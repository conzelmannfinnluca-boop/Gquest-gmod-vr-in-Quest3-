# Gquest – Quellcode

Lokale Quellcode-Sicherung vom 18. Oktober 2026. Enthält den aktuell im Projekt
vorhandenen eigenen Gquest-Code, Build-Werkzeuge und Tests.

## Hier findest du den Code

- `work/quest_engine_bridge.cpp`: native Android-/OpenXR-Brücke und Handkorrektur.
- `work/gquest-ui/lua/autorun/client/`: Menü, Handgelenk-HUD,
  Waffenmodell-Diagnose und Ausrichtung.
- `work/gquest-arcvr/content/lua/`: eigener ArcVR-Adapter und Glock-SWEP.
- `work/gquest-arcvr/derive_grip.py`: reproduzierbare Glock-Griffkorrektur.
- `work/gquest_decode_idle_root.py`: Decoder der tatsächlichen Idle-Wurzelpose.
- `work/gdroid-xr-bootstrap/`: Quellcode und Konfiguration des XR-Bootstrap-Tests.
- `work/build_quest_lab.py`: APK-Packager.
- `work/verify_gquest_package.py`: APK-Signatur-/Inhaltsprüfung.
- `work/harness/`, `work/gquest-arcvr/test_*.lua`: vorhandene Tests.
- Weitere Probe-/Audit-Skripte unter `work/` sind Entwicklungswerkzeuge;
  sie werden nicht automatisch in das Spiel geladen.

`SOURCE_FILES.json` enthält Originalpfade, Dateigrößen und SHA256-Prüfsummen.
Die Ordnerstruktur entspricht dem bestehenden Projekt, damit relative Pfade
in den vorhandenen Skripten erhalten bleiben.

## Umfang

Dies ist der verfügbare Gquest-Anpassungscode, nicht der vollständige Quellcode
von Garry’s Mod, GDroid oder der Source-Engine. APKs, Spielemodelle/-texturen,
SDKs, kompilierte Bibliotheken, Signierschlüssel und das vollständige ArcVR-
Repository sind keine Bestandteile dieser Sicherung. Die Lua-Waffenintegration
orientiert sich an Pescorr/arcvr_anniversary_bugfix_beta, Commit
`0d8d5bed01c77ad1550097689dc0d1e6fc035385`; Herkunft und Anpassungen sind
in `work/gquest-arcvr/ADAPTATION.md` und den Manifesten beschrieben.
Es wird keine neue Lizenz für fremde Bestandteile vergeben.

## Bauen

Siehe `BUILD.md`. Für den privaten APK-Build werden die bereits lokal vorhandenen
Abhängigkeiten aus dem übergeordneten Gquest-Projekt benötigt. Diese werden nur
auf ausdrücklichen Aufruf von `prepare_dependencies.py` lokal verlinkt.
Der Build verwendet ausschließlich die Quellcode-Kopie in diesem Ordner und
schreibt seine Ergebnisse hier nach `work/` und `outputs/`.

## Stand

Die Sicherung enthält auch jüngere HUD-/Ausrichtungsänderungen, deren
Darstellung auf der Quest noch geprüft werden muss. Das beigefügte bisherige
Build-Protokoll ist eine Momentaufnahme des übergeordneten Projekts und keine
neue Kompilierungs- oder Geräteprüfung dieses Exports.
