# H3VR-artiges Waffenhandling (körperliches Magazin)

Stand: 15. November 2026. Referenz des Nutzers:
[H3VR2 – All Guns Showcase](https://www.youtube.com/watch?v=R06MqBxoNZk). Es wurden nur
Titel/Metadaten gelesen, keine Videobilder analysiert, und **keine H3VR-Assets
übernommen**. Umgesetzt ist die Bedienmechanik, nicht H3VR-Geometrie.

## Was neu ist

`work/gquest-ui/lua/autorun/client/gquest_h3_manual.lua`
(im Paket `lua/autorun/client/gquest_h3_manual.lua`).

Die nativen HL2-/HLVR-Waffen behalten ihren echten Zustand (Clip, Reserve,
Magazin-Entity, Sound, Animation). Das Modul legt die H3VR-typische **manuelle
Bedienung** davor und liest sie aus der echten Pose der Zweithand
(`vr.GetHandPose`), nicht aus einer Taste:

1. **Magazin greifen und herausziehen.** Die Zweithand greift am Magazinschacht
   (Griffaktion gedrückt, Abstand ≤ `gquest_h3_grab_radius`) und zieht es nach
   unten weg (≥ `gquest_h3_mag_pull`). Das löst den nativen Auswurf aus –
   denselben `+eject`/`-eject`-Impuls, den das geprüfte Tasten-Nachladen
   (`gquest_reload.lua`) benutzt. Das Ziehen wird verriegelt, damit ein
   versehentliches Vorbeifahren kein Magazin verliert.
2. **Magazin einsetzen.** Kommt die Zweithand mit dem frischen Magazin zurück in
   den Schacht (≤ `gquest_h3_seat_radius`), wird eingesetzt und – wenn
   `gquest_h3_assisted 1` – aus dem **eigenen Vorrat** aufgefüllt
   (`gquest_reload_refill`). Es wird nie Munition erzeugt; die Grenze bleibt
   Reserve und Magazingröße. 0,35 s nach dem Auswurf ist der Schacht gesperrt,
   damit man nicht in derselben Bewegung wieder einsetzt.
3. **Durchladen.** Am Schlitten/Ladehebel greifen und nach hinten ziehen
   (≥ `gquest_h3_rack_pull`) gibt einen Rack-Klick; steht die Waffe danach leer,
   während Reserve vorhanden ist, füllt der Rack sie (H3VR-Schritt „laden“).

Jede Aktion hat einen Haptikimpuls auf der Zweithand (`vr.TriggerHaptic`, nur
wenn die Laufzeit die Aktion wirklich als aktiv meldet).

Greifaktion: die erste tatsächlich aktive der gelieferten Aktionen `grab`,
`grip`, `hand_grab`, `use`; ist keine digital aktiv, zählt ein echter
Hand-Curl (`hand_curl` ≥ 0,55) – beide sind in `libvrxr` vorhanden. Fehlt beides
im Lauf, passiert nichts; es wird keine Eingabe erfunden.

## Schalter und Kalibrierung

| ConVar | Standard | Bedeutung |
|---|---|---|
| `gquest_h3_manual` | 1 | Modul an/aus (0 = nur alter Tastenweg) |
| `gquest_h3_assisted` | 1 | Einsetzen/Racken füllt aus eigenem Vorrat |
| `gquest_h3_grab_radius` | 5.5 | Greifabstand zu Magazinschacht/Schlitten |
| `gquest_h3_seat_radius` | 2.5 | Abstand, ab dem das Magazin einsetzt |
| `gquest_h3_mag_pull` | 6 | Weg nach unten, der auswirft |
| `gquest_h3_rack_pull` | 4 | Weg nach hinten, der durchlädt |

Die Offsets je Waffenklasse (`weapon_pistol`, `weapon_357`, `weapon_smg1`,
`weapon_ar2`) stehen im Handrahmen der **Waffenhhand** (f = vorwärts, r = rechts,
u = oben) und sind Startwerte, keine Messung am Gerät. Deshalb:

```
gquest_h3_report                  # gemessene Handposition im Handrahmen + Abstand
gquest_h3_sample 5 2 apply        # 5 s warten, 2 s alle Bilder mitteln, anwenden+speichern
gquest_h3_offset 0.6 -1.2 -3.0    # Magazinschacht der gehaltenen Klasse setzen
gquest_h3_save                    # -> data/gquest/h3_manual.json
gquest_h3_reset                   # gespeicherte Werte der Klasse löschen
gquest_h3_status                  # Zustand, Schwellen, Offset, Clip/Reserve
```

`gquest_h3_sample` ist der praktische Weg: Befehl vom PC schicken, dann die
Zweithand in die Griffpose bringen und still halten. Ausgegeben werden Mittelwert
und Streuung über alle Bilder des Fensters; `spread` über ca. 0,5 Einheiten
bedeutet, dass die Hand nicht ruhig lag. Ohne `apply` wird nur der passende
`gquest_h3_offset`-Befehl vorgeschlagen.

Linkshänder werden gespiegelt: `vr.GetPrimaryHand()` bestimmt Waffen- und
Zweithand, der seitliche Offset wird entsprechend negiert.

## Abnahmetest am Gerät (woran ein stimmiger Offset erkennbar ist)

Alle Zahlen sind Source-Einheiten (1 ≈ 2,54 cm).

1. **Modul geladen:** `GQUEST_H3 ready:` steht im Log; sonst ist die Datei nicht
   im APK oder ein Lua-Fehler davor.
2. **Greifaktion aktiv:** `gquest_h3_report` mit der Hand in der Griffpose zeigt
   `grip=true`. `grip=false` bei gedrückter Hand heißt: auf diesem Gerät ist
   keine der gelieferten Greifaktionen aktiv – dann greift das Modul nicht.
3. **Messung ruhig:** `gquest_h3_sample 6 2` liefert `spread` ≤ 0,5 und bei 72 Hz
   etwa 144 `frames`. Größere Streuung = Hand nicht still, Messung wiederholen.
4. **Offset sitzt:** nach `apply` (oder `gquest_h3_offset` + `gquest_h3_save`)
   zeigt `gquest_h3_status` `distance` ≤ 1,5 mit der Hand in der Griffpose.
5. **Kein Fehlauslöser:** Hand entspannt neben dem Körper → `distance` > 5,5 und
   keine `GQUEST_H3 mag_out`-Zeile.
6. **Genau eine Aktion pro Geste:** Ziehen ≈ 7 Einheiten nach unten → genau eine
   `mag_out`-Zeile; Zurückführen in den Schacht → genau eine `mag_seated`-Zeile.
   Wird schon beim Greifen ausgeworfen, `gquest_h3_mag_pull` erhöhen oder den
   Well-Offset nachmessen.
7. **Munition bleibt erhalten:** nach dem Einsetzen zeigt `gquest_h3_status`
   `clip` = Magazingröße und `reserve` genau um die fehlenden Schuss kleiner.
8. **Neustart:** `files/garrysmod/data/gquest/h3_manual.json` enthält die Klasse,
   `gquest_h3_status` zeigt nach einem App-Neustart denselben `override`.

Wenn die native Engine dieselbe Ziehbewegung schon selbst auswertet, erscheint
der native Auswurf ohne `GQUEST_H3 mag_out`; dann nicht doppelt bedienen, sondern
`gquest_h3_manual 0` setzen und den nativen Weg weiterverfolgen.

## Was lokal geprüft ist

* `luac -p` (echtes Lua 5.1, selbst gebaut) über **alle** ausgelieferten
  Lua-Dateien: keine Syntaxfehler.
* `work/harness/test_h3_manual.lua` mit echtem Lua 5.1: Greifverriegelung ohne
  Auswurf, 4 vs. 7 Einheiten Ziehweg, genau ein Auswurf pro Geste, Freigabe des
  Impulses nach 0,18 s, Schachtsperre, genau ein Refill beim Einsetzen,
  Assisted-aus-Pfad, Rack lädt nur bei leerer Waffe, kein Doppel-Refill,
  Loslassen setzt Greifen/Racken zurück, Spiegelung für Linkshänder,
  Menü-/VR-/Modul-Gates, Verlust der Pose, Klassenwechsel, Kalibrierung und
  Datei-Roundtrip, Analog-Curl-Fallback. Alle Prüfungen bestehen.
* Bestehende Tests unverändert grün: `work/test_reload_client.lua`,
  `work/harness/gquest_wrist_hud_test.lua`,
  `work/harness/gquest_weapon_align_test.lua`,
  `work/harness/test_native_pose_class.lua`,
  `work/test_gquest_menu_navigation.lua`.

## Was ausdrücklich nicht geprüft ist

* Kein Gerätelauf: Haptik, tatsächliche Offsets im Headset, ob die gelieferte
  Greifaktion wirklich aktiv wird, und ob die native Engine parallel dieselbe
  Geste auslöst (dann doppelt auswerfen – mit `gquest_h3_manual 0` abschaltbar).
* Die natives Waffen behalten **keinen +1-Kammerzustand**: HL2-Clip1 ist die
  einzige Munitionswahrheit. Ein H3VR-„eine Kugel bleibt in der Kammer“ ist
  damit nicht abgebildet, und ein Schuss-Gate („erst durchladen“) ist für die
  nativen Waffen aus Lua nicht erzwingbar.
* Das Magazin selbst zeichnet weiter die Engine; das Modul erzeugt kein
  zusätzliches Magazinmodell im Handraum.
* Schrotflinte/Vorderschaft, Armbrust und RPG haben hier keine Magazingeste.

## Offene nächste Schritte (Gerät)

1. `gquest_h3_report` mit gehaltener Pistole/SMG aufrufen und die Zahlen mit
   den Klassen-Offsets vergleichen; mit `gquest_h3_offset` nachziehen, `save`.
2. Prüfen, ob der native Pfad dieselbe Geste schon auswertet (Log:
   `GQUEST_H3 mag_out` vs. zusätzlicher nativer Auswurf).
3. Erst danach Rack-/Vorderschaftgesten auf Schrotflinte ausdehnen.
