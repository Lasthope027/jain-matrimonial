"""Create a source-only deliverable excluding credentials, uploads and build caches."""
from pathlib import Path
import hashlib, zipfile, os

root = Path(__file__).resolve().parents[1]
destination = root / 'dist'
destination.mkdir(exist_ok=True)
archive = destination / 'jain-matrimonial-source.zip'
folders = {'backend', 'database', 'documentation', 'scripts', 'customer_app', 'admin_app', 'storage'}
files = {'.dockerignore', '.env.example', '.gitignore', 'alembic.ini', 'docker-compose.yml', 'pytest.ini', 'README.md'}
excluded = {'.git', '.dart_tool', 'build', '.gradle', 'ephemeral', '.plugin_symlinks', '__pycache__', '.pytest_cache', '.idea'}
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
    candidates = [root / name for name in files]
    for folder in sorted(folders):
        for directory, children, filenames in os.walk(root / folder):
            children[:] = sorted(name for name in children if name not in excluded)
            candidates.extend(Path(directory) / name for name in sorted(filenames))
    for path in candidates:
        relative = path.relative_to(root)
        if relative.parts[0] not in folders and str(relative) not in files:
            continue
        if any(part in excluded for part in relative.parts): continue
        if not path.is_file() or path.is_symlink(): continue
        if path.name in {'local.properties', 'key.properties', '.flutter-plugins-dependencies', '.env'}: continue
        if path.suffix.lower() in {'.jks', '.keystore', '.pyc', '.iml', '.dump', '.log'}: continue
        if relative.parts[0] == 'storage' and path.name != '.gitkeep': continue
        bundle.write(path, Path('jain-matrimonial') / relative)
with zipfile.ZipFile(archive) as bundle:
    names = bundle.namelist()
    assert names and all('/.env' not in n or n.endswith('/.env.example') for n in names)
    assert all('/.tools/' not in n and '/.venv/' not in n for n in names)
print(f'{archive.name}: {len(names)} source files, {archive.stat().st_size} bytes')
print('SHA256', hashlib.sha256(archive.read_bytes()).hexdigest())
