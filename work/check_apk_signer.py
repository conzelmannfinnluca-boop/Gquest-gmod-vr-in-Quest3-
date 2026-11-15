"""Fail unless the built APK is signed by the expected certificate.

The build signs with whatever key GQUEST_KEYSTORE points at. A packaging or
environment slip (debug key, wrong archive, half signed APK) would still produce
an installable APK that cannot update an existing installation, so the signer is
checked before the artefact leaves CI.

    python3 work/check_apk_signer.py work/Gquest.apk          # erwartet GQUEST_EXPECTED_SIGNER
    python3 work/check_apk_signer.py work/Gquest.apk --expect <sha256>

Exit 1 on mismatch, missing signature or missing tooling, so the job stops.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def find_java() -> str:
    bundled = ROOT / "work/toolchains/jdk/bin/java"
    if bundled.is_file():
        return str(bundled)
    from shutil import which

    return which("java") or ""


def find_apksigner() -> str:
    candidates = sorted((ROOT / "work/android-sdk/build-tools").glob("*/lib/apksigner.jar"))
    return str(candidates[-1]) if candidates else ""


def certificate_sha256(apk: Path, java: str, jar: str) -> tuple[str, str]:
    """Return the signer digest (lowercase hex, no colons) or an error text."""
    result = subprocess.run([java, "-jar", jar, "verify", "--print-certs", str(apk)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        output = (result.stdout + result.stderr).strip().splitlines()
        reason = next((line.strip() for line in output if line.strip()), "unbekannter Fehler")
        return "", f"apksigner verify fehlgeschlagen ({reason}) - kein gueltig signiertes APK?"
    for line in result.stdout.splitlines():
        if "certificate SHA-256" in line:
            return line.split(": ", 1)[-1].replace(":", "").strip().lower(), ""
    return "", "kein Signaturzertifikat im APK gefunden"


def normalise(value: str) -> str:
    return value.replace(":", "").strip().lower()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--expect", default=os.environ.get("GQUEST_EXPECTED_SIGNER", ""),
                        help="SHA-256 des erwarteten Signaturzertifikats "
                             "(Standard: $GQUEST_EXPECTED_SIGNER)")
    args = parser.parse_args()

    expected = normalise(args.expect)
    if not expected:
        print("SIGNATUR: kein erwartetes Zertifikat - GQUEST_EXPECTED_SIGNER oder --expect setzen.")
        return 1
    if not args.apk.is_file():
        print(f"SIGNATUR: {args.apk} fehlt.")
        return 1
    java, jar = find_java(), find_apksigner()
    if not java or not jar:
        print("SIGNATUR: java oder apksigner.jar nicht gefunden "
              "(work/toolchains/jdk, work/android-sdk/build-tools).")
        return 1

    actual, error = certificate_sha256(args.apk, java, jar)
    if not actual:
        print(f"SIGNATUR: {error}")
        return 1
    if actual != expected:
        print("SIGNATUR FALSCH - das APK ist nicht mit dem hinterlegten Schluessel signiert.")
        print(f"  erwartet: {expected[:16]}...")
        print(f"  im APK:   {actual[:16]}...")
        print("  Pruefen: GQUEST_KEYSTORE/GQUEST_KEY_ALIAS der CI-Secrets, kein Debug-Build im Artefakt.")
        return 1
    print(f"SIGNATUR OK: {args.apk} ist mit {actual[:16]}... signiert")
    return 0


if __name__ == "__main__":
    sys.exit(main())
