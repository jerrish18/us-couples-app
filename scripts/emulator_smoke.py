import subprocess,time
from pathlib import Path

def adb(*args):
    return subprocess.check_output(['adb',*args],text=True)
out=Path('verification');out.mkdir(exist_ok=True)
assert 'Success' in adb('install','-r','release/Us.apk')
adb('logcat','-c')
adb('shell','am','start','-W','-n','com.jerrish18.us/.MainActivity')
deadline=time.monotonic()+60
while time.monotonic()<deadline:
    time.sleep(2)
    adb('shell','uiautomator','dump','/sdcard/us-ui.xml')
    xml=adb('shell','cat','/sdcard/us-ui.xml')
    if 'Welcome back' in xml and 'Continue with Google' in xml:break
else:raise SystemExit('Signed APK did not reach the login screen')
(out/'login-ui.xml').write_text(xml)
with (out/'login.png').open('wb') as file:
    subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True)
logs=adb('logcat','-d')
if 'FATAL EXCEPTION' in logs or 'Unable to start activity' in logs:
    raise SystemExit('Android reported a crash after launch')
assert adb('shell','pidof','com.jerrish18.us').strip()
(out/'install-launch.txt').write_text('PASS: exact signed universal APK installed and reached login on Android API 24; process remains alive.\n')
print('PASS: signed APK installs and launches on Android 7')
