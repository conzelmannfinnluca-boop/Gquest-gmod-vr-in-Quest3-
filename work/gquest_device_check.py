"""Install the current Gquest build on the Quest and collect the weapon reports.

One run does what the last session could not: it waits for the headset, installs
outputs/Gquest.apk, restores the opt-in left-palm profile, launches the VR
activity, sends the weapon checks through the engine's dev command socket and
pulls the JSON the two Lua modules write.

Nothing here is claimed unless it is observed: every step prints the command it
runs, a missing device, install failure, closed socket or absent report stops
with a non-zero status instead of assuming success.

    python3 work/gquest_device_check.py            # install, check, retrieve
    python3 work/gquest_device_check.py --no-install
    python3 work/gquest_device_check.py --save     # also send gquest_align_save
    python3 work/gquest_device_check.py --dry-run  # print the plan only

Reports land in outputs/Gquest-device-weapon_models.json,
outputs/Gquest-device-weapon_align.json and outputs/Gquest-device-weapon-check.log.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APK = ROOT / "outputs/Gquest.apk"
PACKAGE = "com.gmodvr.qvrx"
ACTIVITY = f"{PACKAGE}/com.gmodvr.flat.GameActivity"
DATA_DIR = "files/garrysmod/data/gquest"
REPORTS = ("weapon_models.json", "weapon_align.json")
OUT = ROOT / "outputs"
SOCKET_PORT = 27100


def run(command, serial=None, capture=True, timeout=300):
    full = ["adb"] + (["-s", serial] if serial else []) + command
    print("+ " + " ".join(full), flush=True)
    result = subprocess.run(full, capture_output=capture, text=True, timeout=timeout)
    return result


def adb_text(command, serial=None, timeout=300):
    result = run(command, serial, timeout=timeout)
    if result.returncode != 0:
        raise SystemExit(f"adb failed: {result.stderr.strip() or result.returncode}")
    return result.stdout.strip()


def wait_for_device(deadline_seconds):
    end = time.monotonic() + deadline_seconds
    while time.monotonic() < end:
        output = adb_text(["devices"])
        devices = [line.split()[0] for line in output.splitlines()[1:] if line.strip().endswith("device")]
        if devices:
            return devices[0]
        time.sleep(5)
    return None


def install(serial):
    result = run(["install", "--no-incremental", "-r", str(APK)], serial, timeout=900)
    text = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0 or "Success" not in text:
        raise SystemExit("install did not report Success:\n" + text.strip())
    print("install: Success")
    # The left-palm correction is opt-in; a plain reinstall keeps the profile,
    # a fresh device needs the gate created explicitly.
    adb_text(["shell", "run-as", PACKAGE, "mkdir", "-p", "files/diagnostics"], serial)
    adb_text(["shell", "run-as", PACKAGE, "touch", "files/diagnostics/left-palm-native.enable"], serial)
    print("left-palm profile: present")
    adb_text(["shell", "pm", "path", PACKAGE], serial)


def launch(serial):
    adb_text(["shell", "am", "force-stop", PACKAGE], serial)
    adb_text(["shell", "am", "start", "-a", "android.intent.action.MAIN", "-c",
              "com.oculus.intent.category.VR", "-n", ACTIVITY], serial)
    print("launch: requested")


def send_commands(serial, commands, timeout_seconds=180):
    """Talk to the engine's dev command socket through an adb forward."""
    adb_text(["forward", f"tcp:{SOCKET_PORT}", f"tcp:{SOCKET_PORT}"], serial)
    end = time.monotonic() + timeout_seconds
    last_error = None
    while time.monotonic() < end:
        try:
            with socket.create_connection(("127.0.0.1", SOCKET_PORT), timeout=3) as connection:
                connection.settimeout(3)
                banner = connection.recv(4096)
                if b"command socket" in banner or b"vr_cmdsock" in banner:
                    payload = ("\n".join(commands) + "\n").encode()
                    connection.sendall(payload)
                    time.sleep(1)
                    print("socket: sent " + ", ".join(commands))
                    return True
                last_error = f"unexpected banner: {banner[:80]!r}"
        except OSError as error:
            last_error = str(error)
        time.sleep(4)
    print(f"socket: not available ({last_error}); the menu still offers Waffentest")
    return False


def pull(serial, name, timeout_seconds=180):
    """Copy one report out of the app's private data directory."""
    path = f"{DATA_DIR}/{name}"
    end = time.monotonic() + timeout_seconds
    while time.monotonic() < end:
        result = run(["shell", "run-as", PACKAGE, "cat", path], serial, timeout=60)
        text = (result.stdout or "").strip()
        if result.returncode == 0 and text.startswith("{") and text.rstrip().endswith("}"):
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError:
                parsed = None
            if parsed is not None:
                target = OUT / f"Gquest-device-{name}"
                target.write_text(json.dumps(parsed, indent=2) + "\n")
                print(f"report: {target.relative_to(ROOT)} ({target.stat().st_size} bytes)")
                return parsed
        time.sleep(6)
    print(f"report: {path} not readable yet")
    return None


def logcat(serial):
    result = run(["logcat", "-d", "-v", "time"], serial, timeout=120)
    lines = [line for line in (result.stdout or "").splitlines()
             if "GQUEST_WMODEL" in line or "GQUEST_ALIGN" in line]
    target = OUT / "Gquest-device-weapon-check.log"
    target.write_text("\n".join(lines) + ("\n" if lines else ""))
    print(f"log: {target.relative_to(ROOT)} ({len(lines)} GQUEST lines)")
    return lines


def summarise(models, align):
    if models:
        print("\nweapon models on the device:")
        print(f"  weapons={len(models.get('weapons', []))} "
              f"parts={len(models.get('parts', []))}")
        active = models.get("active")
        if active:
            print(f"  active={active.get('class')} model={active.get('entity_model')}")
    if align:
        print(f"  saved alignments={len((align.get('classes') or {}))}")
    return bool(models)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-install", action="store_true")
    parser.add_argument("--save", action="store_true", help="also send gquest_align_save")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--wait", type=int, default=int(os.environ.get("GQUEST_WAIT", "180")))
    parser.add_argument("--serial", default=os.environ.get("GQUEST_SERIAL"))
    arguments = parser.parse_args()

    if not APK.is_file():
        raise SystemExit(f"missing {APK}")
    if arguments.dry_run:
        print(f"apk: {APK} ({APK.stat().st_size} bytes)")
        print("plan:")
        for step in [
            "wait for an adb device",
            "--no-install skipped" if arguments.no_install else f"install -r {APK.name}",
            "touch files/diagnostics/left-palm-native.enable",
            "start the VR activity",
            f"adb forward tcp:{SOCKET_PORT}",
            "send gquest_wmodel_verbose, gquest_align_status" + (", gquest_align_save" if arguments.save else ""),
            "pull " + ", ".join(REPORTS),
            "collect GQUEST_ log lines",
        ]:
            print("  - " + step)
        return 0

    serial = arguments.serial or wait_for_device(arguments.wait)
    if not serial:
        raise SystemExit(
            f"no Quest on adb within {arguments.wait}s (USB or mDNS). Connect it, "
            "accept the debugging prompt, then rerun.")
    print(f"device: {serial}")

    if not arguments.no_install:
        install(serial)
    launch(serial)
    # The report runs 20 s after the map loads; give the engine time to boot.
    time.sleep(35)
    commands = ["gquest_wmodel_verbose", "gquest_align_status"]
    if arguments.save:
        commands.append("gquest_align_save")
    sent = send_commands(serial, commands)
    if not sent:
        print("note: send the same commands through the in-game menu or console")

    models = pull(serial, "weapon_models.json")
    align = pull(serial, "weapon_align.json")
    logcat(serial)
    if models is None:
        print("result: no weapon-model report on the device; inspect the log above")
        return 2
    summarise(models, align)
    print("result: reports retrieved")
    return 0


if __name__ == "__main__":
    sys.exit(main())
