# Aktueller GDroid-Build

Im bestehenden privaten Gquest-Arbeitsordner:

```sh
rtk proxy python3 Gquest-Hybrid/tools/build.py
```

Der aktuelle Export enthält den eigenen Integrationscode. Für einen eigenständigen Build aus dieser Kopie müssen die privaten Abhängigkeiten am erwarteten relativen Pfad vorhanden sein: offizielle gepinnte0.1.30-APK, native Bibliotheken, Spiel-/VR-Inhalte und Manifeste, Android-/Rust-/JDK-Toolchains sowie eigener Debug-Signierschlüssel. Diese Dateien sind bewusst nicht Bestandteil des Quellarchivs. Alte Bootstrap-/Test-App-Skripte gehören zur Entwicklungshistorie und sind nicht der aktuelle Build-Einstieg.

Der Build führt die HL2-Menü-, Modell-, Griff-Cache-, Ausrüstungs-, Eingabe- und Navigationsprüfungen sowie die C++-/Rust-/APK-Grenzprüfungen aus.

Vorabprüfung der Eingaben: `tools/build.py` ruft sie als ersten Schritt selbst auf – fehlt eine Eingabe, stoppt der Build mit deren Liste statt mit einem Traceback an der Stelle, die sie zuerst braucht. Fehlt die Prüfdatei selbst, läuft der Build mit einer Warnung weiter wie bisher.

Einzeln aufrufbar (rein lesend, ohne Build):

```sh
python3 work/check_gquest_build.py
```

Prüft Basis-APK, die 33 nativen Bibliotheken, beide Inhalts-Manifeste (VR-Assets, Waffenskripte) und die Werkzeuge samt gepinnter Prüfsummen und listet jede fehlende Eingabe mit Abhilfe. Rückgabewert 1 bedeutet: der Build bricht an dieser Stelle ab. `--root <ordner>` prüft einen anderen Arbeitsordner. Quellarchiv im privaten Hauptprojekt erneut erstellen: `rtk proxy python3 work/package_gdroid_source.py`.
