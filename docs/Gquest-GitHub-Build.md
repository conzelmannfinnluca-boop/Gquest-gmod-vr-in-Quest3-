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

Das APK ist mit deinem Release-Schlüssel aus den Secrets signiert (siehe
Abschnitt 3b) und lässt sich wie gewohnt per `bash outputs/install-gquest.sh`
bzw. `adb install -r` installieren. Ohne hinterlegte Secrets bricht der Lauf ab.

## 3b. Eigener Signaturschlüssel (statt Debug-Key)

Mit einem eigenen Schlüssel tragen alle Builds dieselbe Signatur – nur so lässt
sich eine installierte GQuest-Version per `adb install -r` aktualisieren. Der
Debug-Key taugt dafür nicht: er liegt nicht in der CI und ist nicht dauerhaft.

Einmalig auf dem eigenen Rechner:

```sh
keytool -genkeypair -keystore gquest-release.jks -alias gquest \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -dname "CN=Gquest, O=Gquest, C=DE"

# Fingerabdruck notieren (muss bei jeder APK gleich sein)
keytool -list -v -keystore gquest-release.jks -alias gquest | grep SHA256

# Keystore als Base64 für das Secret
base64 -w0 gquest-release.jks > gquest-release.jks.b64   # macOS: base64 -i
```

Dann unter Repository → Settings → Secrets and variables → Actions anlegen:

| Secret | Inhalt |
|---|---|
| `GQUEST_KEYSTORE_B64` | kompletter Inhalt von `gquest-release.jks.b64` |
| `GQUEST_KEYSTORE_PASS` | Store-Passwort |
| `GQUEST_KEY_ALIAS` | `gquest` |
| `GQUEST_KEY_PASS` | Key-Passwort, nur falls abweichend |

Fehlen die Secrets, bricht der Lauf beim Schritt „Signaturschluessel aus den
Secrets" mit `::error::` ab – er fällt nicht still auf den Debug-Key zurück.
Der Job prüft Passwort und Alias mit `keytool`, zeigt den SHA256-Fingerabdruck im
Log und löscht den Keystore am Ende wieder (`if: always()`). Die Passwörter
gehen als `env:`-Referenz an `apksigner`, stehen also nicht in der Prozessliste.

**Keystore und Passwörter sicher aufbewahren.** Ist der Schlüssel weg, lässt
sich keine APK mehr über eine bestehende Installation legen; Nutzer müssten
deinstallieren (Spielstände/Mods im App-Verzeichnis gehen dabei verloren).

`bash outputs/install-gquest.sh` vergleicht vor dem Installieren den
Signatur-Fingerabdruck des neuen APKs mit der installierten Version und bricht
mit beiden Fingerabdrücken plus Backup-/Deinstallationsbefehlen ab, wenn sie
nicht übereinstimmen. Fehlt `apksigner` oder ist die installierte APK nicht
lesbar, warnt es nur und installiert wie bisher – dann fängt erst `adb install`
den Fehler `INSTALL_FAILED_UPDATE_INCOMPATIBLE` ab.

Lokal mit demselben Schlüssel bauen (der Debug-Key bleibt der Standard, wenn
diese Variablen fehlen):

```sh
GQUEST_KEYSTORE=~/gquest-release.jks GQUEST_KEY_ALIAS=gquest \
GQUEST_KEYSTORE_PASS=… python3 Gquest/tools/build.py

# danach prüfen
java -jar work/android-sdk/build-tools/34.0.0/lib/apksigner.jar verify --print-certs work/Gquest.apk
```

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
| Release-Keystore | aus den Secrets `GQUEST_KEYSTORE_B64`, `GQUEST_KEYSTORE_PASS`, `GQUEST_KEY_ALIAS`, `GQUEST_KEY_PASS` (siehe Abschnitt 3b) |

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
