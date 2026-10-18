"""Read-only ELF helper: find strings/xrefs in the shipped ARM64 client.

The Quest port's weapon handling is inside libclient.so, so answering a question
about it from shipped bytes needs a string-to-virtual-address mapping (to read
the disassembly window) and, where the toolchain supports it, an address-to-xref
search. No memory is mapped and nothing is executed.
"""
from __future__ import annotations

import argparse
import struct
import subprocess
from pathlib import Path

NDK_OBJDUMP = sorted(Path("android-sdk/ndk").glob(
    "*/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump"))


class Elf:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        if self.data[:4] != b"\x7fELF" or self.data[4] != 2:
            raise ValueError("expected a 64-bit ELF")
        program_offset = struct.unpack_from("<Q", self.data, 32)[0]
        program_size = struct.unpack_from("<H", self.data, 54)[0]
        self.segments = []
        for index in range(struct.unpack_from("<H", self.data, 56)[0]):
            base = program_offset + index * program_size
            kind = struct.unpack_from("<I", self.data, base)[0]
            if kind != 1:  # PT_LOAD
                continue
            file_offset, virtual, _, _, file_size = struct.unpack_from("<QQQQQ", self.data, base + 8)
            self.segments.append((virtual, file_offset, file_size))

    def file_offset(self, virtual: int):
        for virtual_start, file_start, size in self.segments:
            if virtual_start <= virtual < virtual_start + size:
                return file_start + (virtual - virtual_start)
        return None

    def virtual(self, file_offset: int):
        for virtual_start, file_start, size in self.segments:
            if file_start <= file_offset < file_start + size:
                return virtual_start + (file_offset - file_start)
        return None

    def find(self, needle: bytes):
        results, start = [], 0
        while True:
            found = self.data.find(needle, start)
            if found < 0:
                return results
            results.append(found)
            start = found + 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("strings", nargs="+")
    parser.add_argument("--dump", type=Path, help="write the .text disassembly")
    parser.add_argument("--window", type=int, default=0,
                        help="print this many bytes around each virtual address")
    arguments = parser.parse_args()
    elf = Elf(arguments.binary)
    result = {}
    for text in arguments.strings:
        offsets = [o for o in elf.find(text.encode())]
        result[text] = [hex(elf.virtual(o)) for o in offsets if elf.virtual(o)]
    print(json_dump(result))
    if arguments.dump:
        tool = NDK_OBJDUMP[-1] if NDK_OBJDUMP else Path("llvm-objdump")
        with arguments.dump.open("w") as handle:
            subprocess.run([str(tool), "-d", "--no-show-raw-insn", str(arguments.binary)],
                           stdout=handle, check=True)


def json_dump(value):
    import json
    return json.dumps(value, indent=2)


if __name__ == "__main__":
    main()
