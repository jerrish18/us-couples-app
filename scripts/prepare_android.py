from pathlib import Path
import re

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
text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application android:allowBackup="false" android:fullBackupContent="false"')
text = text.replace('<application', '<uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.USE_BIOMETRIC"/>\n    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n    <application')
text = text.replace('</application>', '''<receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
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
