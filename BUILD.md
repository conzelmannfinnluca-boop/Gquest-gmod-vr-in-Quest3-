# Privater lokaler Build

Diese Quellcode-Kopie besitzt dieselbe `work/`-Struktur wie das ursprüngliche
Projekt. Die vorhandenen APK-Packager können daher unverändert verwendet werden.

## Voraussetzungen prüfen

Benötigt werden Python 3, Bash, der vorhandene Android-NDK 23.2.8568313,
Android Build Tools 34.0.0, der vorhandene JDK sowie die privaten Basispakete
und Modellressourcen des ursprünglichen Gquest-Arbeitsordners.

```bash
cd /home/shift/Documents/Codex/2026-10-13/Gquest/Gquest-Source
rtk proxy python3 prepare_dependencies.py --workspace /home/shift/Documents/Codex/2026-10-13/Gquest --check
```

`--check` verändert keine Dateien. Ohne `--check` legt das Werkzeug ausschließlich
lokale symbolische Verknüpfungen auf die bestehenden privaten Abhängigkeiten an.
Vorhandene widersprechende Zieldateien werden nicht überschrieben.
Die Quellcode-Dateien in dieser Sicherung bleiben eigene, bearbeitbare Kopien.
Verlinkte Binärressourcen solltest du nicht in diesem Export bearbeiten.

## APK aus dieser Kopie bauen

```bash
rtk proxy bash build-local.sh /home/shift/Documents/Codex/2026-10-13/Gquest
```

Der Aufruf kompiliert die native Bridge, aktualisiert das ArcVR-Inhaltsmanifest,
packt die APK, führt zipalign aus, signiert mit dem vorhandenen Android-Debug-Key
und prüft Signatur, ZIP und Inhaltsidentität. Ergebnisse:

- `outputs/Gquest.apk`
- `outputs/Gquest-build-verification.json`

Der ursprüngliche Projektordner wird dabei nur für Abhängigkeiten gelesen.
Es wird nichts auf die Quest installiert. Die neue Kopie wird nicht automatisch
mit späteren Änderungen im Originalordner synchronisiert.

Der Debug-Keystore wird unter `~/.android/debug.keystore` erwartet; alternativ
kann `GQUEST_DEBUG_KEYSTORE` auf einen vorhandenen Android-Debug-Keystore mit
den Standard-Debug-Zugangsdaten zeigen. Keystores gehören nicht in diese Sicherung.
Für einen anderen Rechner müssen die privaten Abhängigkeiten separat bereitstehen.
Der Bootstrap-Test unter `work/gdroid-xr-bootstrap/` ist ein separates Projekt;
seine externen SDK-/Bibliothekseinstellungen müssen für einen Neubau angepasst werden.

## Vorhandene Lua-Prüfungen

Mit einem vorhandenen Lua-5.1-Compiler:

```bash
rtk proxy bash work/lua_compile_check.sh
```

Die vorhandenen Harness-Dateien unter `work/harness/` und die beiden ArcVR-
Testdateien bilden Engine-Grenzen nach. Sie ersetzen keinen Test in der Brille.

Die Erstellung dieser Sicherung prüft Kopieridentität, Python-Syntax,
Shell-Syntax und verfügbare Build-Abhängigkeiten. Ein vollständiger APK-Neubau
und ein neuer Quest-Test sind nicht Teil der Quellcode-Sicherung.
