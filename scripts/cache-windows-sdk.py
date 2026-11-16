"""Extract official Windows SDK payloads locally without installing a system MSI."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json, runpy, subprocess, shutil, os, sys

root = Path(__file__).resolve().parents[1]
tools = root / '.tools'
fetch = runpy.run_path(str(root / 'scripts/download-tools.py'))['download']
packages = json.loads((tools / 'vs-manifest.json').read_text(encoding='utf-8-sig'))['packages']
package = next(p for p in packages if p['id'] == 'Win11SDK_10.0.26100')
payloads = {Path(p['fileName']).name: p for p in package['payloads']}
names = [
    'Windows SDK Desktop Headers x86-x86_en-us.msi',
    'Windows SDK Desktop Headers x64-x86_en-us.msi',
    'Windows SDK Desktop Libs x64-x86_en-us.msi',
    'Windows SDK for Windows Store Apps Headers-x86_en-us.msi',
    'Windows SDK for Windows Store Apps Libs-x86_en-us.msi',
    'Universal CRT Headers Libraries and Sources-x86_en-us.msi',
    'Windows SDK Desktop Tools x64-x86_en-us.msi',
    'Windows SDK for Windows Store Apps Tools-x86_en-us.msi',
    'Windows SDK for Windows Store Apps Headers OnecoreUap-x86_en-us.msi',
]
downloads = tools / 'windows-sdk-downloads'
downloads.mkdir(exist_ok=True)

def obtain(name):
    p = payloads[name]
    return fetch(p['url'], downloads / name, p['sha256'].lower())

def task(name):
    msi = obtain(name)
    layout = msi.with_suffix('.json')
    subprocess.run([os.environ.get('JAIN_PWSH', 'pwsh.exe'), '-NoProfile', '-File', str(root / 'scripts/export-msi-layout.ps1'),
                    '-Msi', str(msi), '-Output', str(layout)], check=True, capture_output=True)
    data = json.loads(layout.read_text(encoding='utf-8-sig'))
    scratch = downloads / (msi.stem + '-files')
    scratch.mkdir(exist_ok=True)
    for row in data['Media']:
        if not row[0]: continue
        cabinet = obtain(row[0])
        subprocess.run([r'C:\Windows\System32\expand.exe', str(cabinet), '-F:*', str(scratch)],
                       check=True, capture_output=True)
    directories = {row[0]: row[1:] for row in data['Directory']}
    components = dict(data['Component'])

    def directory(key):
        if key == 'TARGETDIR': return tools / 'windows-sdk'
        parent, value = directories[key]
        return directory(parent) / value.split(':')[0].split('|')[-1]

    for key, component, filename in data['File']:
        source = scratch / key
        target = (directory(components[component]) / filename.split('|')[-1]).resolve()
        if not target.is_relative_to((tools / 'windows-sdk').resolve()):
            raise ValueError('Unsafe SDK path')
        if source.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
    print(f'Extracted {name}', flush=True)

with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(task, sys.argv[1:] or names))
