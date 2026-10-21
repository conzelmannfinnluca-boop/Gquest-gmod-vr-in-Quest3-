# Gquest — GDroid als einzige aktive Spielbasis

Stand: 21. Oktober 2026. Zielgeräte: Quest 3 und Quest 3S. Andere Rust-Prototypen bleiben archiviert; es werden hier keine neuen separaten Spielversionen entwickelt. Die vorhandene kleine Rust-Startbibliothek gehört zum bisherigen GDroid-Paket, sie ersetzt nicht dessen Engine.

## Referenzen
- GDroid 0.1.30: https://github.com/tinsarfal/GDroid/releases/tag/0.1.30
- NecrosVideos: Just How GOOD Is Gmod In VR? https://www.youtube.com/watch?v=6JmbX9fl_3g

Video-Metadaten und Beschreibung abgerufen; keine vollständige Frame-/Audioanalyse verfügbar. Folgende Bereiche stammen aus der Beschreibung, nicht aus behaupteten eigenen Beobachtungen einzelner Szenen.

| Bereich | Stand in Gquest | Nächste Prüfung |
|---|---|---|
| VR-Sicht und Bewegung | Auf Quest 3 vom Nutzer bestätigt | Regression nach 0.1.30 |
| Waffen | ArcVR entfernt; native HL2-Waffen/Physgun, 12 Griffprofile | Pistole und SMG-Haltung bestätigt; weitere Einzeltests |
| Objektgewicht | Keine eigene vollständige Gewichtssimulation | Stabiles Zweihandverhalten und physikalische Kräfte messen |
| Knöpfe bedienen | Native Use-Eingaben vorhanden | Kontakt, Abstand und Trefferflächen im Spiel prüfen |
| Objekte greifen | Native HL2-/GMod-Interaktion vorhanden | Linke/rechte Hand, Loslassen und Physgun testen |
| Nachladen | Nur native HL2-Magazin-/Kammerzustände; ArcVR entfernt | Native Gesten und Schießen auf der Quest bestätigen |
| Menüs und Addons | Gquest-Menü plus GDroid-Basis | Eigenes Menü bestätigt; Workshop und breite Addon-Regression offen |
| Bildrate | 72-Hz-Profil, frühere Läufe teils darunter | Frametimes nach Update messen, keine Best-Port-Rangbehauptung |
| Quest 3S | Zielplattform | Kein eigener Hardwaretest bisher |

Das Update und jede Funktion werden getrennt als gebaut, installiert, technisch geprüft oder vom Nutzer bestätigt dokumentiert. Höher aufgelöste Waffenmeshes und H3VR-artige freie Magazinmechanik sind nicht allein durch diese Liste implementiert.

## Verbindliches Ziel und bestätigte Differenzen

Ziel ist GMods PC-VR-Verhalten auf eigenständiger Quest, keine ArcVR-Sonderkollektion. Vollständige1:1-Parität ist noch nicht bewiesen. Die HL2-Pistole sitzt nach expliziter VR-Modellzuordnung korrekt. Der SMG-Zweihandfehler ließ sich auf deckungsgleiche native Griff-Caches zurückführen; Wiederherstellung aus Modell-Attachments wurde vom Nutzer als zweihändig stabil und einhändig richtig bestätigt. Weitere Waffen, Nachladegesten, Greifen, Physgun/Toolgun und Addons müssen jeweils auf konkretes Verhalten geprüft werden.
