import subprocess,time
from pathlib import Path
out=Path('verification');out.mkdir(exist_ok=True)
def adb(*args):
    return subprocess.check_output(['adb',*args],text=True,timeout=60,stderr=subprocess.STDOUT)
try:
    print(adb('install','--no-streaming','-r','release/Us.apk'),flush=True)
    adb('logcat','-c')
    adb('shell','input','keyevent','KEYCODE_HOME')
    print(adb('shell','am','start','-W','-n','com.jerrish18.us/.MainActivity'),flush=True)
    time.sleep(12)
    print(adb('shell','dumpsys','activity','activities'),flush=True)
    adb('shell','uiautomator','dump','/sdcard/probe.xml')
    (out/'probe-ui.xml').write_text(adb('shell','cat','/sdcard/probe.xml'))
finally:
    for name,args in [('logcat',('logcat','-d','-b','all')),('crashes',('logcat','-d','-b','crash'))]:
        (out/(name+'.txt')).write_text(adb(*args))
    with (out/'probe.png').open('wb') as file:
        subprocess.run(['adb','exec-out','screencap','-p'],stdout=file,timeout=30)
    print(adb('logcat','-d','-b','crash'),flush=True)
