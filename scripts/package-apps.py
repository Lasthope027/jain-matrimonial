"""Package successfully built native applications and write SHA-256 checksums."""
from pathlib import Path
import hashlib, shutil, struct, zipfile

root = Path(__file__).resolve().parents[1]
dist = root / 'dist'
dist.mkdir(exist_ok=True)
apk = root / 'customer_app/build/app/outputs/flutter-apk/app-debug.apk'
runner = next((path for path in [root / 'admin_app/build/windows/local/runner',
                               root / 'admin_app/build/windows/x64/runner/Release']
               if (path / 'jain_admin.exe').is_file()), root / 'admin_app/build/windows/local/runner')
for path in [apk, runner / 'jain_admin.exe', runner / 'flutter_windows.dll', runner / 'data/app.so']:
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f'Required native build output missing: {path.relative_to(root)}')
with zipfile.ZipFile(apk) as archive:
    assert 'lib/arm64-v8a/libflutter.so' in archive.namelist()
    assert archive.testzip() is None
exe = (runner / 'jain_admin.exe').read_bytes()
assert exe[:2] == b'MZ' and exe[struct.unpack_from('<I', exe, 0x3c)[0]:][:4] == b'PE\0\0'
shutil.copyfile(apk, dist / 'jain-customer-arm64-debug.apk')
with zipfile.ZipFile(dist / 'jain-admin-windows-x64.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in sorted(runner.rglob('*')):
        if not path.is_file(): continue
        relative = path.relative_to(runner)
        if 'CMakeFiles' in relative.parts or path.suffix.lower() in {'.pdb', '.lib', '.exp', '.cmake', '.obj', '.res'}: continue
        archive.write(path, Path('jain-admin-windows') / relative)
    archive.write(root / 'documentation/installation.md', 'jain-admin-windows/INSTALLATION.md')
    engine_license = root / '.tools/flutter/bin/cache/artifacts/engine/windows-x64-release/LICENSE.windows_flutter.md'
    if engine_license.exists():
        archive.write(engine_license, 'jain-admin-windows/LICENSE.flutter-engine.md')
    runtime = next((root / '.tools/msvc/VC/Redist/MSVC').glob('*/x64/Microsoft.VC143.CRT'), None)
    if runtime is not None:
        for path in sorted(runtime.glob('*.dll')):
            archive.write(path, Path('jain-admin-windows') / path.name)
artifacts = sorted(dist.glob('*.zip')) + sorted(dist.glob('*.apk'))
lines = []
for artifact in artifacts:
    lines.append(hashlib.sha256(artifact.read_bytes()).hexdigest() + '  ' + artifact.name)
    print(artifact.name, artifact.stat().st_size, 'bytes')
(dist / 'SHA256SUMS.txt').write_text('\n'.join(lines) + '\n')
