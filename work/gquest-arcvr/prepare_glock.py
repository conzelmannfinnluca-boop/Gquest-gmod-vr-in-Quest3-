"""Build a private, source-pinned Glock asset slice; do not load the VRMod addon."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import struct

HERE = Path(__file__).resolve().parent
SOURCE = HERE.parent / "arcvr-anniversary"
CONTENT = HERE / "content"
COMMIT = "0d8d5bed01c77ad1550097689dc0d1e6fc035385"

def header(path):
    b = path.read_bytes()
    def u(off): return struct.unpack_from("<I", b, off)[0]
    def string(off): return b[off:b.index(0, off)].decode("utf-8", "replace")
    assert b[:4] == b"IDST" and u(4) == 48, path
    textures = [string(u(208) + i * 64 + u(u(208) + i * 64)) for i in range(u(204))]
    dirs = [string(u(u(216) + i * 4)).replace("\\", "/") for i in range(u(212))]
    bones = [string(u(160) + i * 216 + u(u(160) + i * 216)) for i in range(u(156))]
    return {"version": u(4), "checksum": u(8), "bones": bones, "textures": textures, "texture_dirs": dirs}

models = ["pistol_glock", "mag_glock", "9mmbullet", "9mmcase"]
records, metadata, unresolved = [], {}, []
files = set()
for name in models:
    stem = "models/weapons/arcticvr/aniv/" + name
    rel = stem + ".mdl"
    data = header(SOURCE / rel)
    metadata[rel] = data
    # Android Source uses DX90 VTX data; retain PHY only where present and valid.
    for ext in (".mdl", ".vvd", ".dx90.vtx", ".phy"):
        path = SOURCE / (stem + ext)
        if not path.exists():
            assert ext == ".phy", path
            continue
        b = path.read_bytes()
        offset = {".vvd": 8, ".dx90.vtx": 16, ".phy": 12}.get(ext)
        if offset is not None:
            assert struct.unpack_from("<I", b, offset)[0] == data["checksum"], path
        files.add(stem + ext)
    for tex in data["textures"]:
        candidates = ["materials/" + d + tex + ".vmt" for d in data["texture_dirs"]]
        found = next((r for r in candidates if (SOURCE / r).is_file()), None)
        if found:
            files.add(found)
            vmt = (SOURCE / found).read_text()
            for key, value in re.findall(r'"(\$[^" ]+)"\s*"([^"\n]+)"', vmt):
                if key.lower() in ("$basetexture", "$bumpmap", "$detail", "$envmapmask"):
                    dep = "materials/" + value.replace("\\", "/") + ".vtf"
                    if (SOURCE / dep).is_file(): files.add(dep)
                    else: unresolved.append({"model": rel, "texture_dependency": dep})
        else:
            unresolved.append({"model": rel, "material_candidates": candidates})

glock_lua = SOURCE / "lua/weapons/arcticvr_aniv_glock/shared.lua"
mag_lua = SOURCE / "lua/arcticvr/magazines/glock_17_aniv.lua"
expected_bones = ["pistol", "magazine", "trigger", "slide", "bullet", "selector", "muzzle", "eject", "slidelock", "foregrip"]
assert metadata["models/weapons/arcticvr/aniv/pistol_glock.mdl"]["bones"] == expected_bones
text = glock_lua.read_text()
for name, value in {"DamageMin": 15, "DamageMax": 30, "RPM": 1200, "MaxRange": 6000,
                    "Penetration": 4, "MuzzleVelocity": 200000}.items():
    assert re.search(r"SWEP\." + name + r"\s*=\s*" + str(value) + r"\b", text)
assert "SWEP.Primary.ClipSize = 17" in text
assert "offsetPos = Vector(-4.9, -4, 1.3)" in text
assert "offsetAng = Angle(10, 0, 0)" in text
assert "mag.Capacity = 17" in mag_lua.read_text()

for rel in sorted(files):
    path = SOURCE / rel
    destination = CONTENT / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(path, destination)
    b = path.read_bytes()
    records.append({"path": rel, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest()})
manifest = {
    "repository": "https://github.com/Pescorr/arcvr_anniversary_bugfix_beta",
    "commit": COMMIT, "private_lab_only": True,
    "source_files": {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (glock_lua, mag_lua)},
    "weapon": {"class": "arcticvr_aniv_glock", "damage_min": 15, "damage_max": 30,
        "rpm": 1200, "magazine_capacity": 17, "primary_default_clip": 1000, "max_range": 6000,
        "penetration": 4, "muzzle_velocity": 200000, "spread": "1/105", "firemodes": [1,-3,0],
        "offset_pos": [-4.9,-4,1.3], "offset_ang": [10,0,0], "magazine_pose_pos": [-6.5,3.2,-5],
        "magazine_pose_ang": [0,0,90]},
    "models": metadata, "files": records, "unresolved_materials": unresolved,
    "external_content": ["models/weapons/w_pist_glock18.mdl", "sound/weapons/glock/glock18-1.wav",
        "sound/weapons/glock/glock_slideback.wav", "sound/weapons/glock/glock_sliderelease.wav",
        "sound/weapons/glock/glock_clipin.wav", "sound/weapons/glock/glock_clipout.wav"],
    "not_included": "Original autoruns/server receivers; these require the VRMod runtime and physical pickup system."
}
stock_evidence = HERE.parent / "gquest-arcvr-stock-dependencies.json"
if stock_evidence.is_file():
    manifest["existing_user_content_evidence"] = json.loads(stock_evidence.read_text())
    manifest["external_content_note"] = "Glock material, worldmodel and three main sounds found in existing user VPKs; actual Quest mount/material parser still requires runtime check."
(HERE / "glock_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps({"files": len(records), "bytes": sum(x["bytes"] for x in records), "unresolved": len(unresolved)}))
