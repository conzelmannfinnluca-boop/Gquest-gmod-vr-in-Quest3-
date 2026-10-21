"""Export current own GDroid integration; exclude game/runtime assets and retired weapons."""
from pathlib import Path
import hashlib,json,zipfile,shutil
ROOT=Path(__file__).resolve().parent.parent
files={}
for base,pattern in [("Gquest-Hybrid","*"),("work/gquest-ui","*.lua"),("work/harness","test_hl2*.lua")]:
 for p in (ROOT/base).rglob(pattern):
  if p.is_file() and not p.is_symlink() and not {"target","dist",".git","__pycache__"}.intersection(p.relative_to(ROOT/base).parts):files[str(p.relative_to(ROOT))]=p
names=["work/prepare_weapon_model_overrides.py","work/gquest-weapon-models/manifest.json","work/build_quest_lab.py","work/verify_gdroid_base.py","work/verify_gquest_package.py","work/generate_native_finger_profiles.py","work/gquest_native_fingers.h","work/gquest_native_finger_profiles.h","work/gquest_retired_content.h","work/gquest_vr_lua.h","work/quest_engine_bridge.cpp","work/gdroid-0.1.30-build-pin.json","work/gquest-hl2-authored-fingers.json","work/gquest-native-finger-profile-manifest.json","work/run_lua_checks.py","work/test_reload_client.lua","work/test_gquest_menu_navigation.lua","work/harness/test_native_pose_class.lua","work/gdroid130-compat/audit.json","work/gdroid130-compat/audit.md","work/gdroid130-compat/lua-vr-and-cmdsock-audit.json","work/gdroid130-compat/lua-vr-and-cmdsock-audit.md","work/package_gdroid_source.py"]
for n in names:files[n]=ROOT/n
files["GDroid-0.1.30-README.md"]=ROOT/"outputs/Gquest-GDroid-Source-README.md"
files["README.md"]=ROOT/"outputs/Gquest-GDroid-Source-README.md"
files["BUILD.md"]=ROOT/"outputs/Gquest-GDroid-BUILD.md"
files["docs/Gquest-HL2-only-verification.json"]=ROOT/"outputs/Gquest-HL2-only-verification.json"
files["docs/Gquest-HL2-damage-verification.json"]=ROOT/"outputs/Gquest-HL2-damage-verification.json"
files["docs/Gquest-Feature-Referenz.md"]=ROOT/"outputs/Gquest-Feature-Referenz.md"
stage=ROOT/"Gquest-Source"
# Preserve stale source copies outside the active source folder.
for relative in ["work/gquest-arcvr","work/gquest-right-finger-profiles.json"]:
 old=stage/relative
 if old.exists():
  backup=ROOT/"work/backups/20261021-before-hl2-only/source-copy"/relative
  backup.parent.mkdir(parents=True,exist_ok=True)
  if not backup.exists():shutil.move(str(old),str(backup))
manifest={}
for n,p in sorted(files.items()):
 assert p.is_file(),p
 assert p.suffix.lower() not in {".so",".apk",".jks",".keystore",".mdl",".vtf",".vvd",".vtx",".mp4"},p
 manifest[n]=hashlib.sha256(p.read_bytes()).hexdigest()
 dest=stage/n;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
output=ROOT/"outputs/Gquest-GDroid-0.1.30-Source.zip"
with zipfile.ZipFile(output,"w",zipfile.ZIP_DEFLATED) as z:
 for n,p in sorted(files.items()):z.write(p,n)
 z.writestr("SOURCE-SHA256.json",json.dumps(manifest,indent=2)+"\n")
 assert z.testzip() is None
with zipfile.ZipFile(output) as z:
 for n,h in manifest.items():assert hashlib.sha256(z.read(n)).hexdigest()==h,n
(stage/"GDroid-0.1.30-SOURCE-SHA256.json").write_text(json.dumps(manifest,indent=2)+"\n")
(stage/"SOURCE_FILES.json").write_text(json.dumps({"scope":"current own GDroid integration; other retained files are historical", "files":manifest},indent=2)+"\n")
print(len(files),"own source/doc files;",output.stat().st_size,"bytes; ZIP CRC and all identities verified")
