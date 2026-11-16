"""Download official Android command tools and verified Temurin JDK into .tools."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib,json,re,urllib.request,zipfile
import runpy

root=Path(__file__).resolve().parents[1]/'.tools'
root.mkdir(exist_ok=True)

download=runpy.run_path(str(Path(__file__).with_name('download-tools.py')))['download']

def extract(archive,target):
    target.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(archive) as source:
        for member in source.infolist():
            if not (target/member.filename).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe archive path')
        source.extractall(target)

def java():
    try:
        assets=json.load(urllib.request.urlopen('https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows',timeout=30))
        package=assets[0]['binary']['package']
    except urllib.error.HTTPError:
        release=json.load(urllib.request.urlopen('https://api.github.com/repos/adoptium/temurin21-binaries/releases/latest',timeout=30))
        asset=next(a for a in release['assets'] if a['name'].startswith('OpenJDK21U-jdk_x64_windows_hotspot_') and a['name'].endswith('.zip'))
        digest=urllib.request.urlopen(asset['browser_download_url']+'.sha256.txt',timeout=30).read().decode().split()[0]
        package={'link':asset['browser_download_url'],'checksum':digest}
    archive=download(package['link'],root/'temurin-jdk21.zip',package['checksum'])
    extract(archive,root/'java')
    print('JDK ready:',next((root/'java').glob('jdk*')),flush=True)

def android():
    page=urllib.request.urlopen('https://developer.android.com/studio',timeout=30).read().decode()
    url=re.search(r'https://dl\.google\.com/android/repository/commandlinetools-win-[\w.-]+\.zip',page).group()
    archive=download(url,root/'android-command-tools.zip')
    extract(archive,root/'android-command-tools')
    import shutil
    target=root/'android-sdk/cmdline-tools/latest'
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copytree(root/'android-command-tools/cmdline-tools',target,dirs_exist_ok=True)
    print('Android command tools ready',flush=True)

if __name__=='__main__':
    with ThreadPoolExecutor(max_workers=2) as executor:list(executor.map(lambda task:task(),[java,android]))
