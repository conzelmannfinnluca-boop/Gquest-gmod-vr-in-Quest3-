#!/usr/bin/env bash
# Installiert das gebaute GQuest-APK auf der Quest.
#
# Vorab wird die Signatur verglichen: Android lehnt ein Update ab, wenn die
# installierte Version mit einem anderen Schluessel signiert ist
# (INSTALL_FAILED_UPDATE_INCOMPATIBLE). Dann nennt das Skript die Fingerabdruecke
# und bricht ab, statt in den adb-Fehler zu laufen.
set -euo pipefail

gquest_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gquest_root="$(dirname -- "$gquest_dir")"
gquest_serial="${GQUEST_SERIAL:-2G0YC5ZG4W00HM}"
package="com.gmodvr.qvrx"
apk="$gquest_dir/Gquest.apk"

[ -f "$apk" ] || { echo "FEHLT $apk - erst bauen (python3 Gquest/tools/build.py)."; exit 1; }

# --- Werkzeuge fuer die Signaturpruefung (fehlen sie, wird nur gewarnt) ---
java_bin=""
if [ -x "$gquest_root/work/toolchains/jdk/bin/java" ]; then
    java_bin="$gquest_root/work/toolchains/jdk/bin/java"
elif command -v java > /dev/null 2>&1; then
    java_bin="$(command -v java)"
fi
apksigner_jar=""
for candidate in "$gquest_root"/work/android-sdk/build-tools/*/lib/apksigner.jar; do
    [ -f "$candidate" ] && apksigner_jar="$candidate"
done

signer_of() {  # $1 = APK; gibt den SHA-256 des Signaturzertifikats aus
    "$java_bin" -jar "$apksigner_jar" verify --print-certs "$1" 2>/dev/null \
        | grep -i 'certificate SHA-256' | head -1 \
        | sed 's/.*: //' | tr -d ':' | tr 'A-F' 'a-f' || true
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

adb -s "$gquest_serial" get-state

# --- Signatur-Vorabpruefung ---
new_signer=""
if [ -n "$java_bin" ] && [ -n "$apksigner_jar" ]; then
    new_signer="$(signer_of "$apk")"
fi
installed_path="$(adb -s "$gquest_serial" shell pm path "$package" 2>/dev/null \
    | sed -n 's/^package://p' | head -1 | tr -d '\r' || true)"
installed_signer=""
if [ -n "$installed_path" ] && [ -n "$new_signer" ]; then
    if adb -s "$gquest_serial" pull "$installed_path" "$tmp/installed.apk" > /dev/null 2>&1 \
        && [ -s "$tmp/installed.apk" ]; then
        installed_signer="$(signer_of "$tmp/installed.apk")"
    fi
fi

if [ -z "$new_signer" ]; then
    echo "HINWEIS: apksigner/JDK nicht gefunden - Signatur nicht vorab pruefbar."
elif [ -z "$installed_path" ]; then
    echo "Signatur: Neuinstallation ($package ist nicht installiert)."
elif [ -z "$installed_signer" ]; then
    echo "HINWEIS: installierte APK nicht lesbar - Signatur nicht vorab pruefbar."
elif [ "$new_signer" = "$installed_signer" ]; then
    echo "Signatur: gleicher Schluessel (${new_signer:0:16}...) - Update direkt moeglich."
else
    cat <<TEXT
SIGNATUR PASST NICHT - Android verweigert dieses Update.
  installiert: ${installed_signer:0:16}...
  neues APK:   ${new_signer:0:16}...

Einmal deinstallieren. Die Deinstallation loescht files/garrysmod, deshalb
vorher sichern:
  adb -s $gquest_serial exec-out run-as $package tar -cf - files > gquest-backup.tar
  tar -tf gquest-backup.tar | head        # nicht leer? dann weiter

Dann:
  adb -s $gquest_serial uninstall $package
  bash "$0"                    # installiert das neue APK

Zum Schluss den Spielstand zurueckspielen:
  cat gquest-backup.tar | adb -s $gquest_serial shell run-as $package tar -xf - -C files
TEXT
    exit 1
fi

install_log="$tmp/install.log"
if ! adb -s "$gquest_serial" install --no-incremental -r "$apk" 2>&1 | tee "$install_log"; then
    if grep -qi 'UPDATE_INCOMPATIBLE\|signatures do not match' "$install_log"; then
        echo "Android hat das Update wegen abweichender Signatur abgelehnt: einmal deinstallieren (siehe oben)."
    fi
    exit 1
fi

adb -s "$gquest_serial" shell run-as com.gmodvr.qvrx mkdir -p files/diagnostics
adb -s "$gquest_serial" shell run-as com.gmodvr.qvrx touch files/diagnostics/left-palm-native.enable
adb -s "$gquest_serial" shell am start -a android.intent.action.MAIN -c com.oculus.intent.category.VR -n com.gmodvr.qvrx/com.gmodvr.flat.GameActivity
echo "Gquest installed with the confirmed left-palm profile. Put on the headset and activate both controllers."
