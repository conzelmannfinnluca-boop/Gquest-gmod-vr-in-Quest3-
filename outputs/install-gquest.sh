#!/usr/bin/env bash
set -euo pipefail
gquest_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gquest_serial="2G0YC5ZG4W00HM"
adb -s "$gquest_serial" get-state
adb -s "$gquest_serial" install --no-incremental -r "$gquest_dir/Gquest.apk"
adb -s "$gquest_serial" shell run-as com.gmodvr.qvrx mkdir -p files/diagnostics
adb -s "$gquest_serial" shell run-as com.gmodvr.qvrx touch files/diagnostics/left-palm-native.enable
adb -s "$gquest_serial" shell am start -a android.intent.action.MAIN -c com.oculus.intent.category.VR -n com.gmodvr.qvrx/com.gmodvr.flat.GameActivity
echo "Gquest installed with the confirmed left-palm profile. Put on the headset and activate both controllers."
