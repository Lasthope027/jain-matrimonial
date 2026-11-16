"""Download universal Flutter artifacts using Python's working HTTPS client."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import io
import tarfile
import urllib.request
import zipfile

sdk = Path(__file__).resolve().parents[1] / '.tools/flutter'
cache = sdk / 'bin/cache'
version = (sdk / 'bin/internal/engine.version').read_text().strip()
base = f'https://storage.googleapis.com/flutter_infra_release/flutter/{version}/'
items = []
for name in ('material_fonts', 'gradle_wrapper'):
    path = (sdk / f'bin/internal/{name}.version').read_text().strip()
    items.append((f'https://storage.googleapis.com/{path}', cache / f'artifacts/{name}', name, path))
for name in ('sky_engine', 'flutter_gpu'):
    items.append((base + name + '.zip', cache / 'pkg', None, None))
for artifact, directory in [('flutter_patched_sdk.zip','common'),('flutter_patched_sdk_product.zip','common'),('windows-x64/artifacts.zip','windows-x64'),('windows-x64/font-subset.zip','windows-x64')]:
    items.append((base + artifact, cache / f'artifacts/engine/{directory}', None, None))


def fetch(item):
    url, target, stamp, revision = item
    download = cache / 'downloads' / url.rsplit('/', 1)[1]
    download.parent.mkdir(parents=True, exist_ok=True)
    if not download.exists():
        with urllib.request.urlopen(url, timeout=120) as response, download.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
    target.mkdir(parents=True, exist_ok=True)
    if url.endswith('.tgz'):
        with tarfile.open(download) as archive:
            archive.extractall(target, filter='data')
    else:
        with zipfile.ZipFile(download) as archive:
            archive.extractall(target)
    if stamp:
        if stamp == 'gradle_wrapper':
            for name in ('gradle/wrapper/gradle-wrapper.properties', 'NOTICE'):
                (target / name).unlink(missing_ok=True)
        (cache / f'{stamp}.stamp').write_text(revision)
    print(f'Cached {url.rsplit("/",1)[1]}', flush=True)


with ThreadPoolExecutor(max_workers=6) as executor:
    list(executor.map(fetch, items))
for stamp in ('flutter_sdk', 'font-subset'):
    (cache / f'{stamp}.stamp').write_text(version)
