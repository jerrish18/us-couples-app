import subprocess,time
from pathlib import Path

def adb(*args):
    return subprocess.check_output(['adb',*args],text=True,timeout=60)
out=Path('verification');out.mkdir(exist_ok=True)
print('Installing signed APK',flush=True)
assert 'Success' in adb('install','--no-streaming','-r','release/Us.apk')
print('Installation succeeded; starting app',flush=True)
adb('logcat','-c')
print(adb('shell','am','start','-n','com.jerrish18.us/.MainActivity'),flush=True)
deadline=time.monotonic()+60
while time.monotonic()<deadline:
    time.sleep(2)
    try:adb('shell','uiautomator','dump','/sdcard/us-ui.xml')
    except subprocess.TimeoutExpired:
        (out/'diagnostic.txt').write_text(adb('logcat','-d','-b','all'))
        raise SystemExit('Android UI dump timed out; diagnostics saved')
    xml=adb('shell','cat','/sdcard/us-ui.xml')
    if 'Welcome back' in xml and 'Continue with Google' in xml:break
else:
    (out/'last-ui.xml').write_text(xml)
    with (out/'failed-launch.png').open('wb') as file:
        subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True,timeout=30)
    (out/'diagnostic.txt').write_text(adb('logcat','-d','-b','all'))
    raise SystemExit('Signed APK did not reach the login screen')
(out/'login-ui.xml').write_text(xml)
with (out/'login.png').open('wb') as file:
    subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True)
logs=adb('logcat','-d','-b','crash')
(out/'crashes.txt').write_text(logs)
if 'FATAL EXCEPTION' in logs or 'Unable to start activity' in logs:
    raise SystemExit('Android reported a crash after launch')
assert adb('shell','pidof','com.jerrish18.us').strip()
(out/'install-launch.txt').write_text('PASS: exact signed universal APK installed and reached login on Android API 24; process remains alive.\n')
print('PASS: signed APK installs and launches on Android 7')
