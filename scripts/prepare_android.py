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
manifest.write_text(text)
print('Android configured for package com.jerrish18.us, API 24+, with automatic backups disabled.')
