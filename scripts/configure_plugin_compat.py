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
