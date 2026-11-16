"""Populate a project-local pub cache from Flutter's pinned dependency versions."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import io
import json
import tarfile
import urllib.request
import yaml

root = Path(__file__).resolve().parents[1]
flutter = root / '.tools/flutter'
cache = root / '.tools/pub-cache'
pins = {}
for file in [flutter / 'packages/flutter_tools/pubspec.yaml',
             *list((flutter / 'packages/flutter_tools/packages').glob('*/pubspec.yaml')),
             flutter / 'packages/flutter/pubspec.yaml', flutter / 'packages/flutter_test/pubspec.yaml']:
    data = yaml.safe_load(file.read_text())
    for section in ('dependencies', 'dev_dependencies'):
        for name, version in (data.get(section) or {}).items():
            if isinstance(version, str) and version[0].isdigit():
                pins[name] = version
            elif isinstance(version, str) and version.startswith('^') and name not in pins:
                pins[name] = version[1:]

for application in ('customer_app', 'admin_app'):
    data = yaml.safe_load((root / application / 'pubspec.yaml').read_text())
    for name, version in data.get('dependencies', {}).items():
        if isinstance(version, str) and name not in pins:
            pins[name] = version.lstrip('^')


def fetch(item):
    name, version = item
    if version is None:
        info = json.load(urllib.request.urlopen(f'https://pub.dev/api/packages/{name}', timeout=45))
        version = info['latest']['version']
    target = cache / 'hosted/pub.dev' / f'{name}-{version}'
    if (target / 'pubspec.yaml').exists():
        return name
    info = json.load(urllib.request.urlopen(f'https://pub.dev/api/packages/{name}', timeout=45))
    release = next(v for v in info['versions'] if v['version'] == version)
    archive = urllib.request.urlopen(release['archive_url'], timeout=90).read()
    digest = hashlib.sha256(archive).hexdigest()
    if digest != release['archive_sha256']:
        raise ValueError(f'Archive checksum mismatch: {name}')
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(archive), mode='r:gz') as package:
        package.extractall(target, filter='data')
    hashes = cache / 'hosted-hashes/pub.dev'
    hashes.mkdir(parents=True, exist_ok=True)
    (hashes / f'{name}-{version}.sha256').write_text(digest)
    metadata = cache / 'hosted/pub.dev/.cache'
    metadata.mkdir(parents=True, exist_ok=True)
    (metadata / f'{name}-versions.json').write_text(json.dumps(info))
    return name


if __name__ == '__main__':
    print(f'Fetching {len(pins)} pinned dependencies', flush=True)
    with ThreadPoolExecutor(max_workers=8) as executor:
        for i, name in enumerate(executor.map(fetch, sorted(pins.items())), 1):
            if i % 20 == 0:
                print(f'{i}/{len(pins)} dependencies cached', flush=True)
    for _ in range(8):
        existing = {yaml.safe_load(f.read_text(encoding='utf-8')).get('name')
                    for f in (cache / 'hosted/pub.dev').glob('*/pubspec.yaml')}
        missing = set()
        for file in (cache / 'hosted/pub.dev').glob('*/pubspec.yaml'):
            data = yaml.safe_load(file.read_text(encoding='utf-8'))
            for name, spec in (data.get('dependencies') or {}).items():
                if name not in existing and (isinstance(spec, str) or spec is None):
                    missing.add(name)
        if not missing:
            break
        print(f'Fetching {len(missing)} transitive packages: {sorted(missing)}', flush=True)
        with ThreadPoolExecutor(max_workers=8) as executor:
            list(executor.map(fetch, ((name, None) for name in missing)))
