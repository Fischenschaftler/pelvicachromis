# Manuelle Fischsteuerung

Der Button **Fisch steuern** wechselt von BETRACHTEN zu STEUERN. **Steuerung
beenden** oder Esc kehrt zur Seitenansicht und Foto-/Projektbearbeitung zurück.
Das aktuell dargestellte, individuell texturierte GLB wird verwendet. Material-
Instanzen und Projektzustand bleiben beim Moduswechsel bestehen. Während einer
Foto-Berechnung oder eines geöffneten Dialogs wird der Wechsel nicht ausgeführt.

## Bedienung

| Eingabe | Wirkung |
| --- | --- |
| W | Beschleunigen bis zur normalen Schwimmgeschwindigkeit |
| S | Bremsen; hat Vorrang vor W |
| A / D | Weich nach links / rechts drehen |
| Q / E | Tiefer / höher schwimmen |
| Shift + W | Beschleunigen bis zur schnellen Geschwindigkeit |
| Linke Maustaste halten, bewegen | Verfolgerkamera um den Fisch drehen |
| Mausrad | Kameraabstand ändern |
| Ansicht zurücksetzen | Nur die Kamera zurücksetzen |
| Esc / Steuerung beenden | Neutralen Fisch und Betrachtungsmodus wiederherstellen |

Foto- und Projektbearbeitung werden im Steuerungsmodus ausgeblendet. Es werden
keine Arbeitsdaten dabei verworfen. Die Animation läuft im Steuerungsmodus immer;
der bisherige Start/Stopp-Button zeigt deshalb „Schwimmtempo automatisch“.
Beim Beenden wird auch ein vorher pausierter Animationszustand wiederhergestellt.

## Bewegungsmodell und Achsen

Der importierte Fisch hat **lokal +X vorwärts, +Y oben, Z als Körperbreite**.
Dies wurde an Mund-/Augenpositionen im Vergleich zur Schwanzflosse geprüft.
Die Blender-Achsen werden beim glTF-Import entsprechend umgewandelt.

`FishMotion` ist ein neuer Node3D über der unveränderten GLB-Instanz. Der
Controller verändert ausschließlich diesen übergeordneten Transform und das
AnimationPlayer-Abspieltempo. Er setzt weder Bone-Posen noch Vertexdaten.

Alle neuen Bewegungs- und Kameraparameter liegen in
`scripts/fish/fish_movement_config.gd`. Standardwerte in Metern und Sekunden:

| Größe | Wert |
| --- | --- |
| Schweben | 0 m/s, Animation läuft langsam weiter |
| Normales Schwimmen | 0,04 m/s (etwa eine halbe Fischlänge pro Sekunde) |
| Schnelles Schwimmen | 0,10 m/s |
| Beschleunigung | 0,035 m/s² |
| Nachgleiten / Bremsen | 0,014 / 0,09 m/s² |
| Maximale Drehgeschwindigkeit | 1 rad/s |
| Drehbeschleunigung / Abbremsen | 1,2 / 1,8 rad/s² |
| Vertikale Geschwindigkeit | ±0,025 m/s |
| Vertikale Beschleunigung / Dämpfung | 0,035 / 0,05 m/s² |
| Maximale Körperneigung / Rollen | ±20° / ±6° |

Die Physikschritte nähern Geschwindigkeit, Dreh- und Vertikalgeschwindigkeit
begrenzt an die Sollwerte an. Auch die kombinierte Vorwärts-/Höhenbewegung bleibt auf maximal 0,10 m/s
begrenzt. Nach Loslassen von W gleitet der Fisch aus. Die
Vorwärtsrichtung folgt dem lokalen +X im aktuellen Gierwinkel; Steigen/Sinken
wird zusätzlich vertikal gesteuert. Pitch stellt diese Höhenbewegung optisch dar
und ist begrenzt, damit vertikale Bewegung nicht doppelt gezählt wird. Leichtes
Rollen folgt der Drehgeschwindigkeit. Neigung und Rollen werden exponentiell
geglättet. Fenster-Fokusverlust unterdrückt Bewegungseingaben und Kameradrags.

## Swim_Test

Die originale Loop-Animation bleibt unverändert. AnimationPlayer.speed_scale
folgt geglättet dem Betrag der tatsächlichen Geschwindigkeit einschließlich
Höhenbewegung: 0,18 im Stillstand, 1,0 bei normaler Fahrt, bis 1,9 bei schneller
Fahrt. Der Übergang verwendet exponentielle Dämpfung; die Animationsphase wird
beim Beschleunigen nicht neu gestartet. Die vorhandene Körper-/Flossenbewegung
bleibt damit auch beim Schweben erhalten. Eine kleinere Animationsamplitude oder
kurvenspezifische Körperbiegung wird noch nicht erzeugt.

## Kamera und Reset

Eine eigene Perspective-Camera3D folgt unabhängig vom Fischknoten. Position,
Blickziel und Blickrotation werden gedämpft. Standard: hinter dem Fisch in einem
Winkel von 35° seitlich und 18° oberhalb. Der Standardabstand wird aus den
Modellabmessungen, FOV und dem aktuellen Fensterformat berechnet. Grenzen:
1,8 bis 12 Modellradien und -15° bis +65° vertikale Kameraneigung.

`viewer.reset_fish_control()` setzt Position, Rotation, Vorwärts-, Vertikal- und
Drehgeschwindigkeit, Eingaben, Kamera und Animationstempo zurück. Der UI-Button
**Ansicht zurücksetzen** bewegt hingegen ausschließlich die Kamera. Bei jedem
Eintritt beginnt der Fisch neutral; der Modus wird nicht in project.json gespeichert.

## Input, Gamepad und Aquarium

Input Actions: fish_forward, fish_brake, fish_turn_left, fish_turn_right,
fish_up, fish_down, fish_boost, fish_control_exit. Physische Tastenzuordnung in
project.godot. `set_movement_input()` akzeptiert analoge Werte 0…1 für Vorwärts,
Bremse und Boost sowie -1…1 für Drehen und Höhe; Gamepad-Achsen können später in
der Input Map ergänzt werden. Noch keine Gamepad-Oberfläche.

`apply_displacement()` kapselt die Positionsänderung für spätere Aquariumgrenzen
oder eine Kollisionsprüfung. Aktuell freier Raum ohne Wände, Hindernisse oder
Wasserphysik. Wegen des neutralen Hintergrunds fehlen feste räumliche Bezugspunkte.

## Prüfungen und portable Version

```powershell
& $Godot --path . --script res://scripts/fish/validate_fish_control.gd
& $Godot --path . --script res://scripts/storage/validate_portable_storage.gd
```

Der Steuerungstest prüft beide Modi, analoge Bewegung, sanfte Übergänge,
Geschwindigkeitsgrenzen, Kamera/Zoom/Reset, Input Map, Texturerhalt, Projektwechsel,
Animation und kleine Fenster. Der portable Workflow prüft zusätzlich den Übergang
von einer tatsächlich aus dem Foto erzeugten Textur zur Steuerung und zurück.
Diagnosen: godot/diagnostics/fish_control_validation.json und
fish_control_idle/forward/turn/chase_camera.png.

Die drei neuen Runtime-Skripte sind ausdrücklich im Preset **Windows Portable**
enthalten. Keine zusätzlichen Laufzeitabhängigkeiten oder Projektdatenfelder.
Die bestehenden Windows-/Grafiktreiber-Anforderungen bleiben bestehen.

## Ergebnis dieses Schrittes

Bestanden: Steuerungstest ohne Grafik und mit realem GPU-Viewport, Fotoimport,
automatische Analyse mit manuellen Korrekturen und tatsächlicher Foto-Texturierung,
Atlas-Regression, Projektverwaltung sowie portable Speicherung einschließlich
Umzug des gespeicherten Projekts. Alle zwölf aus dem Foto erzeugten Punkte und
seine Textur bleiben beim Steuern erhalten. Testfehler und Godot-Fehlerlogs leer.

Zusätzlich wurde ein separater Windows-Release-Diagnosebuild mit derselben
Produkt-Hauptszene und einer eingebetteten Testszene ausgeführt: gespeichertes
Fotoprojekt öffnen, Steuern, Vorwärts/Drehen/Steigen/Boost, Animationstempo,
Verfolgerkamera-Zoom, Reset und Rückkehr zur Bearbeitung bestanden. Die finale
EXE enthält diese Testszene nicht und wurde ebenfalls fehlerfrei gestartet.
Kein manueller UI-Abnahmetest auf einem zweiten Rechner.

Die aktuelle portable EXE und ZIP stehen unter dist/PelvicachromisStudio/ und
dist/PelvicachromisStudio_Windows_Portable.zip. Diagnosebuilds und Build-Artefakte
werden nicht in Git aufgenommen. Frühere Größen/Hashes in PORTABLE_WINDOWS.md
beziehen sich auf den dort beschriebenen ersten Build.
