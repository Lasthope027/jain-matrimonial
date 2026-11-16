"""Populate a project-local Android SDK using Google's repository metadata."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import hashlib, runpy, urllib.request, xml.etree.ElementTree as ET, zipfile, sys

root = Path(__file__).resolve().parents[1] / '.tools'
fetch = runpy.run_path(str(Path(__file__).with_name('download-tools.py')))['download']
repository = ET.fromstring(urllib.request.urlopen('https://dl.google.com/android/repository/repository2-3.xml', timeout=60).read())
sdk = root / 'android-sdk'
downloads = root / 'android-downloads'
downloads.mkdir(exist_ok=True)

def task(identifier):
    package = next(p for p in repository.findall('remotePackage')
                   if p.get('path') == identifier and p.find('channelRef').get('ref') == 'channel-0')
    archive = next(a.find('complete') for a in package.findall('archives/archive')
                   if a.findtext('host-os', 'windows') == 'windows')
    name = archive.findtext('url')
    path = fetch('https://dl.google.com/android/repository/' + name, downloads / name)
    if hashlib.sha1(path.read_bytes()).hexdigest() != archive.findtext('checksum'):
        raise ValueError('Google repository checksum mismatch')
    destination = sdk.joinpath(*identifier.split(';'))
    with zipfile.ZipFile(path) as source:
        for member in source.infolist():
            relative = Path(*Path(member.filename).parts[1:])
            target = (destination / relative).resolve()
            if not target.is_relative_to(destination.resolve()): raise ValueError('Unsafe SDK path')
            if not member.is_dir():
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(source.read(member))
    license_id = package.find('uses-license').get('ref')
    license_text = next(p.text.strip() for p in repository.findall('license') if p.get('id') == license_id)
    licenses = sdk / 'licenses'
    licenses.mkdir(exist_ok=True)
    (licenses / license_id).write_text(hashlib.sha1(license_text.encode()).hexdigest() + '\n')
    print(f'Cached {identifier}', flush=True)

with ThreadPoolExecutor(max_workers=3) as pool:
    list(pool.map(task, sys.argv[1:] or ['platform-tools', 'platforms;android-36', 'build-tools;36.0.0']))
