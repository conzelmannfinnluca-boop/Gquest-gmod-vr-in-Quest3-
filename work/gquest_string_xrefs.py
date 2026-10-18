"""List every string a code range references, in address order.

Used to read the engine's metadata/JSON schema keys straight out of a static
initializer without guessing which literals belong together. The scanner
reconstructs adrp+add pairs; every resolved target that lands in a printable
string region is printed with its virtual address. Read-only.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path


def load(path: Path):
    data = path.read_bytes()
    program_offset = struct.unpack_from("<Q", data, 32)[0]
    program_size = struct.unpack_from("<H", data, 54)[0]
    segments = []
    for index in range(struct.unpack_from("<H", data, 56)[0]):
        base = program_offset + index * program_size
        if struct.unpack_from("<I", data, base)[0] != 1:
            continue
        file_offset, virtual, _, file_size, _ = struct.unpack_from(
            "<QQQQQ", data, base + 8)
        segments.append((virtual, file_offset, file_size))
    return data, segments


def string_at(data, segments, virtual, limit=160):
    for start, file_offset, size in segments:
        if start <= virtual < start + size:
            offset = file_offset + (virtual - start)
            end = data.find(b"\0", offset)
            if end < 0:
                return None
            raw = data[offset:min(end, offset + limit)]
            if len(raw) < 3 or not all(32 <= byte < 127 for byte in raw):
                return None
            return raw.decode()
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("start", help="virtual address of the first instruction")
    parser.add_argument("stop", help="virtual address past the last instruction")
    arguments = parser.parse_args()
    start, stop = int(arguments.start, 0), int(arguments.stop, 0)
    data, segments = load(arguments.binary)
    for start_address, file_offset, size in segments:
        if not (start_address <= start < start_address + size):
            continue
        offset = file_offset + (start - start_address)
        codes = struct.unpack_from(f"<{(stop - start) // 4}I", data, offset)
        pending = {}
        for index, code in enumerate(codes):
            address = start + index * 4
            if code & 0x9F000000 == 0x90000000:
                immlo, immhi = (code >> 29) & 3, (code >> 5) & 0x7FFFF
                immediate = ((immhi << 2 | immlo) << 12)
                if immediate & (1 << 32):
                    immediate -= 1 << 33
                pending[code & 0x1F] = (address & ~0xFFF) + immediate
                continue
            if code & 0xFF800000 == 0x91000000:
                source = (code >> 5) & 0x1F
                if source in pending:
                    target = pending[source] + ((code >> 10) & 0xFFF)
                    text = string_at(data, segments, target)
                    if text:
                        print(f"{address:#010x} -> {target:#010x} {text!r}")
        return


if __name__ == "__main__":
    main()
