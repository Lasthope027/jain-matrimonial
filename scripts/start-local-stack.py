"""Keep the local PostgreSQL/API processes together in one foreground session."""
from pathlib import Path
import os, subprocess, sys, time, urllib.request
import psycopg
from sqlalchemy.engine import make_url

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'backend'))
from app.config import get_settings

url = make_url(get_settings().database_url)
kwargs = dict(host=url.host, port=url.port or 5432, user=url.username,
              password=url.password, dbname=url.database, connect_timeout=3)
database = None
api = None
logs = []
try:
    try:
        with psycopg.connect(**kwargs): pass
    except psycopg.OperationalError:
        log = (root / '.tools/local-stack-postgres.log').open('ab')
        logs.append(log)
        database = subprocess.Popen([str(root / '.tools/pgsql/bin/postgres.exe'), '-D',
                                     str(root / '.tools/pgdata'), '-h', '127.0.0.1', '-p', '5432'],
                                    stdout=log, stderr=subprocess.STDOUT,
                                    creationflags=subprocess.CREATE_NO_WINDOW)
        for _ in range(30):
            try:
                with psycopg.connect(**kwargs): pass
                break
            except psycopg.OperationalError:
                if database.poll() is not None: raise RuntimeError('PostgreSQL did not start; inspect .tools/local-stack-postgres.log')
                time.sleep(1)
        else: raise RuntimeError('PostgreSQL startup timed out')
    log = (root / '.tools/local-stack-api.log').open('ab')
    logs.append(log)
    api = subprocess.Popen([sys.executable, '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000'],
                           cwd=root, env=dict(os.environ, PYTHONPATH=str(root / 'backend')),
                           stdout=log, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
    for _ in range(60):
        try:
            with urllib.request.urlopen('http://127.0.0.1:8000/api/v1/ready', timeout=3) as response:
                if response.status == 200: break
        except (OSError, urllib.error.URLError):
            if api.poll() is not None: raise RuntimeError('API did not start; inspect .tools/local-stack-api.log')
            time.sleep(1)
    else: raise RuntimeError('API readiness timed out')
    print('Local API ready: http://127.0.0.1:8000/api/v1/ready (migration 0005)', flush=True)
    print('Keep this terminal running. Press Ctrl+C to stop processes started here.', flush=True)
    while api.poll() is None: time.sleep(1)
finally:
    if api is not None and api.poll() is None:
        api.terminate(); api.wait(timeout=15)
    if database is not None and database.poll() is None:
        subprocess.run([str(root / '.tools/pgsql/bin/pg_ctl.exe'), '-D', str(root / '.tools/pgdata'), '-m', 'fast', 'stop'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        database.wait(timeout=30)
    for log in logs: log.close()
