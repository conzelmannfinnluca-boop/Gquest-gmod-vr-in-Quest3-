"""Decode the pinned ArcVR Glock root's constant idle pose. Read-only.

This deliberately supports only the audited RAWPOS|RAWROT2 animation, failing
closed on changed source bytes/layout instead of guessing another MDL format.
Valve format references are returned with the result. No third-party modules.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

EXPECTED_SHA256 = "c682c0cf077149eba9085c0bfe38b8641e9e5bfac979972e3ef90db80412fbcd"
DEFAULT_MODEL = Path(__file__).resolve().parent / "arcvr-anniversary/models/weapons/arcticvr/aniv/pistol_glock.mdl"
RAWPOS = 0x01
RAWROT2 = 0x20


def decode_idle_root(path: str | Path = DEFAULT_MODEL) -> dict:
    """Return validated metadata and a model-space 4x4 root idle matrix."""
    path = Path(path)
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != EXPECTED_SHA256:
        raise ValueError(f"Pinned Glock source mismatch: {digest}")

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    def read(fmt, offset):
        size = struct.calcsize(fmt)
        require(0 <= offset <= len(data) - size, f"Out-of-range read at {offset:#x}")
        return struct.unpack_from(fmt, data, offset)

    def integer(offset):
        return read("<i", offset)[0]

    def name(offset):
        require(0 <= offset < len(data), "Out-of-range name")
        end = data.find(b"\0", offset)
        require(end >= offset, "Unterminated name")
        return data[offset:end].decode("ascii")

    require(data[:4] == b"IDST" and integer(4) == 48, "Expected MDL version 48")
    require(integer(76) == len(data), "Header length mismatch")
    bone_count, bone_index = read("<ii", 156)
    require(bone_count > 0 and bone_index == 0x298, "Unexpected root bone table")
    require(integer(bone_index + 4) == -1, "Bone zero is not a root")
    require(name(bone_index + integer(bone_index)) == "pistol", "Unexpected root bone name")
    animation_count, animation_index = read("<ii", 180)
    require(animation_count == 1 and animation_index == 0xd18, "Unexpected animation table")
    animation_name = name(animation_index + integer(animation_index + 4))
    fps = read("<f", animation_index + 8)[0]
    require(animation_name == "@idle" and fps == 30.0, "Unexpected animation identity")
    require(integer(animation_index + 12) == 0, "Unexpected animation flags")
    frames = integer(animation_index + 16)
    require(frames == 2, "Unexpected idle frame count")
    require(integer(animation_index + 52) == 0, "External animation block unsupported")
    animation_data_offset = integer(animation_index + 56)
    require(animation_data_offset == 104, "Unexpected animation data offset")
    root_record = animation_index + animation_data_offset
    require(root_record == 0xd80, "Unexpected root animation record")
    bone, flags, next_offset = read("<BBh", root_record)
    require(bone == 0 and flags == RAWPOS | RAWROT2 and next_offset == 18,
            "Expected root constant RAWPOS|RAWROT2 record")
    # RAWROT2 occupies eight bytes immediately after the four-byte record header;
    # RAWPOS then occupies six bytes (Vector48, three IEEE binary16 components).
    packed = read("<Q", root_record + 4)[0]
    require(packed == 0x5ffffefffff80000, "Unexpected quaternion64 bits")
    xyz = [(((packed >> (21 * axis)) & 0x1fffff) - 1048576) / 1048576.5
           for axis in range(3)]
    remaining = 1.0 - sum(value * value for value in xyz)
    require(remaining >= 0.0, "Invalid quaternion64 norm")
    q = xyz + [math.sqrt(remaining) * (-1.0 if packed >> 63 else 1.0)]
    position = list(read("<3e", root_record + 12))
    require(root_record + 18 == root_record + next_offset, "Record size mismatch")
    x, y, z, w = q
    rotation = [
        [1 - 2 * (y*y + z*z), 2 * (x*y - z*w), 2 * (x*z + y*w)],
        [2 * (x*y + z*w), 1 - 2 * (x*x + z*z), 2 * (y*z - x*w)],
        [2 * (x*z - y*w), 2 * (y*z + x*w), 1 - 2 * (x*x + y*y)],
    ]
    matrix = [rotation[row] + [position[row]] for row in range(3)]
    matrix.append([0.0, 0.0, 0.0, 1.0])
    orthonormal_error = max(abs(sum(rotation[row][k] * rotation[col][k] for k in range(3))
                                - float(row == col)) for row in range(3) for col in range(3))
    require(orthonormal_error < 1e-12, "Decoded rotation is not orthonormal")
    return {
        "source": str(path.resolve()), "source_sha256": digest,
        "animation": animation_name, "animation_descriptor_offset": animation_index,
        "frames": frames, "root_record_offset": root_record,
        "root_bone": bone, "flags": flags, "next_offset": next_offset,
        "packed_quaternion64": hex(packed), "quaternion_xyzw": q,
        "position": position, "matrix": matrix,
        "orthonormal_max_error": orthonormal_error,
        "scope": "Constant authored root idle; not inverse bind pose or runtime world pose",
        "format_references": [
            "https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/studio.h",
            "https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/mathlib/compressed_vector.h",
        ],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", nargs="?", type=Path, default=DEFAULT_MODEL)
    arguments = parser.parse_args()
    print(json.dumps(decode_idle_root(arguments.model), indent=2))
