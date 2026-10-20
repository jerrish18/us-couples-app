"""Guard unrelated services and established navigation. v1.6 explicitly adds cycle care and expands media support."""
import hashlib,json,re
from pathlib import Path
manifest=json.loads(Path('docs/ui-scope.json').read_text())
for name,expected in manifest['frozen_files'].items():
    assert hashlib.sha256(Path(name).read_bytes()).hexdigest()==expected, f'Non-UI file changed: {name}'
actual=re.findall(r"path:\s*'(/[^']*)'",Path('lib/main.dart').read_text())
assert sorted(actual)==sorted(manifest['navigation_destinations']), 'Navigation destinations changed'
print(f"PASS: {len(manifest['frozen_files'])} backend/service files and all navigation destinations unchanged")
