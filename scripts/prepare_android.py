from pathlib import Path
import re
import shutil

gradle = Path('android/app/build.gradle.kts')
if not gradle.exists():
    raise SystemExit('Expected Flutter Kotlin Gradle template')
text = gradle.read_text()
text, count = re.subn(r'minSdk\s*=\s*flutter.minSdkVersion', 'minSdk = 24', text)
if count != 1:
    raise SystemExit('Android template changed: review minimum SDK before building')
gradle.write_text(text)
manifest = Path('android/app/src/main/AndroidManifest.xml')
text = manifest.read_text().replace('android:label="us"', 'android:label="Us"')
text = text.replace('android:icon="@mipmap/ic_launcher"','android:icon="@drawable/us_icon"')
text = text.replace('</activity>','<meta-data android:name="flutter_deeplinking_enabled" android:value="false"/></activity>',1)
text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application android:enableOnBackInvokedCallback="true" android:allowBackup="false" android:fullBackupContent="false"')
text = text.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <application')
text = text.replace('android:launchMode="singleTop"','android:launchMode="singleTask"')
text = text.replace('</activity>', '<intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="com.jerrish18.us" android:host="login-callback"/></intent-filter></activity>',1)
text = text.replace('</application>', '<receiver android:name=".UsWidgetProvider" android:exported="true"><intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter><meta-data android:name="android.appwidget.provider" android:resource="@xml/us_widget_info"/></receiver></application>')
text = text.replace('</application>',  '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>
    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
      <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter>
    </receiver>
    </application>''')
text = text.replace('<application', '<uses-permission android:name="android.permission.WAKE_LOCK"/><uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/><uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/><uses-permission android:name="android.permission.FOREGROUND_SERVICE"/><uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/><application')
text = text.replace('</activity>', '<intent-filter><action android:name="android.intent.action.SEND"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="text/plain"/><data android:mimeType="image/*"/><data android:mimeType="application/pdf"/></intent-filter><intent-filter><action android:name="android.intent.action.SEND_MULTIPLE"/><category android:name="android.intent.category.DEFAULT"/><data android:mimeType="image/*"/></intent-filter></activity>',1)
manifest.write_text(text)
text = gradle.read_text().replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
text += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n'
gradle.write_text(text)
activity = Path('android/app/src/main/kotlin/com/jerrish18/us/MainActivity.kt')
shutil.copyfile('android_templates/MainActivity.kt',activity)
print('Android configured for package com.jerrish18.us, API 24+, with automatic backups disabled.')

for source, destination in [
 ('UsWidgetProvider.kt','kotlin/com/jerrish18/us/UsWidgetProvider.kt'),
 ('us_widget.xml','res/layout/us_widget.xml'),
 ('us_widget_info.xml','res/xml/us_widget_info.xml'),
 ('us_widget_background.xml','res/drawable/us_widget_background.xml')]:
    destination = Path('android/app/src/main') / destination
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(Path('android_templates') / source,destination)
for icon in ['us_icon','us_notification']:
    shutil.copyfile(Path('android_templates') / (icon+'.xml'),Path('android/app/src/main/res/drawable') / (icon+'.xml'))
for styles in Path('android/app/src/main/res').glob('values*/styles.xml'):
    styles.write_text(re.sub(r'parent="@android:style/Theme.[^"]+"','parent="Theme.AppCompat.DayNight.NoActionBar"',styles.read_text()))

# The plugin allows floating Glance versions; hold the tested stable ABI/API.
root_gradle = Path('android/build.gradle.kts')
root_gradle.write_text(root_gradle.read_text()+'\nsubprojects {\n    configurations.configureEach {\n        resolutionStrategy.eachDependency {\n            if (requested.group == "androidx.glance") useVersion("1.1.1")\n        }\n    }\n}\n')

# WorkManager constructs this Room database through reflection at process startup.
# Preserve its no-argument constructor in the signed R8 release build.
Path('android/app/proguard-rules.pro').write_text(
    '-keep class androidx.work.impl.WorkDatabase_Impl { public <init>(); }\n')
gradle.write_text(gradle.read_text().replace('buildTypes {',
    'buildTypes {\n        release { proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro") }'))

# Dart references this drawable by string, so Android cannot discover its use.
raw=Path('android/app/src/main/res/raw');raw.mkdir(exist_ok=True)
(raw/'keep.xml').write_text('<resources xmlns:tools="http://schemas.android.com/tools" tools:keep="@drawable/us_notification"/>')

# Presentation-only colors for the native widget and launch surface.
for source, destination in [('us_colors.xml','values/us_colors.xml'),('us_colors_night.xml','values-night/us_colors.xml')]:
    target=Path('android/app/src/main/res')/destination
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copyfile(Path('android_templates')/source,target)
for launch in Path('android/app/src/main/res').glob('drawable*/launch_background.xml'):
    launch.write_text('<layer-list xmlns:android="http://schemas.android.com/apk/res/android"><item><shape><gradient android:angle="315" android:startColor="@color/us_widget_start" android:endColor="@color/us_widget_end"/></shape></item></layer-list>')

# Use the same launch identity and accent on Android 12+ system splash screens.
import xml.etree.ElementTree as ET
for styles in Path('android/app/src/main/res').glob('values*/styles.xml'):
    tree=ET.parse(styles)
    for style in tree.getroot().findall('style'):
        if style.get('name')=='LaunchTheme':
            for name,value in [('android:windowSplashScreenBackground','@color/us_widget_start'),('android:windowSplashScreenAnimatedIcon','@drawable/us_icon')]:
                item=style.find(f"item[@name='{name}']")
                if item is None:item=ET.SubElement(style,'item',{'name':name})
                item.text=value
    tree.write(styles,encoding='unicode')

# v1.6 camera / microphone foreground service; started only after foreground consent.
shutil.copyfile('android_templates/UsCallService.kt', Path('android/app/src/main/kotlin/com/jerrish18/us/UsCallService.kt'))
text=manifest.read_text()
text=text.replace('<application', '<uses-permission android:name="android.permission.CAMERA"/><uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/><uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/><uses-permission android:name="android.permission.FOREGROUND_SERVICE_MICROPHONE"/><uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA"/><uses-feature android:name="android.hardware.camera" android:required="false"/><uses-feature android:name="android.hardware.microphone" android:required="false"/><application',1)
text=text.replace('</application>','<service android:name=".UsCallService" android:exported="false" android:foregroundServiceType="microphone|camera"/></application>')
manifest.write_text(text)

# Android 17: LAN permission covers same-Wi-Fi WebRTC; Nearby Devices for headsets.
manifest.write_text(manifest.read_text().replace('<application','<uses-permission android:name="android.permission.ACCESS_LOCAL_NETWORK"/><uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/><application',1))
gradle.write_text(gradle.read_text().replace('compileSdk = flutter.compileSdkVersion','compileSdk = 37').replace('targetSdk = flutter.targetSdkVersion','targetSdk = 37'))
# Preserve JNI methods used by the WebRTC native library in release builds.
rules=Path('android/app/proguard-rules.pro')
rules.write_text(rules.read_text()+'\n-keep class org.webrtc.** { *; }\n-keep class com.cloudwebrtc.webrtc.** { *; }\n')

# On-phone AI uses the existing engine, native WebRTC audio, and offline TTS.
for name in ['EchoPcm.kt','EchoPhoneNative.kt','EchoPhoneService.kt']:
    shutil.copyfile(Path('android_templates')/name,activity.parent/name)
text=manifest.read_text().replace('</application>','<service android:name=".EchoPhoneService" android:exported="false" android:foregroundServiceType="microphone"/></application>')
manifest.write_text(text)
test_dir=Path('android/app/src/test/kotlin/com/jerrish18/us');test_dir.mkdir(parents=True,exist_ok=True)
shutil.copyfile('android_templates/tests/EchoPcmTest.kt',test_dir/'EchoPcmTest.kt')
gradle.write_text(gradle.read_text()+'\ndependencies { testImplementation("junit:junit:4.13.2") }\n')
