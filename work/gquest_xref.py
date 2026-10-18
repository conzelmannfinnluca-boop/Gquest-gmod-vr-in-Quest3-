"""Find ARM64 code references (adrp+add) to a virtual address in an ELF.

String literals and cvar descriptors in the shipped client are addressed with an
adrp/add pair; this scanner reconstructs that pair from the raw instruction words
so a specific log message or cvar name can be traced back to the function that
uses it. Read-only: nothing is executed and no memory is mapped.
"""
from __future__ import annotations

import argparse
import struct
from pathlib import Path


def segments(data: bytes):
    program_offset = struct.unpack_from("<Q", data, 32)[0]
    program_size = struct.unpack_from("<H", data, 54)[0]
    result = []
    for index in range(struct.unpack_from("<H", data, 56)[0]):
        base = program_offset + index * program_size
        if struct.unpack_from("<I", data, base)[0] != 1:
            continue
        file_offset, virtual, _, file_size, _ = struct.unpack_from(
            "<QQQQQ", data, base + 8)
        result.append((virtual, file_offset, file_size))
    return result


def scan(path: Path, targets: set[int]):
    data = path.read_bytes()
    hits = {}
    for virtual, file_offset, file_size in segments(data):
        if not file_size:
            continue
        words = file_size // 4
        chunk = data[file_offset:file_offset + file_size]
        codes = struct.unpack_from(f"<{words}I", chunk)
        pending = {}
        for index, code in enumerate(codes):
            address = virtual + index * 4
            if code & 0x9F000000 == 0x90000000:  # adrp
                immlo = (code >> 29) & 3
                immhi = (code >> 5) & 0x7FFFF
                immediate = ((immhi << 2 | immlo) << 12)
                if immediate & (1 << 32):
                    immediate -= 1 << 33
                pending[code & 0x1F] = (address & ~0xFFF) + immediate
                continue
            if code & 0xFF800000 == 0x91000000:  # add, 64-bit, no shift
                source = (code >> 5) & 0x1F
                if source not in pending:
                    continue
                immediate = (code >> 10) & 0xFFF
                shift = (code >> 22) & 3
                target = pending[source] + (immediate << (12 * shift))
                if target in targets:
                    hits.setdefault(target, []).append(address)
    return hits


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("addresses", nargs="+", help="virtual addresses, e.g. 0xbbcc0")
    parser.add_argument("--window", type=int, default=0,
                        help="also print this many bytes around each hit")
    arguments = parser.parse_args()
    targets = {int(value, 0) for value in arguments.addresses}
    hits = scan(arguments.binary, targets)
    for target in sorted(targets):
        sites = hits.get(target, [])
        print(f"{target:#x}: {len(sites)} reference(s)")
        for site in sorted(sites):
            print(f"  code {site:#x}")
    if arguments.window:
        data = arguments.binary.read_bytes()
        for target in sorted(targets):
            for site in sorted(hits.get(target, [])):
                for virtual, file_offset, file_size in segments(data):
                    if virtual <= site - arguments.window and \
                            site + arguments.window < virtual + file_size:
                        start = file_offset + (site - arguments.window - virtual)
                        print(f"-- bytes around {site:#x}")
                        print(data[start:start + 2 * arguments.window].hex())
                        break


if __name__ == "__main__":
    main()
