"""Verify the pinned official base and every linked native dependency."""
from pathlib import Path
import hashlib,json,struct,zipfile
ROOT=Path(__file__).resolve().parent.parent
pin=json.loads((ROOT/"work/gdroid-0.1.30-build-pin.json").read_text())
apk=ROOT/"outputs/GDroid-0.1.30.apk"
assert hashlib.sha256(apk.read_bytes()).hexdigest()==pin["apk_sha256"]
with zipfile.ZipFile(apk) as z:
    for name,digest in pin["native_sha256"].items():
        packaged=z.read("lib/arm64-v8a/"+name)
        linked=(ROOT/"work/gdroid-0.1.30-native"/name).read_bytes()
        assert packaged==linked and hashlib.sha256(linked).hexdigest()==digest,name
    client=z.read("lib/arm64-v8a/libclient.so")
    patch=pin["client_vr_player_patch"]
    off=int(patch["file_offset"],0)
    assert client[off:off+4].hex()==patch["before"]
    audit=json.loads((ROOT/"work/gdroid130-compat/audit.json").read_text())
    ph=struct.unpack_from("<Q",client,32)[0]
    segments=[struct.unpack_from("<IIQQQQQQ",client,ph+i*56) for i in range(struct.unpack_from("<H",client,56)[0])]
    def read(va,size):
        h=next(h for h in segments if h[0]==1 and h[3]<=va and va+size<=h[3]+h[5])
        o=h[2]+va-h[3]
        return client[o:o+size]
    names={"constructor":"pose_constructor","blend":"finger_blend_function","allocator":"layer_allocator","localpose":"local_hand_pose"}
    for key,target in names.items():
        a=int(audit["addresses"][target]["new"],0)
        expected=audit["exact_signature_checks"][key]
        assert read(a,expected["size"]).hex()==expected["hex"],key
    call=int(audit["addresses"]["finger_blend_call"]["new"],0)
    ins=struct.unpack("<I",read(call,4))[0]
    assert ins>>26==0b100101
    delta=ins&0x3ffffff
    if delta&(1<<25):delta-=1<<26
    assert call+delta*4==int(audit["addresses"]["finger_blend_function"]["new"],0)
print("PASS pinned GDroid0.1.30: official digest, all native dependencies, four exact signatures, blend call and VR init patch")
