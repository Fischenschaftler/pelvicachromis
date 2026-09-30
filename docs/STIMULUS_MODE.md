# Wissenschaftlicher Stimulusmodus

Zusätzliche Präsentationsansicht für Verhaltensversuche mit einem realen Fisch vor einem Monitor. Die bestehende Foto-, Projekt- und Texturverarbeitung bleibt im normalen Viewer. Der Stimulus zeigt ausschließlich Fisch und neutralen Hintergrund, ohne UI oder Mauszeiger.

## Start und Steuerung

Zuerst das gewünschte Fischprojekt öffnen, die gewünschte Original-/generierte Färbung wählen und **F9** drücken. Während Fotoanalyse, Texturerzeugung oder eines offenen Fotodialogs ist der Einstieg gesperrt. Die bisherige freie Fischsteuerung wird beim Einstieg beendet.

| Taste | Funktion |
|---|---|
| F9 | Versuch aus dem Viewer starten |
| W / S | Bildschirm auf / ab |
| A / D | Bildschirm links / rechts |
| R / F, halten | Sollgeschwindigkeit erhöhen / reduzieren |
| Q / E | Nach links / rechts ausrichten |
| F8 | Definierte Anfangslage, Tempo und Animationsphase zurücksetzen; Ereignis protokollieren |
| Esc | Versuch beenden und zum Viewer zurückkehren |

Loslassen bremst weich bis zum Stillstand. Diagonalbewegung überschreitet das Geschwindigkeitslimit nicht. Horizontale Bewegung wählt automatisch die passende Seitenorientierung; Q/E haben Vorrang. Eine Umkehr dreht sanft um die vertikale Y-Achse zwischen 0 und PI. Dabei wird der Fisch kurz kantennah sichtbar, bleibt aber ohne weiteren Befehl nicht frontal stehen. Es gibt keine automatische Bildschirmbegrenzung: ein Fisch kann den Bildausschnitt verlassen. F8 setzt ihn zurück.

## Szene, Kamera und Koordinaten

`scenes/StimulusMode.tscn` besitzt einen eigenen 3D-Viewport, konstante Beleuchtung und eine orthografische Camera3D mit KEEP_HEIGHT. Die Kamera blickt entlang -Z auf die **X/Y-Ebene**. +X ist rechts, +Y oben, die Position des Fischzentrums bleibt auf `plane_depth` in Z. Das Modell darf bei Drehung/Schwimmanimation räumlich ausgedehnt sein; die Translation bleibt eben.

Kameratransform und Projektionsgröße werden einmal beim Start gesetzt. Es gibt weder Orbit, Zoom noch Verfolgung. Mausereignisse werden abgefangen. Vollbild wird vor Beginn eingestellt. Eine spätere Fenstergrößenänderung beendet den Lauf, statt die Projektion unbemerkt zu ändern. Fokusverlust beendet ihn standardmäßig ebenfalls. Vollbild, Fensterposition/-größe, Mausmodus und vorheriger Animationszustand werden beim Stoppen wiederhergestellt.

Der tatsächliche importierte Fisch wird nur vorübergehend umgehängt. Meshes, Materialien einschließlich der individuellen Runtime-Fototextur, Skeleton, 15 Bones, UVs und Animation bleiben dieselben Instanzen. Ein übergeordneter Knoten übernimmt die Darstellungsgröße; die Modellgeometrie wird nicht verändert. Originalhierarchie und Transformation werden anschließend wiederhergestellt.

## Reproduzierbare Konfiguration

Beim ersten regulären Start entsteht `config/stimulus.json` neben der portablen EXE. Im Editor liegt sie unter `dev_portable_data/config/`. Vor dem nächsten Versuch editieren; jeder Lauf liest und kopiert die Einstellungen neu. Ungültige Felder/Werte verhindern den Start.

Die Defaults stehen zentral in `scripts/stimulus/stimulus_config.gd`:

- `background_color`: RGB [0.12, 0.12, 0.12], alternativ [0,0,0] oder [1,1,1].
- `fish_display_length`: 8 nominale cm; `units_per_cm`: 0.01; `view_height`: 0.24 Godot-Einheiten.
- `plane_depth`: 0; `camera_distance`: 1.
- `stimulus_speed`: 0.04; `min_speed`: 0.01; `max_speed`: 0.10 Godot-Einheiten/s.
- `speed_adjustment`: 0.025 Einheiten/s pro Sekunde Tastendruck.
- `acceleration`: 0.035; `deceleration`: 0.05 Einheiten/s².
- `turn_speed`: PI rad/s; `turn_acceleration`: 6 rad/s².
- `idle_animation_speed`: 0.18; `swim_animation_speed`: 1; `fast_animation_speed`: 1.9; `animation_response`: 3 pro Sekunde.
- `log_hz`: 20; `flush_interval`: 0.5 s; `fullscreen`: true; `stop_on_focus_loss`: true.

**Noch nicht physikalisch kalibriert.** Die Körperlänge meint die X-Ausdehnung von Fish_Body, ohne Schwanzflosse. Der Skalierungsfaktor ist `fish_display_length * units_per_cm / native_body_length`. Orthografische Pixel pro Einheit ergeben sich aus Viewporthöhe / view_height. Die reale Monitorgröße, DPI/OS-Skalierung und Pixel/cm müssen im nächsten Schritt kalibriert werden. Eine Einstellung von 8 bedeutet aktuell ausdrücklich nicht nachgewiesene 8 cm auf dem Bildschirm. Geschwindigkeiten bleiben Godot-Einheiten/s, nicht validierte cm/s.

Swim_Test wird unverändert geloopt. Seine Abspielrate wird weich an den Betrag der tatsächlichen X/Y-Geschwindigkeit gekoppelt. Stillstand behält eine kleine Restbewegung, die nominelle Geschwindigkeit verwendet Rate 1, die Höchstgeschwindigkeit Rate 1.9.

## Versuchsprotokolle und APIs

`data/experiments/<Zeitstempel>_<Zufallskennung>.jsonl`, neben der EXE; Editor: `dev_portable_data/data/experiments/`. Keine Versuchspositionen oder -geschwindigkeiten gelangen in `project.json`.

Jede Zeile enthält Ereignistyp, monotone Zeit seit Beginn, Simulationszeit, Zustand und Steuerbefehl. Zustand: Position XYZ, Orientierung Y in rad, Zielorientierung, Geschwindigkeit XY, Betrag, Sollgeschwindigkeit, Animationsrate. Startdatensatz: Konfigurationskopie, Projektkennung/-name, Färbungsmodus, bei generierter Textur deren SHA256, Viewportauflösung, Kameraposition, Projektion, Physiktaktrate und `calibrated: false`.

Ereignisse: Start/Anfangszustand, periodische Stichproben, Befehlsänderung, Reset, Stop mit Grund (Bedienung, Escape, Fenstergröße, Fokusverlust, Schließen oder Schreibfehler). Reset startet die Versuchszeit nicht neu. Ereignisse werden sofort, Stichproben periodisch auf Datenträger geflusht. Schreibfehler verhindern/beenden die Präsentation; nach der Rückkehr erscheint eine Fehlermeldung. Ein Prozessabsturz kann trotzdem einen unvollständigen Lauf hinterlassen. Zeitstempel sind Softwarezeiten, keine Messung der tatsächlichen Monitor-Ausgabezeit.

- `fish_viewer.start_stimulus_session(config_override)` / `stop_stimulus_session()` / `reset_stimulus()` bilden den Viewer-Einstieg.
- `stimulus_controller.gd` verwaltet Szene, Sitzung, Eingabe, Lebenszyklus und Wiederherstellung.
- `stimulus_fish_controller.gd` berechnet ausschließlich Bewegung und Animationsrate.
- `stimulus_log.gd` schreibt das Protokoll.
- Für künftige automatische Sequenzen oder eine getrennte Experimentatoroberfläche: `sample_input=false`, dann `set_command({x, y, speed, facing})`, Werte -1..1. Die Präsentationsszene benötigt dafür keine Widgets. Ablaufplanung und zweites Fenster sind noch nicht implementiert.

## Validierung

`scripts/stimulus/validate_stimulus.gd` ist ein Test-Node, kein Bestandteil des regulären Exports. Er prüft Start/Stop, Kamera, beide Bewegungsachsen, Beschleunigung/Bremsen/Limit, Orientierung, Swim_Test, Materialidentität, 15 Bones, Reset, Log-Inhalte, unveränderte Projekte, Projektwechsel, Vollbild und Rückkehr. Headless überspringt ausschließlich grafikspezifische Prüfungen. Zusätzlich laufen die vorhandenen Fotoanalyse-, Import-, Atlas-, Projekt-, Portabilitäts- und freien Steuerungstests.

Die grafischen Diagnosen liegen unter `godot/diagnostics/stimulus_*.png`. Eine separat exportierte Testszene prüft dieselben Abläufe mit dem Windows-Release-Template; der normale Build enthält diese Testszene nicht.

Aufruf im Repository: `Godot --path . --script res://scripts/stimulus/run_stimulus_validation.gd` (für reine technische Prüfung zusätzlich `--headless`). Der Test benötigt das vorhandene Beispielprojekt unter `dist/PelvicachromisStudio/projects/`; Schreibtests verwenden einen separaten Testordner.
