# Gquest GDroid0.1.30 — aktuelle eigene Quellen

Aktive Version: standalone GDroid-App com.gmodvr.qvrx, Ziel Quest3/3S. ArcVR ist auf Nutzerwunsch aus Paket, Waffenmenü und Griffprofilen entfernt. Der Startup-Migrationscode sichert ausschließlich die63 früher installierten ArcVR-Dateien außerhalb des gemounteten Spielordners. Alte ArcVR-Quellen bleiben außerhalb dieses aktuellen Exports als private Historie erhalten.

Die nativen HL2-Waffen bekommen ihre passenden VR-Modelle nach Deploy zugewiesen. Ihre zuvor praktisch deckungsgleichen nativen Griff-Caches werden aus tatsächlichen Modell-Attachments erneuert. Reale Hand-/Kopfdaten, Magazin- und Schusszustände bleiben bei der Engine. Benutzer bestätigt: HL2-Pistole korrekt ausgerichtet; SMG-Haltung und Schießen gut; SMG zweihändig stabil und einhändig richtig nach Cache-Korrektur. Weitere Waffen und Nachladegesten sind nicht pauschal als fertig bestätigt.

Build: `rtk proxy python3 Gquest-Hybrid/tools/build.py`. Der bestehende private Arbeitsordner mit offizieller0.1.30-Basis, eigenen Spiel-/VR-Dateien, SDK/JDK/NDK und Signierschlüssel ist Voraussetzung. Diese privaten Abhängigkeiten sind nicht Teil des Archivs. Eigene C++-/Rust-/Lua-Quellen, Konverter, Daten-Metadaten und sinnvolle Grenztests sind enthalten. Keine Engine-Bibliotheken, SDKs, Modelle, Texturen oder Schlüssel werden exportiert.

APK-SHA256: `676e7f6f9723645643e580b2114d911a494748df3bde9a452a0771749d69a40c`. Installations-/Neustartnachweis: docs/Gquest-HL2-only-verification.json. Vollständige1:1-PCVR-/Addon-Parität und Quest3S-Hardwaretest bleiben offen.

Mündungs- und Griff-Caches werden aus den tatsächlichen VR-Modellpunkten aktualisiert. Bestätigte HL2-Treffer und verbleibender Brechstangenfehler: docs/Gquest-HL2-damage-verification.json.

Brechstangenrichtung vom Träger bestätigt und dauerhaft je Waffenklasse korrigiert; wiederholtes Laden akkumuliert keinen Winkel.
