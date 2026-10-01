# Reproduzierbare Stimulus-Sequenzen

## Bedienung

Ein gespeichertes Fischprojekt öffnen und dessen Original- oder generierte Färbung auswählen. F10 bleibt die bestehende Bildschirmkalibrierung, F9 der manuelle Stimulusmodus. **F11** öffnet den Sequenzeditor außerhalb des Stimulusbildes.

Der Editor bietet Neu, Laden, Speichern, Duplizieren, Name, Beschreibung und Notizen. Die Schritttabelle lässt sich ergänzen, bearbeiten, umordnen und kürzen. Die Gesamtdauer wird aus allen Schritten berechnet. Bei kleinen Fenstern ist die Oberfläche scrollbar. Vor dem Start werden Fischprojekt, Fischlänge, Kalibrierungsprofil, Hintergrund und Dauer angezeigt; Versuchs-ID ist für echte Versuche Pflicht, Versuchstier-ID optional. Fischgröße und Monitorprofil werden weiterhin über die bestehende Kalibrierung eingestellt.

Die Vorschau benötigt keine Versuchs-ID und ist sichtbar als PREVIEW markiert. Echte Versuche zeigen ausschließlich Fisch und Hintergrund, ohne Mauszeiger, Editor oder Statusanzeigen. `sequence_progress()` stellt den aktuellen Zustand für eine spätere Experimentatoranzeige bereit; ein separates Experimentatorfenster ist noch nicht implementiert.

Leertaste pausiert beziehungsweise setzt fort, Esc beendet kontrolliert. Bei gesperrtem Manual Override werden Bewegungsbefehle und F8 ignoriert. Bei erlaubtem Override gelten die bisherigen Stimulus-Tasten; Eingriffe einschließlich F8 werden protokolliert. Der Zeitplan läuft während eines Eingriffs weiter. Solche Versuche sind daher nicht mit unbeeinflussten Wiederholungen gleichzusetzen.

## Portable Speicherung und Format

Sequenzen stehen als lesbare JSON-Dateien unter `data/sequences/<sequence_id>.json`, relativ zum portablen Programmordner. Beim ersten Öffnen werden die drei mitgelieferten Beispiele angelegt, vorhandene Dateien nicht überschrieben. Sequenzen enthalten keine Fischdaten. Duplizieren vergibt eine neue Kennung. Das aktuelle Fischprojekt und die aktive Laufzeitfärbung werden erst beim Start kombiniert; Mesh, Materialien aus dem Import und Projektdateien werden dabei nicht verändert.

Formatversion 1 enthält `sequence_format_version`, `sequence_id`, `sequence_name`, `created_at`, `updated_at`, `description`, `notes`, `initial_state`, `steps` und `total_duration_s`. Zeitstempel sind UTC. `initial_state` enthält `start_mode` (CENTER, LEFT, RIGHT, CUSTOM), `position_cm` und `orientation` (LEFT oder RIGHT). Jeder Schritt enthält:

```json
{
  "step_type": "MOVE",
  "duration_s": 10,
  "target_speed_cm_s": 3,
  "direction": "RIGHT",
  "comment": "Langsame Passage"
}
```

Optional sind `orientation`, `start_position_cm` und `target_position_cm`. Eine Startposition ist beim ersten Schritt oder RESET_POSITION zulässig, ein Ziel nur bei MOVE_TO. Nichtbewegungsschritte verwenden Richtung NONE und Geschwindigkeit 0. Grenzen: 500 Schritte, insgesamt höchstens 3600 Sekunden, JSON höchstens 1 MiB. Nullsekunden sind für einzelne Schritte erlaubt; die Gesamtdauer muss positiv sein. Dateinamen und Kennungen werden validiert.

## Koordinaten, Geschwindigkeit und Grenzen

Bildschirmmitte ist (0, 0) cm. Positive X-Werte zeigen nach rechts, positive Y-Werte nach oben. Die bestehenden Kalibrierungsfunktionen und `units_per_cm` rechnen in die Godot-Präsentationsebene um. Geschwindigkeit wird ausschließlich in cm/s konfiguriert. Beschleunigung, Verzögerung und kontrollierte Drehung stammen aus dem bestehenden Stimuluscontroller. Die Animation folgt der tatsächlichen Geschwindigkeit.

CENTER liegt in der Mitte, LEFT/RIGHT am jeweiligen sicheren Rand, CUSTOM bei den angegebenen cm-Koordinaten. Die Vorprüfung berechnet den vollständigen Bewegungsverlauf mit demselben Integrator wie die Wiedergabe. Auf jeder Achse bleibt ein konservativer Rand von halber Fischlänge plus 0,2 cm frei. Dadurch bleibt auch beim Drehen Platz. Numerische Grenztoleranz: 0,001 cm. Ungültige oder den sichtbaren Bereich verlassende Abläufe werden vor Speichern und Start abgewiesen. Es gibt keine automatische Tempo- oder Wegskalierung. Während der Wiedergabe führen Grenzverletzungen ebenfalls zum Abbruch.

## Schritttypen

| Typ | Verhalten |
| --- | --- |
| WAIT | Kein aktiver Antrieb; bestehende Geschwindigkeit wird kontrolliert abgebremst. |
| MOVE | Bewegung LEFT/RIGHT/UP/DOWN mit vorgegebener Geschwindigkeit und bestehender Beschleunigung. |
| TURN | Stationäre kontrollierte Drehung zur angegebenen Orientierung. |
| MOVE_TO | Bewegung zum cm-Ziel, mit begrenzter Geschwindigkeit und Abbremsen; hält nach Erreichen. Die Vorprüfung verlangt Zielerreichung innerhalb der Dauer, Toleranz 0,01 cm. |
| HOLD | Position halten; setzt Geschwindigkeit beim Eintritt auf null. Optional kontrolliert ausrichten. |
| RESET_POSITION | Explizit zur angegebenen Startposition springen, Geschwindigkeit null; optionale Orientierung sofort setzen. Für Abschnittsgrenzen, nicht als natürliche Bewegung gedacht. |

HOLD und TURN stoppen somit unmittelbar am Schrittanfang. Für ein weiches Auslaufen vorher WAIT verwenden. Richtungswechsel während MOVE verwenden die vorhandene Drehung, kein Spiegeln des Modells. Bei kurzen TURN-Schritten kann die Drehung noch nicht abgeschlossen sein; die tatsächliche Orientierung ist im Log nachvollziehbar.

## Zeitbasis und Reproduzierbarkeit

Start setzt Position, Orientierung, Geschwindigkeit null und Animationsphase null. Eine tiefe, schreibgeschützte Kopie der Definition schützt die laufende Sequenz vor Editoränderungen. Eine monotone Uhr bestimmt die verstrichene Zeit; physikalische Integration erfolgt in festen Schritten von 1/240 Sekunde, zusätzlich exakt an Sequenzgrenzen geteilt. Renderframes bestimmen nicht die Anzahl der simulierten Schritte. Nicht vollständige Zeitschritte werden bis zum nächsten Frame aufbewahrt. Die Integrationsquantisierung beträgt höchstens etwa 4,167 ms; sichtbare Darstellung erfolgt erst beim nächsten tatsächlich ausgegebenen Frame.

Pause stoppt Sequenzzeit, Bewegung und Animationsphase. Zeitstempel im Log bleiben reale Zeitstempel. Mehr als 250 ms ohne Aktualisierung außerhalb einer Pause führen zu `timing_overrun` und kontrolliertem Abbruch. Dies verhindert stillschweigend übersprungene Präsentationsabschnitte. Monitor-/Fensteränderungen und die bestehenden Fokusregeln bleiben wirksam.

Drei automatisierte Durchläufe derselben 5,8-s-Sequenz mit allen Schritttypen wurden mit 30-Hz-Intervallen sowie wechselnden Intervallen (1/144 s, 19 ms, 6 ms, 40 ms) verglichen. Schrittstart/-ende, Sollzustände und Endposition waren identisch: **0 s Zeitabweichung, 0 cm Endpositionsabweichung** auf diesem Rechner. Prüfgrenze für Endposition: 0,000001 cm. Bericht: `godot/diagnostics/sequence_reproducibility.json`.

Dies ist deterministische Softwareintegration, keine extern gemessene Display-Synchronisation. VSync, Grafiktreiber, Panel-Latenz und unterschiedliche Rechner können sichtbare Präsentationszeiten beeinflussen. Keine bitweise plattformübergreifende Garantie, keine zufällige Bewegungsvariation. Sehr lange Sequenzen können während der synchronen Vorprüfung kurz Wartezeit verursachen.

## Versuchslog

Echte Sitzungen: `data/experiments/`. Vorschauen: `data/experiments/previews/`. Die bestehenden JSONL-Protokolle enthalten eine eingebettete vollständige Definition, Formatversion und kanonischen SHA-256-Hash. Eine spätere Änderung der Sequenzdatei verändert alte Protokolle nicht.

Jeder Datensatz enthält Sequenzkennung, Namen, Hash, Schrittindex (nullbasiert), Typ, Sequenzzeit, Restzeit, Soll-/Istposition in cm, Soll-/Istgeschwindigkeit in cm/s, Soll-/Istorientierung in Radiant, Animationsrate, Steuerzustand, aktives Fischprojekt, Fischlänge, Kalibrierungsprofil sowie Versuchs-/Tierkennung und Preview-Kennzeichnung. Zusätzliche Zustandsdaten und reale Zeitstempel bleiben erhalten. `command_speed_cm_s` bezeichnet den effektiv angeforderten Wert, beispielsweise beim Bremsen vor MOVE_TO.

Bei MOVE ist die Sollposition die ideale Bahn mit konstanter Nenngeschwindigkeit ab Schritteintritt; die Istposition kann durch Beschleunigung zurückliegen. Bei MOVE_TO ist sie das Ziel, sonst die Position bei Schritteintritt. Das Log unterscheidet diesen Sollwert ausdrücklich vom erreichten Zustand. Während Pause sind Istgeschwindigkeit und Animationsrate im Log null.

Ereignisse: SESSION_STARTED, STEP_STARTED, STEP_COMPLETED, SESSION_COMPLETED, SESSION_ABORTED, PAUSED, RESUMED, MANUAL_OVERRIDE und CALIBRATION_WARNING. Dazu kommen periodische Zustandsproben gemäß bestehender `log_hz`-Konfiguration. Manual Override protokolliert Befehlsänderungen und Zustandsproben der resultierenden Bewegung. Schreibfehler beenden den Versuch kontrolliert.

## Beispiele und Tests

- Stationär: HOLD 30 s, CENTER.
- Horizontal langsam: HOLD 5 s, MOVE RIGHT 10 s mit 3 cm/s, HOLD 5 s, MOVE LEFT 10 s mit 3 cm/s, Start LEFT.
- Horizontal schnell: gleicher Ablauf mit 6 cm/s. Benötigt ausreichend breiten kalibrierten Bildschirm und wird auf schmalen Monitoren abgewiesen.

Validierung: `godot --path . --script res://scripts/sequences/run_sequence_validation.gd`. Ohne `--headless` werden zusätzlich Editor, echte Präsentation, Vorschau, individuelle Färbung, Animation, Logging, Kalibrierung und bisheriger Stimulusmodus geprüft. Die reine Ablaufprüfung ist auch headless verfügbar. Synthetische Kalibrierungen sind ausschließlich Testfixtures; produktive Kalibrierungsdateien werden nicht verändert.

Zusätzliche Regressionen prüfen freie Fischsteuerung, Fotoimport, automatische Analyse, Landmarks, Masken, Textur-/Atlasumschaltung, Projektverwaltung und portable Speicherung. Releaseprüfungen verwenden eine separate Test-EXE mit derselben Releasevorlage; die Distribution startet weiterhin die normale Hauptszene. Geschützte Modell-, Kalibrierungs-, Analyse-, Projektformat- und Speicherdaten werden per Hash beziehungsweise Git-Vergleich kontrolliert.
