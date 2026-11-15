#!/usr/bin/env bash
# Committet die privaten Build-Eingaben aus dem privaten Arbeitsordner und pusht
# sie, damit der CI-Build sie findet.
#
#   bash work/push_private_inputs.sh --dry-run   # nur zeigen, was passieren würde
#   bash work/push_private_inputs.sh            # prüfen, committen, pushen
#   bash work/push_private_inputs.sh --no-push  # committen ohne push (Test)
#
# Das Skript staged ausschliesslich die privaten Pfade, keine anderen Aenderungen.
set -euo pipefail

root="$(git rev-parse --show-toplevel)"
cd "$root"

dry_run=0
do_push=1
for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --no-push) do_push=0 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unbekannte Option: $arg (erlaubt: --dry-run, --no-push)"; exit 2 ;;
    esac
done

paths=(
    work/quest-vr-content
    work/quest-vr-content-manifest.json
    work/gquest-weapon-models/content
    work/gdroid130-compat/audit.json
    work/gquest-ui/lua/autorun/client/gquest_weapon_catalog.lua
    work/gquest-ui/lua/autorun/server/gquest_hl2_equipment.lua
    work/gquest-ui/lua/autorun/server/gquest_hl2_models.lua
)

missing=0
for path in "${paths[@]}"; do
    if [ ! -e "$path" ]; then
        echo "FEHLT $path"
        missing=1
    fi
done
if [ "$missing" -ne 0 ]; then
    echo
    echo "Dieses Skript muss in dem Arbeitsordner laufen, in dem die privaten"
    echo "Eingaben liegen (mit work/ und outputs/). In diesem Ordner: $root"
    exit 1
fi

echo "== Groesse =="
du -sh "${paths[@]}" | sort -h | tail -n 8

too_large=0
while IFS= read -r file; do
    size="$(stat -c%s "$file")"
    mb=$((size / 1000000))
    if [ "$size" -ge 100000000 ]; then
        echo "ZU GROSS  $file (${mb} MB) - Git lehnt Dateien ueber 100 MB ab."
        echo "          Abhilfe: git lfs track \"<muster>\" und die Datei erneut adden"
        too_large=1
    else
        echo "HINWEIS   $file (${mb} MB) - knapp unter dem 100-MB-Limit"
    fi
done < <(find "${paths[@]}" -type f -size +90000k 2>/dev/null || true)
if [ "$too_large" -ne 0 ]; then
    exit 1
fi

if [ -f work/check_gquest_build.py ]; then
    echo "== Vorabpruefung =="
    if ! python3 work/check_gquest_build.py; then
        echo "HINWEIS: Die Vorabpruefung meldet noch fehlende Eingaben (Liste oben)."
        echo "         Der Push funktioniert trotzdem; der CI-Lauf wird dort abbrechen."
    fi
fi

echo "== Stagen =="
if [ "$dry_run" -eq 1 ]; then
    printf 'git add -- \\\n'
    printf '    %s \\\n' "${paths[@]}"
    echo 'git commit -m "Private Build-Eingaben für den CI-Build"'
    [ "$do_push" -eq 1 ] && echo 'git push origin <aktueller Branch>'
    exit 0
fi

git add -- "${paths[@]}"
if git diff --cached --quiet; then
    echo "Nichts zu committen - die Eingaben liegen bereits im Repo."
else
    git commit -m "Private Build-Eingaben für den CI-Build"
fi

if [ "$do_push" -eq 1 ]; then
    branch="$(git rev-parse --abbrev-ref HEAD)"
    echo "== Push nach origin/$branch =="
    git push origin "$branch"
fi

echo
echo "Fertig. Lauf starten (nicht 'Re-run jobs' auf einem alten Lauf):"
echo "  gh workflow run build-apk.yml --ref main"
echo "  gh run list --workflow build-apk.yml --limit 3     # muss den neuen Commit zeigen"
