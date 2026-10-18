#!/usr/bin/env bash
# Build this source snapshot into a separate private APK; never install it.
set -euo pipefail
gquest_source_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gquest_workspace="${1:-$gquest_source_dir/..}"
cd "$gquest_source_dir"
python3 prepare_dependencies.py --workspace "$gquest_workspace"
gquest_compiler="$gquest_source_dir/work/android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android29-clang++"
gquest_java="$gquest_source_dir/work/toolchains/jdk/bin/java"
gquest_buildtools="$gquest_source_dir/work/android-sdk/build-tools/34.0.0"
gquest_keystore="${GQUEST_DEBUG_KEYSTORE:-$HOME/.android/debug.keystore}"
if [[ ! -x "$gquest_compiler" || ! -x "$gquest_java" || ! -f "$gquest_keystore" ]]; then
    echo "Missing NDK compiler, JDK, or existing Android debug keystore. See BUILD.md." >&2
    exit 1
fi
mkdir -p outputs
"$gquest_compiler" -shared -fPIC -O2 work/quest_engine_bridge.cpp -o work/liblauncheq.so     -llog -ldl -lEGL -lGLESv3 -landroid -Wl,--no-as-needed work/gdroid-native/liblauncher.so -Wl,-soname,liblauncheq.so
python3 work/gquest-arcvr/manifest_runtime.py
python3 work/build_quest_lab.py
"$gquest_buildtools/zipalign" -f -p 4 work/GMod-Quest-Lab-unsigned.apk work/GMod-Quest-Lab-aligned.apk
"$gquest_java" -jar "$gquest_buildtools/lib/apksigner.jar" sign     --ks "$gquest_keystore" --ks-pass pass:android --key-pass pass:android     --out work/Gquest.apk work/GMod-Quest-Lab-aligned.apk
python3 work/verify_gquest_package.py
printf 'Built and package-verified: %s/outputs/Gquest.apk\n' "$gquest_source_dir"
