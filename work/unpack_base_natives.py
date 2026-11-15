"""Extract the pinned native libraries from the base APK for the build.

The build links against work/gdroid-0.1.30-native/*.so and verifies that every
one of them is byte-identical to the copy inside the official APK. This script
creates that directory from the APK itself, so a fresh workspace (or CI run)
does not need the files to be committed.

    python3 work/unpack_base_natives.py

Refuses to write anything unless the base APK matches its pinned digest and
every extracted library matches the digest recorded in the pin.
"""
from __future__ import annotations

import hashlib
import json
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APK = ROOT / "outputs/GDroid-0.1.30.apk"
PIN = ROOT / "work/gdroid-0.1.30-build-pin.json"
TARGET = ROOT / "work/gdroid-0.1.30-native"
BASE_APK_URL = "https://github.com/tinsarfal/GDroid/releases/download/0.1.30/GDroid-0.1.30.apk"


def main() -> int:
    if not APK.is_file():
        print(f"FEHLT {APK.relative_to(ROOT)} - offizielle 0.1.30 ARM64-APK dorthin laden: {BASE_APK_URL}")
        return 1
    pin = json.loads(PIN.read_text())
    digest = hashlib.sha256(APK.read_bytes()).hexdigest()
    if digest != pin["apk_sha256"]:
        print(f"FALSCH {APK.relative_to(ROOT)}: sha256 {digest}")
        print(f"       erwartet {pin['apk_sha256']}")
        return 1
    TARGET.mkdir(parents=True, exist_ok=True)
    written = 0
    with zipfile.ZipFile(APK) as archive:
        for name, expected in pin["native_sha256"].items():
            member = "lib/arm64-v8a/" + name
            if member not in archive.namelist():
                print(f"FEHLT {member} in der Basis-APK")
                return 1
            data = archive.read(member)
            actual = hashlib.sha256(data).hexdigest()
            if actual != expected:
                print(f"FALSCH {name}: sha256 {actual} statt {expected}")
                return 1
            (TARGET / name).write_bytes(data)
            written += 1
    print(f"{written} Bibliotheken aus der Basis-APK entpackt und geprüft: "
          f"{TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
