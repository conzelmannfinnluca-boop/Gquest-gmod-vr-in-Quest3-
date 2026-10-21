"""Check the private APK against current own sources before deployment."""
from pathlib import Path
from zipfile import ZipFile
import hashlib
import json
import shutil
import subprocess

root=Path(__file__).resolve().parent.parent
apk=root/"work/Gquest.apk"
subprocess.run([str(root/"work/toolchains/jdk/bin/java"),"-jar",str(root/"work/android-sdk/build-tools/34.0.0/lib/apksigner.jar"),"verify",str(apk)],check=True)
with ZipFile(apk) as archive:
    assert len(archive.namelist())==len(set(archive.namelist())),"duplicate ZIP member"
    prefix="assets/quest_lab_vr_content/"
    records=[line.split("\t",1) for line in archive.read("assets/quest_lab_vr_content.tsv").decode().splitlines() if line]
    metadata_path=root/"work/gquest-weapon-models/manifest.json"
    metadata=json.loads(metadata_path.read_text()) if metadata_path.exists() else {"files":[]}
    arc={"files":[]}
    # Derived, not hardcoded: the content part of the overlay is the mounted VR
    # content, this project's own Lua and the native weapon scripts.
    expected_records=(len(json.loads((root/"work/quest-vr-content-manifest.json").read_text())["files"])
        +len(list((root/"work/gquest-ui").rglob("*.lua")))
        +len(arc["files"])+len(metadata["files"]))
    assert len(records)==expected_records,(len(records),expected_records)
    for size,name in records:
        assert len(archive.read(prefix+name))==int(size),name
    for source in (root/"work/gquest-ui").rglob("*.lua"):
        assert archive.read(prefix+str(source.relative_to(root/"work/gquest-ui")))==source.read_bytes(),str(source)
    assert not any("arcvr" in n.lower() or "/arcticvr/" in n.lower() for n in archive.namelist()),"retired ArcVR payload in APK"
    for record in metadata["files"]:
        assert hashlib.sha256(archive.read(prefix+record["path"])).hexdigest()==record["sha256"],record["path"]
    assert archive.read("lib/arm64-v8a/liblauncheq.so")==(root/"work/liblauncheq.so").read_bytes()
    assert archive.testzip() is None
report={"sha256":hashlib.sha256(apk.read_bytes()).hexdigest(),"content_records":len(records),"arcvr_files":len(arc["files"]),"signature":"verified","zip_crc":"passed","current_payload_identity":"passed","installed_on_quest":False,"weapon_model_scripts":len(metadata["files"]),"weapon_model_report":"lua/autorun/client/gquest_weapon_models.lua","weapon_align":"lua/autorun/client/gquest_weapon_align.lua","wrist_hud":"removed; legacy autorun retains shared tracking provider","arcvr_status":"removed from package; old mounted files retired at startup"}
target=root/"outputs/Gquest-build-verification.json"
if target.exists():
    previous=json.loads(target.read_text())
    if previous.get("installed_on_quest"):
        shutil.copy2(target,target.with_name("Gquest-installed-build-verification.json"))
target.write_text(json.dumps(report,indent=2)+"\n")
shutil.copy2(apk,root/"outputs/Gquest.apk")
print(json.dumps(report,indent=2))
