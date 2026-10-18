"""Decide, from the shipped bytes alone, whether the port's in-hand weapon models
are authored in one consistent frame.

Attachments in a studio model are stored relative to a bone (`sznameindex`,
`flags`, `bone`, then a bone-local matrix3x4), so a raw read of the matrix is a
bone-local number and cannot be compared across models. This tool transforms each
attachment by its bone's bind matrix (`poseToBone`, the bone-to-model map) and
reports model-space grip, muzzle and hull geometry for every model, plus the
per-model forward axis. Models that do not share the convention are the ones that
can only ever look rotated in hand.

Read-only: no engine is executed and no file is written. Per-model failures are
reported instead of being skipped.
"""
from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

BONE_STRIDE = 216
ATTACHMENT_STRIDE = 92
POSETOBONE_OFFSET = 96


def float_at(data, offset):
    return struct.unpack_from("<f", data, offset)[0]


def cstring(data, offset):
    end = data.find(b"\0", offset)
    return data[offset:end].decode("ascii", "replace")


def matrix(data, offset):
    return [[float_at(data, offset + (row * 4 + column) * 4) for column in range(4)]
            for row in range(3)] + [[0.0, 0.0, 0.0, 1.0]]


def multiply(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def transform(matrix3x4, point):
    return [sum(matrix3x4[i][k] * point[k] for k in range(3)) + matrix3x4[i][3]
            for i in range(3)]


def rotate(matrix3x4, vector):
    return [sum(matrix3x4[i][k] * vector[k] for k in range(3)) for i in range(3)]


def euler(rotation3x3):
    forward = rotation3x3[0]
    return {"pitch": round(math.degrees(math.asin(max(-1.0, min(1.0, forward[2])))), 3),
            "yaw": round(math.degrees(math.atan2(forward[1], forward[0])), 3),
            "forward": [round(v, 4) for v in forward],
            "up": [round(v, 4) for v in rotation3x3[2]]}


def read(path: Path):
    data = path.read_bytes()
    if data[:4] != b"IDST":
        raise ValueError("not a studio model")
    if struct.unpack_from("<i", data, 76)[0] != len(data):
        raise ValueError("header length mismatch")
    header = {
        "version": struct.unpack_from("<i", data, 4)[0],
        "numbones": struct.unpack_from("<i", data, 156)[0],
        "boneindex": struct.unpack_from("<i", data, 160)[0],
        "numattachments": struct.unpack_from("<i", data, 240)[0],
        "attachmentindex": struct.unpack_from("<i", data, 244)[0],
        "hull_min": [float_at(data, 104 + 4 * i) for i in range(3)],
        "hull_max": [float_at(data, 116 + 4 * i) for i in range(3)],
    }
    bones = []
    for index in range(header["numbones"]):
        record = header["boneindex"] + index * BONE_STRIDE
        bones.append({
            "name": cstring(data, record + struct.unpack_from("<i", data, record)[0]),
            "parent": struct.unpack_from("<i", data, record + 4)[0],
            "pose_to_bone": matrix(data, record + POSETOBONE_OFFSET),
        })
    attachments = []
    for index in range(header["numattachments"]):
        record = header["attachmentindex"] + index * ATTACHMENT_STRIDE
        bone = struct.unpack_from("<i", data, record + 8)[0]
        if not 0 <= bone < len(bones):
            raise ValueError(f"attachment {index} names bone {bone} outside the skeleton")
        local = matrix(data, record + 12)
        attachments.append({
            "name": cstring(data, record + struct.unpack_from("<i", data, record)[0]),
            "bone": bone, "bone_name": bones[bone]["name"],
            "local_matrix": local,
            "model_position": transform(bones[bone]["pose_to_bone"], [local[i][3] for i in range(3)]),
            "model_rotation": multiply(bones[bone]["pose_to_bone"], local),
        })
    return header, bones, attachments


def report(path: Path):
    header, bones, attachments = read(path)
    by_name = {entry["name"]: entry for entry in attachments}
    hull_min, hull_max = header["hull_min"], header["hull_max"]
    centre = [round((a + b) / 2, 3) for a, b in zip(hull_min, hull_max)]
    grip = by_name.get("grip")
    muzzle = by_name.get("muzzle") or by_name.get("muzzle2")
    entry = {
        "path": str(path), "version": header["version"], "bones": len(bones),
        "root_bone": bones[0]["name"] if bones else None,
        "hull_size": [round(b - a, 3) for a, b in zip(hull_min, hull_max)],
        "hull_centre": centre,
        "attachments": sorted(by_name),
    }
    for key in ("grip", "foregrip", "muzzle", "reloadpoint"):
        found = by_name.get(key)
        if found:
            entry[key] = {
                "bone": found["bone_name"],
                "model_position": [round(v, 4) for v in found["model_position"]],
                "model_rotation": euler([row[:3] for row in found["model_rotation"][:3]]),
            }
    if grip:
        entry["grip_offset_from_origin"] = round(
            math.dist(grip["model_position"], [0, 0, 0]), 4)
        entry["hull_centre_minus_grip"] = [
            round(centre[i] - grip["model_position"][i], 3) for i in range(3)]
    if grip and muzzle:
        barrel = [muzzle["model_position"][i] - grip["model_position"][i] for i in range(3)]
        entry["barrel_from_grip"] = [round(v, 4) for v in barrel]
        entry["barrel_length"] = round(math.dist(muzzle["model_position"], grip["model_position"]), 4)
        longest = max(range(3), key=lambda i: abs(barrel[i]))
        entry["barrel_axis"] = "xyz"[longest]
        entry["barrel_sign"] = 1 if barrel[longest] > 0 else -1
    return entry


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="+", type=Path)
    arguments = parser.parse_args()
    output = []
    for path in arguments.models:
        try:
            output.append(report(path))
        except Exception as error:  # noqa: BLE001 - reported, never swallowed
            output.append({"path": str(path), "error": f"{type(error).__name__}: {error}"})
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
