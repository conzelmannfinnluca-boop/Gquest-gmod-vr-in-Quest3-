"""Export only own hybrid source and integration tests."""
import hashlib
import json
from pathlib import Path
import zipfile
PROJECT = Path(__file__).resolve().parents[1]
output = PROJECT.parent / 'outputs/Gquest-Rust-GDroid-Source.zip'
files = sorted(p for p in PROJECT.rglob('*') if p.is_file() and not p.is_symlink()
               and not {'target', 'dist', '__pycache__', '.git'}.intersection(p.relative_to(PROJECT).parts))
manifest = {str(p.relative_to(PROJECT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for p in files:
        archive.write(p, Path(PROJECT.name) / p.relative_to(PROJECT))
    archive.writestr(PROJECT.name + '/SOURCE-SHA256.json', json.dumps(manifest, indent=2) + '\n')
    assert archive.testzip() is None
print(output, output.stat().st_size, 'bytes;', len(files), 'source files')
