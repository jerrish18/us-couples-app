import base64
import os
from pathlib import Path

names = ['US_KEYSTORE_B64', 'US_STORE_PASSWORD', 'US_KEY_PASSWORD', 'US_KEY_ALIAS']
if any(not os.environ.get(name) for name in names):
    raise SystemExit('Required signing secrets are missing')
key = Path('android/app/us-release.jks')
key.write_bytes(base64.b64decode(os.environ['US_KEYSTORE_B64'], validate=True))
key.chmod(0o600)
props = Path('android/key.properties')
props.write_text('storeFile=us-release.jks\nstorePassword=' + os.environ['US_STORE_PASSWORD']
    + '\nkeyPassword=' + os.environ['US_KEY_PASSWORD'] + '\nkeyAlias=' + os.environ['US_KEY_ALIAS'] + '\n')
props.chmod(0o600)
gradle = Path('android/app/build.gradle.kts')
text = gradle.read_text()
text = 'import java.util.Properties\nimport java.io.FileInputStream\n\n' + text
position = text.index('android {')
text = text[:position] + 'val releaseKeys = Properties().apply { load(FileInputStream(rootProject.file("key.properties"))) }\n\n' + text[position:]
text = text.replace('android {', '''android {
    signingConfigs {
        create("release") {
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
            storeFile = file(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
        }
    }
''', 1)
old = 'signingConfig = signingConfigs.getByName("debug")'
if old not in text:
    raise SystemExit('Review changed Flutter signing template before release')
text = text.replace(old, 'signingConfig = signingConfigs.getByName("release")')
gradle.write_text(text)
print('Release signing configured without printing signing material.')
