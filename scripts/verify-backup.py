"""Exercise pg_dump/pg_restore and private-file restoration on new disposable DBs."""
from pathlib import Path
from uuid import uuid4
import hashlib,io,os,shutil,subprocess,sys,json
import psycopg
from psycopg import sql
from sqlalchemy.engine import make_url
from PIL import Image

root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'backend'))
from app.config import get_settings

url=make_url(get_settings().database_url)
token=uuid4().hex[:12]
names=[f'jain_backup_source_{token}_test',f'jain_backup_restore_{token}_test']
work=root/'.tools/backup-check'/token
work.mkdir(parents=True)
bin_dir=root/'.tools/pgsql/bin'
kwargs={'host':url.host,'port':url.port or 5432,'user':url.username,'password':url.password,'connect_timeout':5}
admin=psycopg.connect(dbname='postgres',autocommit=True,**kwargs)
env=dict(os.environ,PGPASSWORD=url.password or '',PYTHONPATH=str(root/'backend'))
def run(command,extra=None):
    result=subprocess.run(command,cwd=root,env={**env,**(extra or {})},capture_output=True,text=True)
    if result.returncode:raise RuntimeError(f'Backup validation command failed: {Path(command[0]).name}')

try:
    for name in names:admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    run([sys.executable,'-m','alembic','upgrade','head'],{'DATABASE_URL':url.set(database=names[0]).render_as_string(hide_password=False)})
    stream=io.BytesIO();Image.new('RGB',(10,10),'white').save(stream,'PNG');content=stream.getvalue()
    key=uuid4().hex+'.png';source=work/'source-files';source.mkdir();(source/key).write_bytes(content)
    account,profile=uuid4(),uuid4()
    with psycopg.connect(dbname=names[0],**kwargs) as connection:
        connection.execute('INSERT INTO users (id,email) VALUES (%s,%s)',(account,'backup-fixture@example.test'))
        connection.execute("INSERT INTO user_roles (user_id,role_id) SELECT %s,id FROM roles WHERE name='CUSTOMER'",(account,))
        connection.execute("INSERT INTO matrimonial_profiles (id,full_name,gender,date_of_birth,created_by) VALUES (%s,'Backup Fixture','FEMALE','1996-05-12',%s)",(profile,account))
        connection.execute('INSERT INTO account_profile_relationships (account_id,profile_id) VALUES (%s,%s)',(account,profile))
        connection.execute("INSERT INTO documents (profile_id,uploaded_by,storage_key,original_name,media_type,size_bytes,sha256,kind) VALUES (%s,%s,%s,'fixture.png','image/png',%s,%s,'PHOTO')",(profile,account,key,len(content),hashlib.sha256(content).hexdigest()))
    dump=work/'database.dump'
    common=['-h',url.host or '127.0.0.1','-p',str(url.port or 5432),'-U',url.username or 'jain']
    run([str(bin_dir/'pg_dump.exe'),*common,'-d',names[0],'-Fc','-f',str(dump)])
    run([str(bin_dir/'pg_restore.exe'),*common,'-d',names[1],'--no-owner','--exit-on-error',str(dump)])
    restored=work/'restored-files';shutil.copytree(source,restored)
    with psycopg.connect(dbname=names[1],**kwargs) as connection:
        assert connection.execute('SELECT version_num FROM alembic_version').fetchone()[0]=='0005'
        assert connection.execute('SELECT count(*) FROM matrimonial_profiles').fetchone()[0]==1
        assert connection.execute('SELECT count(*) FROM account_profile_relationships').fetchone()[0]==1
        stored_key,digest=connection.execute('SELECT storage_key,sha256 FROM documents').fetchone()
        assert hashlib.sha256((restored/stored_key).read_bytes()).hexdigest()==digest
        assert set(r[0] for r in connection.execute('SELECT name FROM roles'))=={'CUSTOMER','ADMINISTRATOR'}
    report={'result':'passed','revision':'0005','database_restore':True,'private_file_hash_verified':True,'dump_bytes':dump.stat().st_size}
    (work/'result.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
finally:
    for name in names:
        assert name.startswith('jain_backup_') and name.endswith('_test') and token in name
        admin.execute(sql.SQL('DROP DATABASE IF EXISTS {} WITH (FORCE)').format(sql.Identifier(name)))
    admin.close()
