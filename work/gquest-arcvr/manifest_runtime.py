"""Checksum all private ArcVR slice files for APK or runtime content staging."""
from pathlib import Path
import hashlib
import json
HERE = Path(__file__).resolve().parent
records = []
for path in sorted((HERE / "content").rglob("*")):
    if not path.is_file(): continue
    b = path.read_bytes()
    records.append({"path": str(path.relative_to(HERE / "content")), "bytes": len(b),
                    "sha256": hashlib.sha256(b).hexdigest()})
manifest = {"source_commit": "0d8d5bed01c77ad1550097689dc0d1e6fc035385",
            "private_lab_only": True, "source_weapon": "arcticvr_aniv_glock",
            "adapted_weapon": "gquest_arcvr_aniv_glock", "files": records,
            "total_bytes": sum(r["bytes"] for r in records), "runtime_verified": False,
            "limitations": "Singleplayer shooting slice; explicit test insertion/rack/eject; no physical reload or complete ArcVR compatibility."}
(HERE / "runtime_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({"files": len(records), "bytes": manifest["total_bytes"]}))
