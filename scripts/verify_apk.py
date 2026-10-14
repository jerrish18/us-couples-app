import hashlib
import os
import shutil
import subprocess
from pathlib import Path
from zipfile import ZipFile

apk = Path('build/app/outputs/flutter-apk/app-release.apk')
with ZipFile(apk) as z:
    for abi in ['armeabi-v7a', 'arm64-v8a']:
        if f'lib/{abi}/libapp.so' not in z.namelist():
            raise SystemExit(f'Missing required architecture: {abi}')
sdk = Path(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', '')))
tools = sorted((sdk / 'build-tools').glob('*/apksigner'))
if not tools:
    raise SystemExit('Cannot verify Android signature: apksigner missing')
subprocess.run([str(tools[-1]), 'verify', '--verbose', '--print-certs', str(apk)], check=True)
out = Path('release');out.mkdir(exist_ok=True)
target = out / 'Us.apk';shutil.copyfile(apk, target)
(out / 'Us.apk.sha256').write_text(hashlib.sha256(target.read_bytes()).hexdigest() + '  Us.apk\n')
print('Release signature and both ARM architectures verified.')
