"""Preflight for the Gquest APK build: check inputs, never build or modify.

The build (Gquest/tools/build.py, i.e. Gquest-Hybrid/tools/build.py in the
private folder) fails with a traceback at whichever input is missing first.
This script checks every input up front and lists what is missing or does not
match its pinned digest, so a broken setup is visible in one run.

    python3 work/check_gquest_build.py
    python3 work/check_gquest_build.py --root /path/to/private/workspace

Exit status 0 means every checked input is present and matches; 1 means the
list below the summary still has to be fixed. Only files are read; the script
creates nothing and signs nothing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

BASE_APK_URL = "https://github.com/tinsarfal/GDroid/releases/download/0.1.30/GDroid-0.1.30.apk"

# Lua sources the build compiles or runs; the last three live only in the
# private working folder, the rest ship with the source archive.
OWN_LUA = [
    "lua/autorun/client/gquest_00_vr_api.lua",
    "lua/autorun/client/gquest_h3_manual.lua",
    "lua/autorun/client/gquest_native_weapon_pose.lua",
    "lua/autorun/client/gquest_reload.lua",
    "lua/autorun/client/gquest_vr_ui.lua",
    "lua/autorun/client/gquest_weapon_align.lua",
    "lua/autorun/client/gquest_weapon_catalog.lua",
    "lua/autorun/client/gquest_weapon_models.lua",
    "lua/autorun/client/gquest_wrist_hud.lua",
    "lua/autorun/server/gquest_hl2_equipment.lua",
    "lua/autorun/server/gquest_hl2_models.lua",
]
PRIVATE_ONLY_LUA = {
    "lua/autorun/client/gquest_weapon_catalog.lua",
    "lua/autorun/server/gquest_hl2_equipment.lua",
    "lua/autorun/server/gquest_hl2_models.lua",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


class Report:
    def __init__(self) -> None:
        self.rows: list[tuple[bool, str, str, str]] = []

    def add(self, ok: bool, label: str, detail: str = "", hint: str = "") -> None:
        self.rows.append((ok, label, detail, hint))

    def ok(self, label: str, detail: str = "") -> None:
        self.add(True, label, detail)

    def missing(self, label: str, hint: str) -> None:
        self.add(False, label, "", hint)

    def wrong(self, label: str, detail: str, hint: str) -> None:
        self.add(False, label, detail, hint)

    @property
    def failures(self) -> list[tuple[bool, str, str, str]]:
        return [row for row in self.rows if not row[0]]

    def section(self, title: str) -> None:
        self.rows.append((True, f"\n== {title} ==", "", ""))


def check_base(report: Report, root: Path) -> dict:
    pin_path = root / "work/gdroid-0.1.30-build-pin.json"
    if not pin_path.is_file():
        report.missing("work/gdroid-0.1.30-build-pin.json",
                       "gehört zum Quellarchiv; ohne die Pins ist keine Basisprüfung möglich")
        return {}
    pin = json.loads(pin_path.read_text())
    report.ok("work/gdroid-0.1.30-build-pin.json", "Pins gelesen")

    if (root / "work/gdroid130-compat/audit.json").is_file():
        report.ok("work/gdroid130-compat/audit.json", "Signatur-Audit vorhanden")
    else:
        report.missing("work/gdroid130-compat/audit.json",
                       "gehört zum Quellarchiv; verify_gdroid_base.py liest die Adressen daraus")

    apk = root / "outputs/GDroid-0.1.30.apk"
    if not apk.is_file():
        report.missing("outputs/GDroid-0.1.30.apk",
                       f"offizielle 0.1.30 ARM64-APK nach outputs/ legen: {BASE_APK_URL}")
        return {"pin": pin, "apk": None}
    actual = sha256(apk)
    if actual != pin["apk_sha256"]:
        report.wrong("outputs/GDroid-0.1.30.apk", f"sha256 {actual[:16]}… statt {pin['apk_sha256'][:16]}…",
                     f"genau die offizielle Datei verwenden, nicht eine andere Version: {BASE_APK_URL}")
        return {"pin": pin, "apk": None}
    report.ok("outputs/GDroid-0.1.30.apk",
              f"sha256 {actual[:16]}… ({apk.stat().st_size / 1048576:.1f} MB)")

    native = root / "work/gdroid-0.1.30-native"
    good = bad = 0
    bad_names = []
    with zipfile.ZipFile(apk) as archive:
        packaged = {name.split("/")[-1]: name for name in archive.namelist()
                    if name.startswith("lib/arm64-v8a/")}
        for name, digest in pin["native_sha256"].items():
            linked = native / name
            if not linked.is_file():
                bad += 1
                bad_names.append(name)
                continue
            if sha256(linked) != digest:
                bad += 1
                bad_names.append(name + " (Prüfsumme)")
                continue
            if name in packaged and archive.read(packaged[name]) != linked.read_bytes():
                bad += 1
                bad_names.append(name + " (weicht von der APK ab)")
                continue
            good += 1
        patch = pin["client_vr_player_patch"]
        offset = int(patch["file_offset"], 0)
        client = archive.read("lib/arm64-v8a/libclient.so")
        if client[offset:offset + 4].hex() == patch["before"]:
            report.ok("libclient.so VR-Spieler-Patch",
                      f"erwartete Bytes {patch['before']} an {patch['file_offset']} vorhanden")
        else:
            report.wrong("libclient.so VR-Spieler-Patch",
                         f"an {patch['file_offset']} stehen {client[offset:offset + 4].hex()}, erwartet {patch['before']}",
                         "andere Basis-APK verwenden; der Patch setzt genau diese Bytes voraus")
    if bad:
        report.wrong("work/gdroid-0.1.30-native",
                     f"{good}/{good + bad} Bibliotheken ok, abweichend oder fehlend: {', '.join(bad_names[:6])}"
                     + (" …" if len(bad_names) > 6 else ""),
                     "die 33 Bibliotheken aus der Basis-APK (lib/arm64-v8a/) nach work/gdroid-0.1.30-native/ entpacken")
    else:
        report.ok("work/gdroid-0.1.30-native", f"{good}/{good} Bibliotheken byte-identisch zur APK")

    return {"pin": pin, "apk": apk}


def check_manifest(report: Report, root: Path, manifest_rel: str, content_rel: str) -> None:
    manifest_path = root / manifest_rel
    content_root = root / content_rel
    if not manifest_path.is_file():
        report.missing(manifest_rel, f"gehört zum privaten Arbeitsordner zusammen mit {content_rel}/")
        return
    try:
        entries = json.loads(manifest_path.read_text()).get("files", [])
    except json.JSONDecodeError as error:
        report.wrong(manifest_rel, f"nicht lesbar: {error}", "Manifest aus dem privaten Arbeitsordner neu kopieren")
        return
    if not content_root.is_dir():
        report.missing(content_rel, f"{len(entries)} Dateien laut {manifest_rel} fehlen komplett")
        return
    missing, mismatch, total = [], [], 0
    for entry in entries:
        path = content_root / entry["path"]
        total += 1
        if not path.is_file():
            missing.append(entry["path"])
        elif path.stat().st_size != entry["bytes"] or sha256(path) != entry["sha256"]:
            mismatch.append(entry["path"])
    if not missing and not mismatch:
        report.ok(f"{content_rel}", f"{total}/{total} Dateien mit Prüfsumme und Größe ok")
    else:
        detail = f"{total - len(missing) - len(mismatch)}/{total} ok"
        if missing:
            detail += f", {len(missing)} fehlen (z. B. {', '.join(missing[:4])})"
        if mismatch:
            detail += f", {len(mismatch)} mit falscher Prüfsumme (z. B. {', '.join(mismatch[:4])})"
        report.wrong(content_rel, detail, "Inhalte unverändert aus dem privaten Arbeitsordner übernehmen")


def check_lua(report: Report, root: Path) -> None:
    ui = root / "work/gquest-ui"
    missing = [name for name in OWN_LUA if not (ui / name).is_file()]
    private = [name for name in missing if name in PRIVATE_ONLY_LUA]
    local = [name for name in missing if name not in PRIVATE_ONLY_LUA]
    if local:
        report.wrong("work/gquest-ui Lua", f"fehlen im Quellarchiv: {', '.join(local)}",
                     "Quellarchiv unvollständig; diese Dateien gehören ins Repo")
    if private:
        report.wrong("work/gquest-ui Lua", f"nur im privaten Ordner vorhanden: {', '.join(private)}",
                     "aus dem privaten Arbeitsordner übernehmen; der Build führt deren Tests aus")
    if not missing:
        report.ok("work/gquest-ui Lua", f"{len(OWN_LUA)}/{len(OWN_LUA)} Dateien vorhanden")
    for relative in ("work/harness/test_h3_manual.lua", "work/test_reload_client.lua",
                     "work/test_gquest_menu_navigation.lua"):
        if (root / relative).is_file():
            report.ok(relative)
        else:
            report.missing(relative, "Testdatei gehört ins Quellarchiv; der Build führt sie aus")


def check_tools(report: Report, root: Path) -> None:
    ndk = root / "work/android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin"
    clang = ndk / "aarch64-linux-android29-clang++"
    if clang.is_file():
        report.ok("NDK 23.2 aarch64-clang++")
    else:
        report.missing("NDK 23.2 (aarch64-linux-android29-clang++)",
                       "Android NDK 23.2.8568313 nach work/android-sdk/ndk/ entpacken")

    build_tools = root / "work/android-sdk/build-tools/34.0.0"
    for name, hint in (("zipalign", "Android build-tools 34.0.0 nach work/android-sdk/build-tools/ entpacken"),
                       ("lib/apksigner.jar", "gehört zu Android build-tools 34.0.0")):
        path = build_tools / name
        if path.is_file():
            report.ok(f"build-tools 34.0.0 {name}")
        else:
            report.missing(f"build-tools 34.0.0 {name}", hint)

    java = root / "work/toolchains/jdk/bin/java"
    if java.is_file():
        report.ok("JDK (work/toolchains/jdk)")
    else:
        report.missing("JDK (work/toolchains/jdk/bin/java)",
                       "JDK 17 nach work/toolchains/jdk entpacken; apksigner braucht java")

    keystore = Path.home() / ".android/debug.keystore"
    if keystore.is_file():
        report.ok("Debug-Keystore", str(keystore))
    else:
        report.missing("Debug-Keystore (~/.android/debug.keystore)",
                       "keytool -genkeypair -keystore ~/.android/debug.keystore -storepass android "
                       "-keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 "
                       "-dname 'CN=Android Debug,O=Android,C=US'")

    for name, hint in (("cargo", "Rust-Toolchain installieren (rustup)"),
                       ("rustc", "Rust-Toolchain installieren (rustup)"),
                       ("c++", "C++-Compiler für die Brücken-Tests (g++/clang++)")):
        found = shutil.which(name)
        if found:
            report.ok(name, found)
        else:
            report.missing(name, hint)

    if shutil.which("rustc"):
        try:
            sysroot = subprocess.run(["rustc", "--print", "sysroot"], capture_output=True,
                                     text=True, timeout=30).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            sysroot = ""
        target = Path(sysroot) / "lib/rustlib/aarch64-linux-android" if sysroot else None
        if target and target.is_dir():
            report.ok("Rust-Ziel aarch64-linux-android")
        else:
            report.missing("Rust-Ziel aarch64-linux-android", "rustup target add aarch64-linux-android")

    try:
        import ctypes
        ctypes.CDLL("liblua5.4.so.0")
        report.ok("liblua5.4 (work/run_lua_checks.py)")
    except OSError:
        report.missing("liblua5.4.so.0 (work/run_lua_checks.py)",
                       "Systempaket installieren, z. B. apt-get install liblua5.4-0")

    if sys.version_info >= (3, 8):
        report.ok("python3", sys.version.split()[0])
    else:
        report.wrong("python3", sys.version.split()[0], "Python 3.8 oder neuer verwenden")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=str(Path(__file__).resolve().parent.parent),
                        help="Arbeitsordner mit work/ und outputs/ (Standard: Repo-Wurzel)")
    arguments = parser.parse_args()
    root = Path(arguments.root).resolve()
    report = Report()

    report.section("Basis-APK und native Bibliotheken")
    check_base(report, root)
    report.section("VR-Inhalte und Waffenmodelle")
    check_manifest(report, root, "work/quest-vr-content-manifest.json", "work/quest-vr-content")
    check_manifest(report, root, "work/gquest-weapon-models/manifest.json", "work/gquest-weapon-models/content")
    report.section("Lua-Quellen und Tests")
    check_lua(report, root)
    report.section("Werkzeuge")
    check_tools(report, root)

    print(f"Gquest-Build-Vorabprüfung: {root}")
    for ok, label, detail, _ in report.rows:
        if label.startswith("\n== "):
            print(label)
        elif ok:
            print(f"OK    {label}" + (f"  {detail}" if detail else ""))
        else:
            print(f"FEHLT {label}" + (f"  {detail}" if detail else ""))

    failures = report.failures
    print()
    if not failures:
        print("Ergebnis: alle Eingaben vorhanden und passend.")
        print("Bauen: rtk proxy python3 Gquest-Hybrid/tools/build.py")
        return 0
    print(f"Ergebnis: {len(failures)} Eingabe(n) fehlen oder passen nicht:")
    for index, (_, label, detail, hint) in enumerate(failures, 1):
        print(f"  {index}. {label}" + (f" — {detail}" if detail else ""))
        if hint:
            print(f"     -> {hint}")
    print("\nDer Build würde hier mit einem Traceback abbrechen; erst die Punkte oben beheben.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
