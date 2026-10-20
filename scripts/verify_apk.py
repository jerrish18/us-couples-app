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
signature = subprocess.check_output([str(tools[-1]), 'verify', '--verbose', '--print-certs', str(apk)],text=True)
expected = '6daa58c1d39fe99deb2dc344db77c9a7f108014ad23dd17f20bca342c32547c0'
if expected not in signature.lower().replace(':',''):
    raise SystemExit('APK is signed by an unexpected certificate')
print(signature)
aapt = tools[-1].parent / 'aapt'
resources = subprocess.check_output([str(aapt),'dump','resources',str(apk)],text=True)
if 'drawable/us_notification' not in resources:
    raise SystemExit('Notification icon was stripped from the release APK')
badging = subprocess.check_output([str(aapt),'dump','badging',str(apk)],text=True)
if "versionCode='6'" not in badging or "sdkVersion:'24'" not in badging or "name='com.jerrish18.us'" not in badging:
    raise SystemExit('APK package or minimum Android version is incorrect')
out = Path('release');out.mkdir(exist_ok=True)
target = out / 'Us.apk';shutil.copyfile(apk, target)
(out / 'Us.apk.sha256').write_text(hashlib.sha256(target.read_bytes()).hexdigest() + '  Us.apk\n')
print('Release signature and both ARM architectures verified.')
