"""Align the pinned sharing plugin's Java and Kotlin targets with the host build.

The dependency is resolved first; this modifies only the ephemeral runner copy.
Its upstream 1.8.1 defaults target Java 11 while Flutter's host selects Kotlin 17.
"""
import json
from pathlib import Path
from urllib.parse import unquote, urlparse

config=Path('.dart_tool/package_config.json')
packages=json.loads(config.read_text())['packages']
package=next(p for p in packages if p['name']=='receive_sharing_intent')
uri=urlparse(package['rootUri'])
root=Path(unquote(uri.path)) if uri.scheme=='file' else (config.parent/package['rootUri']).resolve()
gradle=root/'android/build.gradle'
text=gradle.read_text()
assert 'compileSdk 34' in text, 'Review compatibility before changing the pinned sharing dependency'
marker='// Us: consistent Java and Kotlin bytecode targets'
if marker not in text:
    gradle.write_text(text+'\n'+marker+'''\nandroid {
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = '17' }
}
''')
print('Sharing plugin Java/Kotlin compatibility configured.')

# ECHO's native microphone replacement processes a mono buffer. Force mono
# input at the device module so no second microphone channel can escape it.
webrtc=next(p for p in packages if p['name']=='flutter_webrtc')
webrtc_uri=urlparse(webrtc['rootUri'])
webrtc_root=Path(unquote(webrtc_uri.path)) if webrtc_uri.scheme=='file' else (config.parent/webrtc['rootUri']).resolve()
handler=webrtc_root/'android/src/main/java/com/cloudwebrtc/webrtc/MethodCallHandlerImpl.java'
source=handler.read_text()
assert '.setUseStereoInput(true)' in source or '.setUseStereoInput(false)' in source, 'Review WebRTC mono input configuration'
handler.write_text(source.replace('.setUseStereoInput(true)', '.setUseStereoInput(false)'))
print('WebRTC mono capture configured for safe on-phone AI audio replacement.')
