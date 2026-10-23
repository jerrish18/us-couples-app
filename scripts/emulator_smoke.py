import subprocess,time,urllib.request,re,os
from pathlib import Path

def adb(*args):
    return subprocess.check_output(['adb',*args],text=True,timeout=60)
out=Path(os.environ.get('US_VERIFICATION_DIR','verification'));out.mkdir(parents=True,exist_ok=True)
api_level=adb('shell','getprop','ro.build.version.sdk').strip()
print('Installing the previous public release to verify an in-place upgrade',flush=True)
previous=Path('/tmp/Us-previous.apk')
with urllib.request.urlopen('https://github.com/jerrish18/us-couples-app/releases/download/v1.7.0/Us.apk',timeout=60) as response,previous.open('wb') as target:
    while chunk:=response.read(1024*1024):target.write(chunk)
assert 'Success' in adb('install','--no-streaming',str(previous))
old_uid=adb('shell','pm','list','packages','-U','com.jerrish18.us').strip()
print('Installing signed APK update',flush=True)
assert 'Success' in adb('install','--no-streaming','-r','release/Us.apk')
assert old_uid==adb('shell','pm','list','packages','-U','com.jerrish18.us').strip()
print('In-place update succeeded with unchanged app identity; starting app',flush=True)
adb('logcat','-c')
print(adb('shell','am','start','-n','com.jerrish18.us/.MainActivity'),flush=True)
scrolled_login=False
deadline=time.monotonic()+60
while time.monotonic()<deadline:
    time.sleep(2)
    try:adb('shell','uiautomator','dump','/sdcard/us-ui.xml')
    except subprocess.TimeoutExpired:
        (out/'diagnostic.txt').write_text(adb('logcat','-d','-b','all'))
        raise SystemExit('Android UI dump timed out; diagnostics saved')
    xml=adb('shell','cat','/sdcard/us-ui.xml')
    if 'Welcome back' in xml and 'Continue with Google' in xml:break
    if 'Welcome back' in xml and not scrolled_login:
        # Verify Google sign-in remains reachable on a small screen by scrolling.
        with (out/'login-top.png').open('wb') as file:
            subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True)
        dimensions=re.findall(r'(\d+)x(\d+)',adb('shell','wm','size'))[-1]
        width,height=map(int,dimensions)
        adb('shell','input','swipe',str(width//2),str(height*4//5),str(width//2),str(height//3),'400')
        scrolled_login=True
else:
    (out/'last-ui.xml').write_text(xml)
    with (out/'failed-launch.png').open('wb') as file:
        subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True,timeout=30)
    (out/'diagnostic.txt').write_text(adb('logcat','-d','-b','all'))
    raise SystemExit('Signed APK did not reach the login screen')
(out/'login-ui.xml').write_text(xml)
with (out/'login.png').open('wb') as file:
    subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,check=True)
# Exercise Android's actual callback intent while the app is running.
# The denial carries no credentials and must show a retry message, never a crash.
print(adb('shell','am','start','-a','android.intent.action.VIEW','-c','android.intent.category.BROWSABLE','-d','com.jerrish18.us://login-callback?error=access_denied','com.jerrish18.us'),flush=True)
callback_deadline=time.monotonic()+20
while time.monotonic()<callback_deadline:
    time.sleep(1)
    adb('shell','uiautomator','dump','/sdcard/us-callback.xml')
    callback_xml=adb('shell','cat','/sdcard/us-callback.xml')
    if 'Sign-in could not finish' in callback_xml or 'Sign-in could not finish'.replace("'",'&apos;') in callback_xml or 'Start Google sign-in again' in callback_xml:break
else:raise SystemExit('OAuth denial callback did not reach the app error handler')
(out/'oauth-callback-ui.xml').write_text(callback_xml)
logs=adb('logcat' ,'-d','-b','crash')
(out/'crashes.txt').write_text(logs)
if 'FATAL EXCEPTION' in logs or 'Unable to start activity' in logs:
    raise SystemExit('Android reported a crash after launch')
assert adb('shell','pidof','com.jerrish18.us').strip()
(out/'install-launch.txt').write_text(f'PASS: exact signed universal APK installed and reached login on Android API {api_level}; process remains alive.\n')
print(f'PASS: signed APK installs and launches on Android API {api_level}')
