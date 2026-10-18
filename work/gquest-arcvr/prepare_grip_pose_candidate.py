"""Private model-only A/B; compensate the observed animated root, not tracking."""
from pathlib import Path
import hashlib
import json
import shutil
import struct

HERE = Path(__file__).resolve().parent
proof = json.loads((HERE / "grip_roundtrip.json").read_text())
observed = json.loads((HERE / "observed_glock_rest_root.json").read_text())
assert len(observed["samples"]) >= 2
assert all(s["max_error_from_rz90_bind"] < 0.002 for s in observed["samples"])

def multiply(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]

def inverse(a):
    result = [[a[j][i] for j in range(3)] + [0.] for i in range(3)] + [[0.,0.,0.,1.]]
    for i in range(3):
        result[i][3] = -sum(result[i][j]*a[j][3] for j in range(3))
    return result

idle = json.loads((HERE.parent / "gquest-glock-idle-root-audit.json").read_text())
root = idle["matrix"]
assert all(max(abs(s["actual"][i][j]-root[i][j]) for i in range(4) for j in range(4)) < 0.002 for s in observed["samples"])
attachment = multiply(inverse(root), inverse(proof["source_offset_matrix"]))
values = struct.unpack("<12f", struct.pack("<12f", *[attachment[i][j] for i in range(3) for j in range(4)]))
attachment = [list(values[i*4:(i+1)*4]) for i in range(3)] + [[0.,0.,0.,1.]]
check = multiply(proof["source_offset_matrix"], multiply(root, attachment))
error = max(abs(check[i][j] - float(i == j)) for i in range(4) for j in range(4))
assert error < 2e-5

original = HERE / "content/models/weapons/gquest_arcvr/pistol_glock.mdl"
data = bytearray(original.read_bytes())
assert hashlib.sha256(data).hexdigest() == proof["derived_sha256"]
count, index = struct.unpack_from("<II", data, 240)
assert count == 5
record = index + 4*92
name_offset = record + struct.unpack_from("<i", data, record)[0]
assert data[name_offset:data.index(0, name_offset)] == b"grip"
assert struct.unpack_from("<I", data, record+8)[0] == 0
struct.pack_into("<12f", data, record+12, *values)
data[12:76] = b"weapons/gquest_arcvr/pistol_glock_posefix.mdl".ljust(64, b"\0")

destination = HERE.parent / "gquest-weapon-pose-candidate/content/models/weapons/gquest_arcvr/pistol_glock_posefix.mdl"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_bytes(data)
for suffix in (".vvd", ".dx90.vtx", ".phy"):
    source = original.with_suffix(suffix)
    if source.is_file():
        shutil.copyfile(source, destination.with_suffix(suffix))
report = {"model": str(destination), "candidate_sha256": hashlib.sha256(data).hexdigest(),
          "baseline_sha256": proof["derived_sha256"], "animated_root": root,
          "local_grip_matrix": attachment, "roundtrip_max_error": error,
          "equation": "SourceOffset * AnimatedRoot * LocalGrip = identity",
          "scope": "Model attachment and private model name only. No mesh, material, animation, checksum, scale, tracking or hand edits.",
          "runtime_verified": False}
(destination.parents[4] / "candidate.json").write_text(json.dumps(report, indent=2)+"\n")
print(json.dumps(report))
