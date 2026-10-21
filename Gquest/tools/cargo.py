"""Use this workspace's private Rust/NDK installation without shell changes."""
import os
from pathlib import Path
import subprocess
import sys
PROJECT = Path(__file__).resolve().parents[1]
WORK = PROJECT.parent / 'work'
CARGO = WORK / 'toolchains/cargo'
NDK = WORK / 'android-sdk/ndk/23.2.8568313/toolchains/llvm/prebuilt/linux-x86_64/bin'
env = os.environ.copy()
env.update(CARGO_HOME=str(CARGO), RUSTUP_HOME=str(WORK / 'toolchains/rustup'),
           CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER=str(NDK / 'aarch64-linux-android29-clang'))
env['PATH'] = str(CARGO / 'bin') + ':' + env['PATH']
raise SystemExit(subprocess.call([str(CARGO / 'bin/cargo'), *sys.argv[1:]], cwd=PROJECT, env=env))
