"""Minimal read-only VPK v2 reader for extracting the stock viewmodels.

The stock v_* models live inside the user's own Garry's Mod content VPKs; the
Quest port needs their bounds/bones as a reference to tell an authored model
pivot apart from a hold-offset that was only calibrated for the stock model.

Only archive_index 0 (data inside the *_dir.vpk) and the numbered side archives
are supported; anything else is reported as unsupported instead of guessed.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path


class Vpk:
    def __init__(self, directory_vpk: Path):
        self.path = Path(directory_vpk)
        data = self.path.read_bytes()
        signature, self.version, self.tree_size = struct.unpack_from("<III", data, 0)
        if signature != 0x55AA1234:
            raise ValueError("not a VPK")
        header_size = 12 if self.version == 1 else 28
        self.tree = data[header_size:header_size + self.tree_size]
        self.dir_data = data
        self.entries = {}
        cursor = 0

        def cstring():
            nonlocal cursor
            end = self.tree.index(b"\0", cursor)
            value = self.tree[cursor:end].decode("utf-8")
            cursor = end + 1
            return value

        while True:
            extension = cstring()
            if not extension:
                break
            while True:
                path = cstring()
                if not path:
                    break
                while True:
                    filename = cstring()
                    if not filename:
                        break
                    crc, preload, archive, offset, length, terminator = \
                        struct.unpack_from("<IHHIIH", self.tree, cursor)
                    cursor += 18
                    if terminator != 0xFFFF:
                        raise ValueError("VPK entry terminator missing")
                    preload_data = self.tree[cursor:cursor + preload]
                    cursor += preload
                    name = f"{path}/{filename}.{extension}".lstrip("/").lower()
                    self.entries[name] = (archive, offset, length, preload_data)

    def read(self, name: str) -> bytes:
        entry = self.entries.get(name.lower())
        if entry is None:
            raise KeyError(name)
        archive, offset, length, preload = entry
        if archive == 0x7FFF:
            start = 12 + self.tree_size if self.version == 1 else 28 + self.tree_size
            return self.dir_data[start + offset:start + offset + length] + preload
        side = self.path.with_name(
            self.path.name.replace("_dir.vpk", f"_{archive:03d}.vpk"))
        with side.open("rb") as handle:
            handle.seek(offset)
            return handle.read(length) + preload


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("vpk", type=Path)
    parser.add_argument("names", nargs="*")
    parser.add_argument("--grep", help="print entries whose path contains this text")
    parser.add_argument("--extract-to", type=Path)
    arguments = parser.parse_args()
    archive = Vpk(arguments.vpk)
    if arguments.grep:
        for name in sorted(archive.entries):
            if arguments.grep.lower() in name:
                print(name)
        return
    for name in arguments.names:
        content = archive.read(name)
        print(f"{name}\t{len(content)} bytes")
        if arguments.extract_to:
            target = arguments.extract_to / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)


if __name__ == "__main__":
    main()
