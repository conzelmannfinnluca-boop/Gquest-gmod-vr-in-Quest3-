"""apksigner arguments for the GQuest build, debug or release keystore.

Release signing (CI, or a local release build) sets:

    GQUEST_KEYSTORE       path to the keystore, e.g. ~/gquest-release.jks
    GQUEST_KEY_ALIAS      key alias inside it
    GQUEST_KEYSTORE_PASS  store password
    GQUEST_KEY_PASS       key password (defaults to the store password)

Without GQUEST_KEYSTORE the local debug keystore is used, so a plain
`python3 Gquest/tools/build.py` keeps working unchanged.

Passwords are handed to apksigner by environment variable name (`env:NAME`),
never as literal arguments, so they do not show up in the process list.
"""
from __future__ import annotations

import os
from pathlib import Path

DEBUG_KEYSTORE = Path.home() / ".android/debug.keystore"
DEBUG_ALIAS = "androiddebugkey"
DEBUG_PASSWORD = "android"


def keystore_path() -> Path:
    configured = os.environ.get("GQUEST_KEYSTORE")
    return Path(configured).expanduser() if configured else DEBUG_KEYSTORE


def is_release() -> bool:
    return bool(os.environ.get("GQUEST_KEYSTORE"))


def signing_arguments() -> list[str]:
    """Arguments for `apksigner sign`, minus --out and the input file."""
    keystore = keystore_path()
    release = is_release()
    if not keystore.is_file():
        hint = ("GQUEST_KEYSTORE zeigt auf eine fehlende Datei"
                if release else "Debug-Keystore fehlt, z. B. mit keytool erzeugen")
        raise SystemExit(f"SIGNATUR: Keystore {keystore} fehlt - {hint}. Build abgebrochen.")
    alias = os.environ.get("GQUEST_KEY_ALIAS", "")
    if release:
        if not alias:
            raise SystemExit("SIGNATUR: GQUEST_KEY_ALIAS fehlt (Alias des Release-Schluessels).")
        if not os.environ.get("GQUEST_KEYSTORE_PASS"):
            raise SystemExit("SIGNATUR: GQUEST_KEYSTORE_PASS fehlt (Passwort des Keystores).")
    else:
        alias = alias or DEBUG_ALIAS
    os.environ.setdefault("GQUEST_KEYSTORE_PASS", DEBUG_PASSWORD)
    os.environ.setdefault("GQUEST_KEY_PASS", os.environ["GQUEST_KEYSTORE_PASS"])
    return [
        "--ks", str(keystore),
        "--ks-key-alias", alias,
        "--ks-pass", "env:GQUEST_KEYSTORE_PASS",
        "--key-pass", "env:GQUEST_KEY_PASS",
    ]


def describe() -> str:
    keystore = keystore_path()
    alias = os.environ.get("GQUEST_KEY_ALIAS") or (None if is_release() else DEBUG_ALIAS)
    kind = "Release" if is_release() else "Debug"
    return f"SIGNATUR: {kind}-Schluessel {keystore} (Alias {alias or '?'})"
