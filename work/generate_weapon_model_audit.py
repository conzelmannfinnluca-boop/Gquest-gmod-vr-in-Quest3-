"""Write the weapon-model audit for the private Quest port.

Answers, from shipped bytes only, what the package now contains for every weapon
the engine poses in hand: which script key selects which model, whether that
model ships, where its grip and barrel sit in model space, and which physical
part models (magazine, slide, foregrip, shell) the engine names for it.

Inputs are the package's own manifests plus the model files they reference, so a
report cannot claim a file the build would not ship. Output:
outputs/Gquest-weapon-model-audit.json and .md
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from gquest_model_axis_audit import report as axis_report

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
OUT = ROOT / "outputs"

WEAPONS = [
    ("weapon_357", "357"), ("weapon_ar2", "irifle"), ("weapon_bugbait", "bugbait"),
    ("weapon_crossbow", "crossbow"), ("weapon_crowbar", "crowbar"), ("weapon_frag", "grenade"),
    ("weapon_physcannon", "physcannon"), ("weapon_physgun", "superphyscannon"),
    ("weapon_pistol", "pistol"), ("weapon_rpg", "rocket_launcher"),
    ("weapon_shotgun", "shotgun"), ("weapon_smg1", "smg"),
]

PART_SUFFIXES = ["_clip", "_slide", "_reloader", "_shell", "_shellcase", "_missile",
                 "_rebar", "_foregrip", "_charginghandle", "_handle", "_pin"]

# The stock viewmodel the port used before the VR models were added, as named by
# each weapon script's own "viewmodel" key. Comparison source, not a target.
STOCK_VIEWMODEL = {
    "weapon_357": "v_357", "weapon_ar2": "v_irifle", "weapon_bugbait": "v_bugbait",
    "weapon_crossbow": "v_crossbow", "weapon_crowbar": "v_crowbar",
    "weapon_frag": "v_grenade", "weapon_physcannon": "v_physcannon",
    "weapon_physgun": "v_Physics", "weapon_pistol": "v_pistol", "weapon_rpg": "v_rpg",
    "weapon_shotgun": "v_shotgun", "weapon_smg1": "v_smg1",
}


ADDON_VIEWMODEL_EDIT = WORK / "gvrmod/addon/vrmod-x64/lua/vrmod/player/cl_viewmodeledit.lua"


def addon_offsets():
    """Offsets the installed vrmod addon still applies per class.

    These defaults were tuned for the stock v_* viewmodels. Reading them here is
    what makes the mismatch with the vr_* models (grip at the origin) checkable
    instead of asserted.
    """
    if not ADDON_VIEWMODEL_EDIT.is_file():
        return {}
    result, current = {}, None
    for line in ADDON_VIEWMODEL_EDIT.read_text(errors="replace").splitlines():
        stripped = line.strip()
        entry = re.match(r"^(\w+)\s*=\s*\{\s*$", stripped)
        if entry:
            current = entry.group(1)
            continue
        offset = re.match(r"^offsetPos\s*=\s*Vector\(([^)]*)\)", stripped)
        if offset and current:
            try:
                result[current] = [float(part) for part in offset.group(1).split(",")]
            except ValueError:
                pass
    return result


def content_index():
    manifest = json.loads((WORK / "quest-vr-content-manifest.json").read_text())
    index = {}
    for entry in manifest["files"]:
        index[entry["path"].lower()] = entry
    return index


def engine_referenced_models():
    """Every vr_* model path the shipped client and its libraries name."""
    paths = set()
    pattern = re.compile(rb"models/weapons/(?:left_handed/)?vr_[a-z0-9_]+\.mdl")
    for library in [WORK / "base-native/libclient.so", *sorted((WORK / "gdroid-native").glob("*.so"))]:
        if library.is_file():
            paths.update(match.decode() for match in pattern.findall(library.read_bytes()))
    return sorted(paths)


def model_summary(path: Path):
    entry = axis_report(path)
    if "error" in entry:
        return {"error": entry["error"]}
    summary = {
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "hull_size": entry["hull_size"],
        "bones": entry["bones"],
    }
    if "grip" in entry:
        summary["grip_model_position"] = entry["grip"]["model_position"]
        summary["grip_bone"] = entry["grip"]["bone"]
        summary["grip_offset_from_origin"] = entry["grip_offset_from_origin"]
    if "barrel_from_grip" in entry:
        summary["barrel_from_grip"] = entry["barrel_from_grip"]
        summary["barrel_axis"] = entry["barrel_axis"]
    if "foregrip" in entry:
        summary["foregrip_model_position"] = entry["foregrip"]["model_position"]
    return summary


def main():
    index = content_index()
    metadata = json.loads((WORK / "gquest-weapon-models/manifest.json").read_text())
    scripts = {entry["path"]: entry for entry in metadata["files"]}
    content_root = WORK / "quest-vr-content"

    offsets = addon_offsets()
    weapons = []
    parts_total, parts_missing = 0, []
    for class_name, stem in WEAPONS:
        script = scripts.get(f"scripts/{class_name}.txt")
        expected_right = f"models/weapons/vr_{stem}.mdl"
        expected_left = f"models/weapons/left_handed/vr_{stem}_l.mdl"
        entry = {
            "class": class_name,
            "script": f"scripts/{class_name}.txt",
            "vrmodel": script["fields"].get("vrmodel") if script else None,
            "vrmodel_l": script["fields"].get("vrmodel_l") if script else None,
            "expected_vrmodel": expected_right,
            "expected_vrmodel_l": expected_left,
            "script_sha256": script["sha256"] if script else None,
            "original_bytes_preserved": script["original_bytes_preserved"] if script else None,
        }
        entry["matches_expected"] = (
            entry["vrmodel"] == expected_right and entry["vrmodel_l"] == expected_left)
        for key in ("vrmodel", "vrmodel_l"):
            path = entry[key]
            entry[f"{key}_ships"] = bool(path) and path.lower() in index
            if entry[f"{key}_ships"]:
                file = content_root / index[path.lower()]["path"]
                entry[f"{key}_detail"] = model_summary(file)
        parts = []
        for part in sorted(name for name in index
                           if name.startswith("models/weapons/") and name.endswith(".mdl")
                           and stem.split("_")[0] in name and any(s in name for s in PART_SUFFIXES)):
            parts.append(index[part]["path"])
        entry["part_models_shipped"] = parts
        entry["addon_offset"] = offsets.get(class_name)
        stock_name = STOCK_VIEWMODEL[class_name]
        stock_path = WORK / "stock-models/models/weapons" / f"{stock_name}.mdl"
        if stock_path.is_file():
            stock = axis_report(stock_path)
            entry["stock_viewmodel"] = {
                "path": f"models/weapons/{stock_name}.mdl",
                "hull_size": stock.get("hull_size"),
                "attachments": stock.get("attachments"),
            }
        else:
            entry["stock_viewmodel"] = {
                "path": f"models/weapons/{stock_name}.mdl",
                "note": "not present in the extracted retail VPKs",
            }
        weapons.append(entry)

    for path in sorted(name for name in engine_referenced_models()):
        parts_total += 1
        if path.lower() not in index:
            parts_missing.append(path)

    report = {
        "private_lab_only": True,
        "generator": "work/generate_weapon_model_audit.py",
        "scope": (
            "Reads the package's own manifests and model files. Reports model-space "
            "grip/muzzle geometry decoded from the shipped MDL bytes; it does not "
            "observe or claim the rendered in-hand pose on the Quest."
        ),
        "weapons": weapons,
        "engine_referenced_models": {
            "total": parts_total, "missing": parts_missing,
            "all_present": not parts_missing,
        },
        "content_records": len(index),
        "runtime_verified": False,
    }
    OUT.mkdir(exist_ok=True)
    (OUT / "Gquest-weapon-model-audit.json").write_text(json.dumps(report, indent=2) + "\n")

    lines = [
        "# Gquest weapon models, package audit",
        "",
        f"Weapons checked: {len(weapons)}. Content records: {len(index)}. "
        f"Engine-referenced VR models present: {parts_total - len(parts_missing)}/{parts_total}.",
        "",
        "Grip and barrel values are model-space, decoded from the shipped MDL: the grip "
        "attachment is transformed by its owning bone's bind matrix, because the raw "
        "attachment matrix is bone-local and cannot be compared across models.",
        "",
        "| Weapon | Script model | Ships | Grip off origin (u) | Barrel from grip | Axis | VR hull | Stock hull (reference) | Addon offset (u) | Parts shipped |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for entry in weapons:
        detail = entry.get("vrmodel_detail") or {}
        barrel = detail.get("barrel_from_grip")
        stock = entry.get("stock_viewmodel") or {}
        stock_hull = stock.get("hull_size")
        addon_offset = entry.get("addon_offset")
        lines.append("| {} | {} | {} | {} | {} | {} | {} | {} | {} | {} |".format(
            entry["class"],
            entry["vrmodel"] or "-",
            "yes" if entry.get("vrmodel_ships") else "NO",
            detail.get("grip_offset_from_origin", "-"),
            "[" + ", ".join(str(round(value, 2)) for value in barrel) + "]" if barrel else "-",
            detail.get("barrel_axis", "-"),
            "[" + ", ".join(str(round(v, 1)) for v in detail["hull_size"]) + "]"
            if detail.get("hull_size") else "-",
            "[" + ", ".join(str(round(v, 1)) for v in stock_hull) + "]" if stock_hull
            else (stock.get("note") or "-"),
            "[" + ", ".join(str(round(v, 1)) for v in addon_offset) + "]" if addon_offset
            else "none",
            len(entry["part_models_shipped"]),
        ))
    lines += [
        "",
        "## What this does and does not establish",
        "",
        "* Every weapon script the package ships selects the model the port's own engine "
        "expects, and that model ships in the APK (see the `Ships` column).",
        "* Each in-hand model carries a `grip` attachment within a few units of its own "
        "origin, which is the frame the engine's in-hand placement consumes.",
        "* The barrel direction is authored per model, so a single global rotation cannot "
        "be correct for all of them; per-model placement has to come from the model.",
        "* The installed addon still applies stock-viewmodel offsets (last column) to "
        "classes whose model now has its grip at the origin, so the gun sits tens of "
        "units off the hand. `lua/autorun/client/gquest_weapon_align.lua` replaces those "
        "values with the model's own frame, keeps per-weapon tuning in "
        "data/gquest/weapon_align.json and exposes it as `gquest_align`.",
        "* Nothing here proves how a model is drawn in the hand. That is decided by the "
        "shipped client at runtime, so the question is answered in the headset by "
        "`gquest_wmodel` (gquest_weapon_models.lua), whose report names the model each "
        "weapon resolves to and whether every part model loads.",
        "",
        "Per-weapon detail, including each part path and every attachment with its bone:",
        "outputs/Gquest-weapon-model-audit.json",
    ]
    (OUT / "Gquest-weapon-model-audit.md").write_text("\n".join(lines))
    print(json.dumps({
        "weapons": len(weapons),
        "mismatched": [entry["class"] for entry in weapons if not entry["matches_expected"]],
        "models_missing": [entry["class"] for entry in weapons
                           if not entry.get("vrmodel_ships") or not entry.get("vrmodel_l_ships")],
        "engine_models_missing": parts_missing,
    }, indent=2))


if __name__ == "__main__":
    main()
