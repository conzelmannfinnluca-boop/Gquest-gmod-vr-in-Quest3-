# APK-Build in GitHub Actions

Der Workflow `.github/workflows/build-apk.yml` baut das signierte Gquest-APK auf
einem GitHub-Runner. Er ist **manuell** (Actions → „Gquest APK" → „Run workflow"),
damit nicht jeder Push Minuten verbraucht.

Alles, was der Build braucht, ist entweder öffentlich oder kommt aus **einem**
Release-Asset mit deinen privaten Dateien. Ohne dieses Asset bricht der Workflow
in der Vorabprüfung mit der Liste der fehlenden Eingaben ab – nicht mit einem
Traceback mitten im Build.

## 1. Was in das private Archiv gehört

Aus dem **privaten Arbeitsordner** (dort, wo `work/` und `outputs/` liegen):

```sh
cd /pfad/zum/privaten/ordner

tar -czf /tmp/gquest-private-inputs.tar.gz \
    work/quest-vr-content \
    work/quest-vr-content-manifest.json \
    work/gquest-weapon-models/content \
    work/gquest-ui/lua/autorun/server \
    work/gquest-ui/lua/autorun/client/gquest_weapon_catalog.lua \
    work/gdroid130-compat
```

Die Pfade müssen **genau so** im Archiv stehen (relativ zur Wurzel), weil der
Workflow es über das Repo entpackt.

Kurz prüfen:

```sh
tar -tzf /tmp/gquest-private-inputs.tar.gz | head -5
tar -tzf /tmp/gquest-private-inputs.tar.gz | grep -c 'work/quest-vr-content/'   # ~346 Dateien
```

## 2. Archiv als Release-Asset ablegen

Einmalig (GitHub CLI, kein Browser nötig):

```sh
gh release create inputs-latest /tmp/gquest-private-inputs.tar.gz \
   --title "Gquest Build-Eingaben" \
   --notes "Private Eingaben für den CI-Build. Nicht veröffentlichen."
```

Nach Änderungen an Modellen, VR-Assets oder den privaten Lua-Dateien:

```sh
gh release upload inputs-latest /tmp/gquest-private-inputs.tar.gz --clobber
```

Der Workflow liest Tag `inputs-latest` und Datei `gquest-private-inputs.tar.gz`
(beides steht oben in der YAML unter `env:`).

**Variante ohne Release:** Liegen die privaten Dateien ohnehin im selben Repo
(privates Repo bzw. dein privater Build-Ordner als Repo), dann überspringt der
Workflow den Download und prüft die Dateien direkt im Arbeitsbaum. Dann genügt
`gh workflow run build-apk.yml` – kein Upload nötig.

## 3. Workflow starten und APK holen

```sh
gh workflow run build-apk.yml
gh run watch
gh run download -n Gquest-apk          # work/Gquest.apk + Prüfberichte
```

Oder im Browser: Actions → „Gquest APK" → „Run workflow" → nach dem Lauf das
Artefakt `Gquest-apk` herunterladen.

Das APK ist mit demselben Debug-Schlüssel signiert wie dein lokaler Build
(`pass:android`, Alias `androiddebugkey`) und lässt sich wie gewohnt per
`bash outputs/install-gquest.sh` bzw. `adb install -r` installieren.

## 4. Was der Runner selbst beschafft

| Eingabe | Quelle im Workflow |
|---|---|
| Basis-APK 0.1.30 | offizielle Release-URL, SHA256 gegen den Pin geprüft (`28bcce6d…`) |
| 34 native Bibliotheken | `python3 work/unpack_base_natives.py` aus der Basis-APK, jede gegen den Pin geprüft |
| NDK 23.2.8568313 | `dl.google.com/android/repository/android-ndk-r23b-linux.zip` |
| build-tools 34.0.0 | `dl.google.com/android/repository/build-tools_r34-linux.zip` (enthält `zipalign`, `lib/apksigner.jar`) |
| JDK 17 | `actions/setup-java`, als `work/toolchains/jdk` verlinkt |
| Rust + aarch64-Ziel | rustup in **deine** privaten Pfade `work/toolchains/cargo` / `work/toolchains/rustup`, weil `tools/cargo.py` genau die benutzt |
| `liblua5.4.so.0` | `apt-get install liblua5.4-0` (für `work/run_lua_checks.py`) |
| Debug-Keystore | per `keytool` im Job erzeugt |

**Nicht** hochladen: Basis-APK, Toolchains, Keystore, gebaute APKs.

## 5. Grenzen und Hinweise

* **Repo privat halten.** Die VR-Assets enthalten Valve-/Mod-Material; ein
  öffentliches Repo würde sie mitveröffentlichen. Auch der Release-Asset ist für
  jeden mit Lesezugriff aufs Repo sichtbar.
* Release-Assets dürfen bis 2 GB groß sein; Archive über ~1 GB besser vorher
  prüfen (unerwartet große Texturen). Dateien über 100 MB dürfen **nicht** ins
  Repo selbst.
* Der Runner hat 14 GB Platte; NDK (~2–3 GB entpackt) + Rust + Assets passen,
  die Archive werden nach dem Entpacken gelöscht.
* Ein Job darf 6 Stunden laufen (der Build braucht Minuten). Artefakte laufen
  nach 90 Tagen ab.
* Kostenlos und unbegrenzt sind Standard-Runner nur in **öffentlichen** Repos;
  privat gilt das Monatskontingent deines Plans (Free: 2.000 Linux-Minuten).
* Der Workflow nimmt automatisch `Gquest-Hybrid/tools/build.py`, falls es
  existiert, sonst `Gquest/tools/build.py`. Diese Datei muss also im Repo liegen.

## 6. Wenn etwas fehlt

Der Schritt „Vorabpruefung der Build-Eingaben" nennt jede fehlende Datei mit
Abhilfe und bricht dort ab. Typische Fälle:

| Meldung | Ursache |
|---|---|
| `FEHLT work/quest-vr-content` | Archiv unvollständig oder mit falschem Wurzelpfad gepackt |
| `FEHLT … mit falscher Prüfsumme` | Datei geändert, aber `quest-vr-content-manifest.json` nicht neu erzeugt |
| `gh: Not Found (HTTP 404)` | Release-Tag/Dateiname weicht von `env:` ab (nur nötig, wenn die Eingaben nicht schon im Repo liegen), oder `contents: read` fehlt |
| `FEHLT work/toolchains/cargo` | Rust-Schritt übersprungen |
| `Kein Build-Einstieg gefunden` | `tools/build.py` fehlt im Repo |

Lokal dieselbe Prüfung, ohne CI:

```sh
python3 work/check_gquest_build.py
```
