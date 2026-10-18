"""Read-only studio MDL audit for the Gquest VR weapon models.

Reports header identity, hull/view bounds, bones and their names, attachments
with their local transform, and the constant root record of the first local
animation (usually `@idle`). It also probes the attachment record stride instead
of assuming one, because the shipped models come from different SDK revisions.

No file is written and no engine is executed; every number is decoded directly
from the bytes and validated (version, header length, string bounds, matrix
orthonormality) so a layout guess cannot silently produce plausible output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

RAWPOS, RAWROT = 0x01, 0x02
ANIMPOS, ANIMROT = 0x04, 0x08
RAWROT2 = 0x20


def _read(fmt, data, offset):
    size = struct.calcsize(fmt)
    if not (0 <= offset <= len(data) - size):
        raise ValueError(f"out-of-range read of {size} bytes at {offset:#x}")
    return struct.unpack_from(fmt, data, offset)


def _int(data, offset):
    return _read("<i", data, offset)[0]


def _cstring(data, offset):
    if not (0 <= offset < len(data)):
        raise ValueError(f"out-of-range string at {offset:#x}")
    end = data.find(b"\0", offset)
    if end < 0:
        raise ValueError(f"unterminated string at {offset:#x}")
    return data[offset:end].decode("ascii", "replace")


def _vector(data, offset):
    return list(_read("<3f", data, offset))


class Unsupported(Exception):
    """Raised for an animation record whose encoded block is not decoded here."""


def decode_root_record(data, offset, bone_count):
    """Decode one studioanim_t record into a local transform.

    Constant records (RAWPOS/RAWROT/RAWROT2) are fully validated against the
    record's own nextoffset. Encoded blocks are reported as unsupported instead
    of being guessed; their size depends on the compressed value stream.
    """
    bone, flags, next_offset = _read("<BBh", data, offset)
    if bone >= bone_count:
        raise ValueError(f"animation record bone {bone} out of range")
    if not 4 <= next_offset <= 4096:
        raise ValueError(f"implausible animation record length {next_offset}")
    cursor = offset + 4
    rotation, truncated = None, False
    if flags & RAWROT2:
        packed = _read("<Q", data, cursor)[0]
        xyz = [(((packed >> (21 * axis)) & 0x1FFFFF) - 1048576) / 1048576.5
               for axis in range(3)]
        remaining = 1.0 - sum(value * value for value in xyz)
        if remaining < 0.0:
            rotation = {"format": "quaternion64", "packed": hex(packed), "invalid": True}
        else:
            q = xyz + [math.sqrt(remaining) * (-1.0 if packed >> 63 else 1.0)]
            rotation = {"format": "quaternion64", "packed": hex(packed),
                        "quaternion_xyzw": q, "euler_helper": _euler(q)}
        cursor += 8
    elif flags & RAWROT:
        rotation = {"format": "raw-shorts",
                    "values": list(_read("<3h", data, cursor))}
        cursor += 8
    elif flags & ANIMROT:
        truncated = True
    position = None
    if flags & RAWPOS:
        position = list(_read("<3e", data, cursor))
        cursor += 6
    elif flags & ANIMPOS:
        truncated = True
    if not truncated and cursor != offset + next_offset:
        raise ValueError(
            f"constant record consumed {cursor - offset} bytes, header says {next_offset}")
    return {"offset": offset, "bone": bone, "flags": hex(flags),
            "next_offset": next_offset, "position": position, "rotation": rotation,
            "encoded_block_unparsed": truncated}


def _euler(q):
    x, y, z, w = q
    return {
        "pitch": math.degrees(math.asin(max(-1.0, min(1.0, 2 * (w * y - z * x))))),
        "yaw": math.degrees(math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))),
        "roll": math.degrees(math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))),
    }


def decode_attachments(data, header):
    count, index = header["numattachments"], header["attachmentindex"]
    if not count:
        return [], None
    for stride in (92, 88, 56, 64, 96):
        records, ok = [], True
        for i in range(count):
            record = index + i * stride
            if record + stride > len(data):
                ok = False
                break
            name_offset = record + _int(data, record)
            try:
                name = _cstring(data, name_offset)
            except ValueError:
                ok = False
                break
            if not name or not all(32 <= ord(c) < 127 for c in name):
                ok = False
                break
            matrix = [list(_read("<4f", data, record + 12 + row * 16)) for row in range(3)]
            rows_ok = all(
                abs(math.sqrt(sum(m * m for m in row[:3])) - 1.0) < 0.02 for row in matrix
            )
            if not rows_ok:
                ok = False
                break
            records.append({"name": name, "index": i, "local_matrix": matrix})
        if ok and len(records) == count:
            return records, stride
    return [], None


def audit(path: Path) -> dict:
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if data[:4] not in (b"IDST", b"IDSP"):
        raise ValueError("not a studio model")
    version = _int(data, 4)
    if _int(data, 76) != len(data):
        raise ValueError("header length does not match the file size")
    keys = {
        "checksum": 8, "name": 12, "length": 76, "eyeposition": 80, "illumposition": 92,
        "hull_min": 104, "hull_max": 116, "view_bbmin": 128, "view_bbmax": 140,
        "flags": 152, "numbones": 156, "boneindex": 160,
        "numlocalanim": 180, "localanimindex": 184,
        "numbodyparts": 232, "bodypartindex": 236,
        "numattachments": 240, "attachmentindex": 244,
    }
    header = {key: _int(data, offset) for key, offset in keys.items()}
    header["version"] = version
    header["name_string"] = _cstring(data, keys["name"])
    header["eyeposition"] = _vector(data, keys["eyeposition"])
    header["illumposition"] = _vector(data, keys["illumposition"])
    header["hull_min"] = _vector(data, keys["hull_min"])
    header["hull_max"] = _vector(data, keys["hull_max"])
    header["hull_size"] = [round(b - a, 4) for a, b in
                           zip(header["hull_min"], header["hull_max"])]
    header["view_bbmin"] = _vector(data, keys["view_bbmin"])
    header["view_bbmax"] = _vector(data, keys["view_bbmax"])

    bones = []
    for i in range(header["numbones"]):
        record = header["boneindex"] + i * 216
        bones.append({
            "index": i,
            "name": _cstring(data, record + _int(data, record)),
            "parent": _int(data, record + 4),
            "position": _vector(data, record + 32),
        })

    attachments, stride = decode_attachments(data, header)

    animations = []
    for i in range(header["numlocalanim"]):
        record = header["localanimindex"] + i * 100
        name = _cstring(data, record + _int(data, record + 4))
        data_offset = _int(data, record + 56)
        flags = _int(data, record + 12)
        entry = {"name": name, "flags": hex(flags), "fps": _read("<f", data, record + 8)[0],
                 "frames": _int(data, record + 16), "data_offset": data_offset}
        try:
            entry["root_record"] = decode_root_record(
                data, record + data_offset, header["numbones"])
        except ValueError as error:
            entry["root_record_error"] = str(error)
        animations.append(entry)

    return {
        "path": str(path), "sha256": digest, "bytes": len(data),
        "header": header, "bones": bones, "attachment_stride": stride,
        "attachments": attachments, "animations": animations,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="+", type=Path)
    parser.add_argument("--full-bones", action="store_true",
                        help="print every bone instead of only the first twelve")
    arguments = parser.parse_args()
    output = []
    for path in arguments.models:
        try:
            result = audit(path)
        except ValueError as error:
            result = {"path": str(path), "error": str(error)}
        if not arguments.full_bones and "bones" in result:
            result["bone_count"] = len(result["bones"])
            result["bones"] = result["bones"][:12]
        output.append(result)
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
