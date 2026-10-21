"""Build the Rust/C++ bridge, package existing GDroid, check unchanged payloads."""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
BASE = PROJECT.parent
WORK = BASE / 'work'
OUT = PROJECT / 'dist'
OUT.mkdir(exist_ok=True)
NDK = WORK / 'android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin'
TOOLS = WORK / 'android-sdk/build-tools/34.0.0'
JAVA = WORK / 'toolchains/jdk/bin/java'

def run(*args):
    subprocess.run([str(a) for a in args], cwd=BASE, check=True)

def cargo(*args):
    run(sys.executable, PROJECT / 'tools/cargo.py', *args)

run(sys.executable, WORK / 'verify_gdroid_base.py')
run(sys.executable, WORK / 'run_lua_checks.py',
    WORK / 'harness/test_hl2_grip_cache.lua',
    WORK / 'harness/test_hl2_native_models.lua',
    WORK / 'harness/test_hl2_equipment.lua',
    WORK / 'harness/test_hl2_weapon_catalog.lua',
    WORK / 'harness/test_native_pose_class.lua',
    WORK / 'test_reload_client.lua', WORK / 'test_gquest_menu_navigation.lua')
cargo('test')
run('c++', '-std=c++17', '-O2', '-I' + str(PROJECT / 'bridge'),
    PROJECT / 'tests/native_fingers.cpp', '-ldl', '-o', OUT / 'native-fingers-test')
run(OUT / 'native-fingers-test')
run('c++', '-std=c++17', '-O2', '-I' + str(PROJECT / 'bridge'),
    PROJECT / 'tests/vr_lua.cpp', '-ldl', '-o', OUT / 'vr-lua-test')
run(OUT / 'vr-lua-test')
run('c++', '-std=c++17', '-O2', '-I' + str(PROJECT / 'bridge'),
    PROJECT / 'tests/retired_content.cpp', '-o', OUT / 'retired-content-test')
run(OUT / 'retired-content-test')
cargo('build', '--release')
run('c++', '-std=c++17', '-I' + str(PROJECT / 'include'), PROJECT / 'tests/ffi_smoke.cpp',
    PROJECT / 'target/release/libgquest_runtime.a', '-ldl', '-lpthread', '-lm', '-o', OUT / 'ffi-smoke')
run(OUT / 'ffi-smoke')
cargo('build', '--release', '--target', 'aarch64-linux-android')
run(NDK / 'aarch64-linux-android29-clang++', '-shared', '-fPIC', '-O2',
    '-I' + str(PROJECT / 'include'), PROJECT / 'bridge/quest_engine_bridge.cpp',
    PROJECT / 'target/aarch64-linux-android/release/libgquest_runtime.a',
    '-o', WORK / 'liblauncheq.so', '-llog', '-ldl', '-lEGL', '-lGLESv3', '-landroid',
    '-Wl,--no-undefined', '-Wl,--exclude-libs,ALL', '-Wl,--no-as-needed',
    WORK / 'gdroid-0.1.30-native/liblauncher.so', '-Wl,-soname,liblauncheq.so')
run(sys.executable, WORK / 'build_quest_lab.py')
run(TOOLS / 'zipalign', '-f', '-p', '4', WORK / 'GMod-Quest-Lab-unsigned.apk', WORK / 'GMod-Quest-Lab-aligned.apk')
run(JAVA, '-jar', TOOLS / 'lib/apksigner.jar', 'sign', '--ks', Path.home() / '.android/debug.keystore',
    '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', WORK / 'Gquest.apk', WORK / 'GMod-Quest-Lab-aligned.apk')
run(sys.executable, WORK / 'verify_gquest_package.py')
apk = WORK / 'Gquest.apk'
baseline = BASE / "outputs/GDroid-0.1.30.apk"
with zipfile.ZipFile(baseline) as before, zipfile.ZipFile(apk) as after:
    content = lambda z: {n for n in z.namelist() if not n.startswith("META-INF/")}
    prefix="assets/quest_lab_vr_content/"
    assert not content(before)-content(after), "Unexpected base APK member removal"
    added=sorted(content(after)-content(before))
    assert all(n.startswith(prefix) or n in {"assets/quest_lab_vr_content.tsv","lib/arm64-v8a/liblauncheq.so"} for n in added)
    changed=[n for n in sorted(content(before)&content(after)) if before.read(n)!=after.read(n)]
    assert set(changed)=={"AndroidManifest.xml","classes.dex","lib/arm64-v8a/libclient.so"}, changed
    # New launcher, runtime payload, menu resources and every other native library
    # must come from official 0.1.30, never a mixture with the previous base.
    for n in content(before)-set(changed):
        assert before.read(n)==after.read(n), n
shutil.copy2(apk, OUT / 'Gquest-Rust-GDroid.apk')
report = dict(version='0.1.30-gquest', upstream_version='0.1.30', package='com.gmodvr.qvrx', rust_role='VR profiles and owned launcher arguments',
              engine='existing GDroid', renderer='existing libvrxr; no Hotham session',
              apk_sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
              rust_tests=5, cpp_rust_abi_smoke='passed', native_finger_wrapper_test='passed', vr_lua_compatibility_test='passed',
              changed_apk_payloads=changed, added_gquest_overlay_payloads=added,
              existing_models_engine_payloads='official 0.1.30 base; only audited client VR-player instruction patched; own bridge and Lua added',
              native_fingers='opt-in exact-build native blend adapter; original left/root/curl sampling retained',
              signature='verified', zip_crc='passed', quest_test='pending')
(OUT / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({k:v for k,v in report.items() if k!='added_gquest_overlay_payloads'}, indent=2))
