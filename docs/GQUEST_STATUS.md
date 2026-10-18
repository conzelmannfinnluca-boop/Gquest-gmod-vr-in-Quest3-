# Gquest: aktueller Stand (17. Oktober 2026)

Privater experimenteller Standalone-Port für Quest 3. Zielpaket: com.gmodvr.qvrx.

## Paket

`outputs/Gquest.apk`, SHA256
**544edd6c0536167fe61f1d604dfd57b4e0388c8d91c268163892dc8f6eb755c4**, enthält
385 Inhaltsdateien: 346 bestehende VR-Assets, 4 eigene Skripte
(gquest_vr_ui.lua, gquest_wrist_hud.lua, gquest_weapon_models.lua,
gquest_weapon_align.lua), 23 Dateien der ArcVR-Glock-Testintegration und
12 Waffenmodell-Zuordnungen.
APK-Signatur (v3), ZIP-Prüfsummen, Inhaltsgrößen und die Übereinstimmung mit den
aktuellen eigenen Quellen, ArcVR-Hashes und Waffenmodell-Skripten sind geprüft
(`work/verify_gquest_package.py`, Ergebnis in `Gquest-build-verification.json`).

Dieser Build ist **lokal geprüft, nicht installiert**. Am 17. Oktober erkennt ADB
kein angeschlossenes Gerät (weder USB noch mDNS). Zuletzt installiert war
cca9d817613bb6be7bb6e11300acf6076784dcdab1387aed84d5179f98c38bbe
(16. Oktober, im Geräteprotokoll als installiert bestätigt); dieser Stand liegt
zur Rückkehr als `work/Gquest-before-weapon-model-report.apk` vor. Ein
Gerätetest des neuen Builds ist nicht erfolgt und wird nicht behauptet.

Der Build vom 17. Oktober (204f3d4436…) mit dem Waffenmodell-Bericht wurde
durch den Ausrichtungs-Build ersetzt; beide sind lokal geprüft, keiner installiert.

## Waffenmodelle: Prüfbericht aus den ausgelieferten Dateien

`outputs/Gquest-weapon-model-audit.md` (Kurzfassung) und
`outputs/Gquest-weapon-model-audit.json` (Details), erzeugt von
`work/generate_weapon_model_audit.py`. Ergebnisse:

- Alle 12 Waffenskripte wählen genau das Modell, das der ausgelieferte Client
  laut seinen eigenen Meldungen erwartet (vrmodel/vrmodel_l, Originalbytes der
  Skripte ansonsten unverändert).
- Alle 26 in den Bibliotheken namentlich referenzierten VR-Modelle
  einschließlich der linkshändigen Varianten sind im Paket vorhanden.
- Jedes In-Hand-Modell trägt ein `grip`-Attachment wenige Einheiten neben
  seinem eigenen Ursprung; das ist der Bezug, den die Engine benutzt.
- Nachweisliche Ursache der falschen Lage: die installierte VRMod-Erweiterung
  speichert in `cl_viewmodeledit.lua` weiterhin Offsets, die für die alten
  Stock-Viewmodels gedacht waren, z. B. `weapon_physgun` (-31,5 / 13,4 / 14,5),
  `weapon_rpg` (-27,5 / 19 / 10,5), `weapon_shotgun` und `weapon_crossbow`
  (-14,5 / 10 / 8,5), `weapon_physcannon` (-31,5 / 13,4 / 10,5). Die neuen
  `vr_*`-Modelle tragen ihren Griff dagegen 0–13,8 Einheiten um den eigenen
  Ursprung. Beides steht jetzt in der Spalte „Addon offset“ des Prüfberichts.
- Die Laufrichtung ist pro Modell unterschiedlich authentisch (y bzw. z), ein
  einzelner globaler Winkel kann also nicht für alle Modelle richtig sein.
  Diese Zahlen wurden erstmals korrekt in Modellkoordinaten gerechnet: das
  Attachment im MDL ist knochenlokal und muss mit der Bind-Matrix seines Bones
  transformiert werden (`work/gquest_model_axis_audit.py`).
- Als Referenz liegen die Hüllgrößen der vorher benutzten Stock-Viewmodels bei
  (`work/stock-models/`, entpackt aus den eigenen VPKs über `work/gquest_vpk.py`).

Der Bericht belegt damit, **was** das Paket liefert und **wie** jedes Modell
aufgebaut ist. Er belegt nicht, wie das Modell auf der Quest in der Hand
gezeichnet wird; dafür entscheidet der ausgelieferte Client zur Laufzeit.

## Neue In-Headset-Prüfung der Waffenmodelle

`work/gquest-ui/lua/autorun/client/gquest_weapon_models.lua`, im Paket als
`lua/autorun/client/gquest_weapon_models.lua`:

- läuft automatisch 20 s nach dem Kartenstart und auf Befehl `gquest_wmodel`
  (ausführlich: `gquest_wmodel_verbose`),
- prüft für alle 12 Waffen das tatsächlich aufgelöste Modell (Schlüssel werden
  rekursiv aus dem geparsten Skript gelesen, weil der Handelsskript-Aufbau
  verschachtelt ist), ob die Datei auf PathID GAME lädt, und ob die 22 vom
  Client namentlich protokollierten Teilemodelle (Magazin, Schlitten, Vorderschaft,
  Hülse, Nachlader) vorhanden sind,
- liest zusätzlich das aktive Waffensmodelle über einen Clientside-Model
  (Attachments, Größe, Skalierung) und ob die Entity das VR-Modell oder das
  Weltmodell benutzt,
- protokolliert die platzierungsrelevanten ConVars (hlvr_grip_yaw_correction,
  vr_viewmodel_offset_forward, vr_custom_mod_*),
- schreibt den vollständigen Bericht nach `data/gquest/weapon_models.json`
  (per `adb pull` holbar) und zeigt im Spiel eine kurze Zusammenfassung.

Zusätzlich hat das eigene Menü (`gquest_vr_ui.lua`) einen Knopf „Waffentest“
bzw. in den VR-Einstellungen „Waffenmodelle pruefen“. Es wird nur gelesen und
berichtet; Waffe, Modell und ConVars bleiben unverändert.

## Handgelenk-HUD: von der Hand weg

Das HUD saß bisher 1,4 Einheiten vor der rohen Handpose, also direkt auf dem
Handschuh, und verdeckte die Hand. Es wird jetzt im Handrahmen versetzt:
`gquest_wrist_hud_offset_side` (Standard 4,5), `..._up` (Standard 5,0) und
`..._forward` (Standard 1,4, Abstand zum Auge) verschieben die Fläche über und
neben den Handrücken, die Hand bleibt an der alten Stelle sichtbar. Alle drei
sind archivierte Client-ConVars, bleiben also erhalten; im Menü unter
„Handgelenk-HUD“ gibt es je +/− 0,5-Knöpfe und „HUD-Lage zuruecksetzen“.
`gquest_wrist_report` gibt Handposition, Panelposition und den Versatz aus, damit
Richtung und Vorzeichen auf dem Gerät beurteilbar sind statt geraten.

Zusätzlich blendet es sich selbst aus, wenn es nur stört:
`gquest_wrist_hud_near_hide` (Standard 14 Einheiten Abstand zum Kopf, 0 = aus)
mit 3 Einheiten Hysterese, damit die Fläche an der Schwelle nicht flackert, und
`gquest_wrist_hud_hide_aim` (Standard an), das beim beidhändigen Griff ausblendet
– gelesen aus `vrmod.IsForegripActive()`, `g_VR.foregripActive` und
`weapon.ForegripGrabbed`; fehlt vrmod, bleibt nur der Nah-Test. Beides steht als
Auswahl im Menü, und jeder Wechsel wird als `GQUEST_WRIST hide=near|aim|nil`
mit Abstand protokolliert.


Geprüft: `work/harness/gquest_wrist_hud_test.lua` (echtes Lua 5.1) rendert die
Fläche mit nachgebauter Pose und prüft 7 Punkte — Standardwerte landen exakt auf
Hand + 1,4·Blickrichtung + 4,5·rechts + 5·oben, Seite/Höhe 0 stellt die alte
Platzierung exakt wieder her (Regressionsschutz), und bei 90° gedrehter Hand
liegen die Versätze weiter in Handachsen (Welt +x). Nicht geprüft: ob das
Vorzeichen auf dem echten Handschuh nach „oben“ zeigt — dafür ist der Gerätelauf
mit `gquest_wrist_report` da.

## Waffenausrichtung (neu)

`work/gquest-ui/lua/autorun/client/gquest_weapon_align.lua`, im Paket als
`lua/autorun/client/gquest_weapon_align.lua`:

- setzt für die 12 HL2-Klassen, deren Skript ein `vr_*`-Modell wählt, den
  veralteten Stock-Offset auf den Handursprung zurück – aber nur für Klassen,
  deren Skript wirklich ein vorhandenes `vr_*`-Modell nennt,
- legt sich nach `VRMod_Start` (und 1 s danach) über die Mod-Konfiguration, weil
  vrmod seine gespeicherte Config beim Start über die Defaults mischt,
- speichert eigene Feinjustierung pro Waffe in `data/gquest/weapon_align.json`
  und über die öffentliche vrmod-API zusätzlich in deren Waffenconfig,
- Befehle: `gquest_align`, `gquest_align_move x y z`, `gquest_align_rot p y r`,
  `gquest_align_step n`, `gquest_align_save`, `gquest_align_reset`,
  `gquest_align_all`, `gquest_align_status`, ConVar
  `gquest_weapon_align_baseline 0|1`,
- Menü: „Waffe ausrichten“ unter „Waffenmodelle“ (Raster für Links/Rechts,
  Näher/Weiter, Höher/Tiefer, Nick/Gier/Roll, Speichern, Zurücksetzen),
- fehlt vrmod oder `g_VR`, meldet das Modul das im Log und ändert nichts.

Das ist eine vorbereitete, lokal geprüfte Korrektur; ob sie auf der Quest die
Lage trifft, entscheidet erst der Blick durch die Brille.

Lua-Prüfung: `work/lua_compile_check.sh` kompiliert alle ausgelieferten
Lua-Dateien mit einem echten Lua 5.1 `luac -p` (lokal aus lua-5.1.5 gebaut,
weil hier kein Interpreter installiert ist): alle 6 Dateien bestehen. Dazu
läuft `work/harness/gquest_weapon_align_test.lua` mit einem echten
Lua-5.1-Interpreter und nachgebauten Engine-Stubs; es prüft im Einzelnen:
Stock-Offsets werden ersetzt (5/5), alle 12 Klassen liegen danach auf dem
Ursprung, gespeicherte Werte gewinnen, zwei 0,5-Schritte summieren sich,
ungespeicherte Änderungen bleiben flüchtig, Speichern/Zurücksetzen wirken
und die vrmod-API wird benutzt, wenn vorhanden (16 Prüfungen, alle bestanden).
Dieser Test hat einen echten Fehler gefunden: der Rückfallpfad ohne
vrmod-API hat zuvor nichts geschrieben und ist behoben. Zusätzlich läuft
`work/lua_syntax_check.py` (Block-/String-Balance).

## Nächster Gerätetest (genau dieser Schritt fehlt)

Ein Befehl dafür ist vorbereitet:
`outputs/run-gquest-weapon-check.sh` (Aufruf `work/gquest_device_check.py`). Es
wartet auf die Brille, installiert `outputs/Gquest.apk`, setzt das private
Left-Palm-Profil, startet die VR-Activity, öffnet den Engine-Befehlssocket
(`adb forward tcp:27100`, Banner `vr_cmdsock` – so meldet es die Engine selbst),
schickt `gquest_wmodel_verbose` und `gquest_align_status` und holt beide Berichte
per `run-as` nach `outputs/Gquest-device-weapon_models.json`,
`outputs/Gquest-device-weapon_align.json` und die `GQUEST_`-Zeilen nach
`outputs/Gquest-device-weapon-check.log`. Ohne Gerät bricht es mit Exit 1 und
klarer Meldung ab, statt Erfolg zu behaupten (lokal geprüft).

Mit aufgesetzter Brille und aktiven Controllern Gquest als VR-App starten, dann
entweder 20 s warten oder im Menü „Waffentest“ drücken. Danach gilt:

- `adb shell run-as com.gmodvr.qvrx cat files/garrysmod/data/gquest/weapon_models.json`
  bzw. die GQUEST_WMODEL-Zeilen im Sitzungsprotokoll holen.
- `weapons=` 12, `matched=` 12, `parts_missing=` 0 bedeutet: alle Waffenmodelle
  werden auf dem Gerät aufgelöst und geladen.
- Für jede Waffe außerdem prüfen, ob die gehaltene Waffe sichtbar richtig sitzt;
  die Entity benutzt bei den HL2-Waffen das Weltmodell (`uses_expected=false`),
  das In-Hand-Modell wählt der Client selbst.
- Danach im Menü „Waffe ausrichten“ die gehaltene Waffe prüfen; stimmt etwas
  nicht, mit den Rasterknöpfen nachziehen und „Speichern“. `gquest_align_status`
  zeigt alle 12 Klassen mit ihren aktuellen Werten.

Offen bleiben weiterhin: vollständiger sichtbarer Menü-Durchlauf, sichtbare
Waffenpose aller 12 Waffen, physisches ArcVR-Nachladen, weitere
ArcVR-Kompatibilität sowie die Crazy-Physics-Warnung aus dem letzten
Sitzungsende (GMod friert den Spieler dabei ein; Ursache ungeprüft).

## Durch frühere Läufe bestätigt

- Benutzer bestätigt Kopftracking, Fortbewegung und Hände grundsätzlich funktionsfähig.
- Benutzer bestätigt Physgun-Ausrichtung mit hlvr_grip_yaw_correction 0.
  Der neue native Start setzt diesen Wert dauerhaft.
- Native Menü-Renderziele wurden im laufenden Spiel angelegt; echte Controller-
  Klicks auf eigene Buttons wurden protokolliert. Der anschließende Engine-Test
  prüfte Öffnen, Zurück, geschlossen bleiben und sichtbares Spawn-Menü erfolgreich.
  Ein vollständiger sichtbarer Controller-Test aller Menüaktionen bleibt offen.
- Der Port wandelt HL2-Waffen nativ in hlvr_weapon_*-Entities um
  (VRWEAP-CONVERT im Geräteprotokoll); die Waffenskripte unter
  scripts/weapon_*.txt liefern dazu vrmodel/vrmodel_l sowie die Teilemodelle.

## Bestätigte Änderungen und verbleibender Umfang

- Eigene vom Alyx-Stil inspirierte linke Handgelenk-HUD mit drei Herzen,
  Rüstung und tatsächlicher Munition. Darstellung war bereits sichtbar,
  laut Benutzer zunächst falsch ausgerichtet. Die neue XR-/Source-Achsenkonvertierung
  und zum Kopf ausgerichtete Lesefläche sind jetzt auf der Quest bestätigt.
- Linke Hand/Finger laut Benutzer verdreht. Modellvergleich zeigt identische
  Hand-Bindungen und weniger als ein Grad Unterschied bei Finger-Grundstellungen.
  Das belegt keine Ursache. Benutzer grenzt ein: Schon die ganze Handfläche ist
  ohne Greifen verdreht. Die gelesenen Knochen-Manipulatoren sind unverändert,
  linke/rechte lokale Handbasen bleiben beim Bewegen annähernd konstant.
  Korrektur im aktuellen Build aktiv und vom Benutzer bestätigt: Linke Hand jetzt richtig.
  Die korrekte rechte Physgun-Ausrichtung bleibt unverändert.
- ArcVR: eigene Klasse gquest_arcvr_aniv_glock, Grundlage anniversary Glock
  aus Pescorr/arcvr_anniversary_bugfix_beta, Commit
  0d8d5bed01c77ad1550097689dc0d1e6fc035385. Kalibrierter nativer Griff,
  echter XR-Trigger und serverseitige Magazin-/Kammerlogik vorbereitet.
  Isolierte Serverlogiktests bestanden. Auf der Quest: Registrierung Client/Server,
  Modelle/Materialien und Worldtracking bestätigt; analoger Trigger aktiv, digitale
  Feueraktion auch ohne Menü inaktiv. Korrigiert: echter analoger Trigger als
  Ersatz mit Druck-/Loslassschwelle0.55/0.45, isolierte reale Think-Tests bestanden.
  Benutzer sah die Glock, aber keinen Schuss. Anschließend konkreter zweiter Fehler
  nachgewiesen: Attachment heißt im MDL "1", während der Code den Bone-Namen
  "muzzle" suchte. Lookup korrigiert und im aktuellen Paket enthalten.
  Im vorigen Lauf reale Glock ausgewählt, Magazin17/Kammer1+16 nachgewiesen.
  Benutzer bestätigt: Glock schießt. Sitzung1792078159 bestätigt jetzt zusätzlich
  17 echte serverseitige Schussausführungen und17 Client-Bestätigungen; die Summe
  von Magazin/Kammer fällt lückenlos von16 bis0. Treffer auf einen Schadensempfänger
  wurden nicht gemessen. Testmunition kommt aus tatsächlichem Pistolenvorrat.
  Physisches Nachladen, Fingerposen und vollständige ArcVR-Kompatibilität fehlen.

## Native Handkorrektur und Diagnosen

Die rein lesende Diagnose work/gquest_left_hand_audit.lua ist bereits unter
files/runtime/lua/gquest_left_hand_audit.lua bereitgestellt; laden mit
lua_openscript_cl gquest_left_hand_audit.lua, dann gquest_left_hand_audit.
Sie prüft sichtbare GLua-Knochen, kann native reine Renderobjekte jedoch verpassen.
Das Paket enthält zusätzlich eine opt-in native Diagnose: privates Gate
files/diagnostics/hand-axis-probe.enable wird einmal konsumiert; maximal6Samples
lesen nach30Sekunden die echten lokalen Controller-/Skelett-/Ersatzposenpfade und
Source-Griffmatrizen auf dem SDL-Ownerthread. Exakte32Byte-Funktionssignatur und
lesbare Speicherbereiche werden geprüft. Keine Tracking-/Modell-/Knochenänderung.
Diagnose ausgeführt: Sitzung1792077564/PID13342,6Samples je Hand. Beide Hände:
vr1, skeletal0, cached1. Konstante seitenabhängige lokale Offsets; der linke Cache
hat Euler(+62.36,+27.12,+10.54), der Konstruktor negiert Pitch/Roll und erzeugt
die beobachteten(-62.36,+27.12,-10.54). Details in work/GQUEST_NATIVE_HAND_AXES.md.

Aktueller Build enthält eine opt-in umschaltbare Korrektur als Test:
Gate files/diagnostics/left-palm-native.enable ist gesetzt. Die exakt geprüfte
Instruktion3a164c wird nur bei aktivem gecachtem linken Controllerpfad von
0x370000b3 nach0x14000005 geändert; rechts ist der Sprungpfad identisch.
Andere lokale Versätze, rohe Posen, Netzwerkdaten und die HUD bleiben unverändert.
Datei entfernen schaltet zurück; ungültiger Cache/anderer Posepfad und SDL_QUIT
stellen die Originalinstruktion wieder her. Shutdown ist gelatcht; Code-Modul
bleibt bis zum Rücksetzen gepinnt. Signatur-, Speicher- und Schreibschutzprüfungen
sind vorhanden. Korrektur kompiliert, APK geprüft/installiert; PID14406 protokolliert
candidate1/cached_controller1 und Benutzer bestätigt die richtige Handfläche.
Protokollpräfix LEFT_PALM, Baseline work/Gquest-before-left-palm.apk.
Installationsskript outputs/install-gquest.sh setzt das notwendige private Profil
bei einer erneuten Installation auf genau dieser Quest; nur die APK auf einem
frischen Gerät zu installieren aktiviert den opt-in Handversatz nicht automatisch.
Das aktuell vorhandene Profil bleibt bei normalen APK-Aktualisierungen erhalten.

Detaillierte frühere Beobachtungen stehen in GQUEST_STATUS_HISTORY.md.
