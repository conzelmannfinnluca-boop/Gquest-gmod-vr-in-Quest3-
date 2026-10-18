"""Append a mathematically calibrated grip attachment to a private model copy."""
from pathlib import Path
import hashlib
import json
import math
import shutil
import struct
import sys
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from gquest_decode_idle_root import decode_idle_root
SOURCE = HERE.parent / "arcvr-anniversary"
original = SOURCE / "models/weapons/arcticvr/aniv/pistol_glock.mdl"
b = bytearray(original.read_bytes())
def u(off): return struct.unpack_from("<I", b, off)[0]
def mat(values): return [list(values[i*4:(i+1)*4]) for i in range(3)] + [[0.,0.,0.,1.]]
def mul(a,c): return [[sum(a[i][k]*c[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
def inverse(a):
    result = [[a[j][i] for j in range(3)] + [0.] for i in range(3)] + [[0.,0.,0.,1.]]
    for i in range(3): result[i][3] = -sum(result[i][j]*a[j][3] for j in range(3))
    return result
assert b[:4] == b"IDST" and u(4) == 48
checksum = u(8)
root = u(160)
# studio bone poseToBone is model-to-bind-bone; its inverse is root bind pose.
model_to_bone = mat(struct.unpack_from("<12f", b, root+96))
bone_to_model = inverse(model_to_bone)
idle = decode_idle_root(original)
animated_root = idle["matrix"]
pitch = math.radians(10)
c,s = math.cos(pitch), math.sin(pitch)
# Source LocalToWorld: x forward, y left, z up, angle (pitch10,yaw0,roll0).
offset = [[c,0,s,-4.9],[0,1,0,-4],[-s,0,c,1.3],[0,0,0,1]]
# The authored idle root is not the bind pose: its additional 90-degree yaw
# must be included in the attachment's bone-local calibration. A per-model
# 3.5-unit rearward translation was then confirmed by the wearer on Quest.
backshift = [[1.,0.,0.,3.5],[0.,1.,0.,0.],[0.,0.,1.,0.],[0.,0.,0.,1.]]
calibrated_offset = mul(offset, inverse(backshift))
desired_grip = mul(backshift, inverse(offset))
attachment = mul(inverse(animated_root), desired_grip)
attachment = mat(struct.unpack("<12f", struct.pack("<12f", *[attachment[i][j] for i in range(3) for j in range(4)])))
roundtrip = mul(calibrated_offset, mul(animated_root, attachment))
error = max(abs(roundtrip[i][j] - float(i == j)) for i in range(4) for j in range(4))
assert error < 2e-5, error
count, old = u(240), u(244)
assert count == 4
records, names = [], []
for i in range(count):
    start = old+92*i
    record = bytearray(b[start:start+92])
    name_offset = start+struct.unpack_from("<i",record,0)[0]
    name = bytes(b[name_offset:b.index(0,name_offset)])
    records.append(record)
    names.append(name)
record = bytearray(92)
struct.pack_into("<II12f",record,4,0,0,*[attachment[i][j] for i in range(3) for j in range(4)])
records.append(record)
names.append(b"grip")
while len(b)%4: b.append(0)
new_index = len(b)
name_index = new_index+len(records)*92
name_blob = bytearray()
for i,(record,name) in enumerate(zip(records,names)):
    struct.pack_into("<i",record,0,name_index+len(name_blob)-(new_index+92*i))
    name_blob.extend(name+b"\0")
for record in records: b.extend(record)
b.extend(name_blob)
struct.pack_into("<II",b,240,len(records),new_index)
struct.pack_into("<I",b,76,len(b))
name = b"weapons/gquest_arcvr/pistol_glock_posefix2.mdl"
b[12:76] = name.ljust(64,b"\0")
assert u(8) == checksum
target = HERE / "content/models/weapons/gquest_arcvr/pistol_glock_posefix2.mdl"
target.parent.mkdir(parents=True,exist_ok=True)
target.write_bytes(b)
for ext in (".vvd",".dx90.vtx",".phy"):
    source = original.with_suffix(ext)
    if source.exists(): shutil.copyfile(source,target.with_suffix(ext))
proof = {"original":str(original.relative_to(SOURCE)),"derived":str(target.relative_to(HERE/"content")),
    "original_sha256":hashlib.sha256(original.read_bytes()).hexdigest(),
    "derived_sha256":hashlib.sha256(b).hexdigest(),"checksum_preserved":checksum,
    "grip_bone":0,"model_to_bone":model_to_bone,"source_offset_matrix":offset,
    "animated_root_matrix":animated_root,"idle_animation":idle,
    "calibrated_offset_matrix":calibrated_offset,"model_local_translation_delta":[-3.5,0,0],
    "local_grip_matrix":attachment,"roundtrip_max_error":error,
    "equation":"CalibratedOffset * AnimatedIdleRoot * LocalGrip == identity",
    "runtime_status":"Same model/attachment tested in live session1792172326: wearer confirms improved orientation and final distance. Other weapons require separate visual checks."}
(HERE/"grip_roundtrip.json").write_text(json.dumps(proof,indent=2)+"\n")
print(json.dumps({"model":str(target),"attachments":len(records),"error":error,"checksum":hex(checksum)}))
