"""Link existing private build inputs; never download or copy signing keys."""
from pathlib import Path, PurePosixPath
import argparse
import json

ROOT = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--check", action="store_true", help="Validate inputs without creating links")
    args = parser.parse_args()
    workspace = args.workspace.resolve()
    if workspace == ROOT:
        parser.error("Use the original workspace, not this source export")
    relative = [
        "outputs/GDroid-0.1.29.apk", "work/android-sdk", "work/toolchains",
        "work/gdroid-native", "work/quest-vr-content", "work/quest-vr-content-manifest.json",
        "work/gquest-weapon-models/content", "work/arcvr-anniversary",
        "work/sourcevr-core-reference.apk", "work/gquest-arcvr-stock-dependencies.json",
    ]
    manifest = json.loads((ROOT / "work/gquest-arcvr/runtime_manifest.json").read_text())
    for entry in manifest["files"]:
        name = PurePosixPath(entry["path"])
        if name.is_absolute() or ".." in name.parts:
            raise SystemExit("Unsafe manifest path: " + str(name))
        if name.suffix != ".lua":
            relative.append("work/gquest-arcvr/content/" + str(name))
    plan = []
    problems = []
    for name in relative:
        source = workspace / name
        target = ROOT / name
        if not source.exists():
            problems.append("Missing input: " + str(source))
        elif target.exists() or target.is_symlink():
            if not target.is_symlink() or target.resolve() != source.resolve():
                problems.append("Preserving conflicting target: " + str(target))
        else:
            plan.append((source, target))
    if problems:
        raise SystemExit("\n".join(problems))
    if not args.check:
        for source, target in plan:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(source, target_is_directory=source.is_dir())
    print(("CHECK OK: " if args.check else "READY: ") + str(len(relative)) + " private build inputs; " +
          ("no links created" if args.check else str(len(plan)) + " local links created"))

if __name__ == "__main__":
    main()
