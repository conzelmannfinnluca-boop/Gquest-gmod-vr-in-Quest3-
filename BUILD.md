# Aktueller GDroid-Build

Im bestehenden privaten Gquest-Arbeitsordner:

```sh
rtk proxy python3 Gquest-Hybrid/tools/build.py
```

Der aktuelle Export enthält den eigenen Integrationscode. Für einen eigenständigen Build aus dieser Kopie müssen die privaten Abhängigkeiten am erwarteten relativen Pfad vorhanden sein: offizielle gepinnte0.1.30-APK, native Bibliotheken, Spiel-/VR-Inhalte und Manifeste, Android-/Rust-/JDK-Toolchains sowie eigener Debug-Signierschlüssel. Diese Dateien sind bewusst nicht Bestandteil des Quellarchivs. Alte Bootstrap-/Test-App-Skripte gehören zur Entwicklungshistorie und sind nicht der aktuelle Build-Einstieg.

Der Build führt die HL2-Menü-, Modell-, Griff-Cache-, Ausrüstungs-, Eingabe- und Navigationsprüfungen sowie die C++-/Rust-/APK-Grenzprüfungen aus. Quellarchiv im privaten Hauptprojekt erneut erstellen: `rtk proxy python3 work/package_gdroid_source.py`.
