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
text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application android:allowBackup="false" android:fullBackupContent="false"')
text = text.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <application')
text = text.replace('</activity>', '<intent-filter><action android:name="android.intent.action.VIEW"/><category android:name="android.intent.category.DEFAULT"/><category android:name="android.intent.category.BROWSABLE"/><data android:scheme="com.jerrish18.us" android:host="login-callback"/></intent-filter></activity>',1)
text = text.replace('</application>', '<receiver android:name=".UsWidgetProvider" android:exported="true"><intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter><meta-data android:name="android.appwidget.provider" android:resource="@xml/us_widget_info"/></receiver></application>')
text = text.replace('</application>',  '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"/>
    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
      <intent-filter><action android:name="android.intent.action.BOOT_COMPLETED"/><action android:name="android.intent.action.MY_PACKAGE_REPLACED"/></intent-filter>
    </receiver>
    </application>''')
manifest.write_text(text)
text = gradle.read_text().replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true')
text += '\ndependencies { coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4") }\n'
gradle.write_text(text)
activity = Path('android/app/src/main/kotlin/com/jerrish18/us/MainActivity.kt')
activity.write_text(activity.read_text().replace('FlutterActivity', 'FlutterFragmentActivity'))
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
