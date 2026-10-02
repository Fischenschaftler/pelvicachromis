# Prozedurale Wendebewegung

## Umfang

Manueller Stimulus, MOVE, TURN und MOVE_TO verwenden denselben erweiterten `stimulus_fish_controller.gd`. Es gibt keine separate Sequenz-Bewegungslogik. Die freie Viewer-Steuerung außerhalb des wissenschaftlichen Stimulus bleibt unverändert. Kamera, Präsentationsebene, konstante Root-Tiefe und kalibrierter Modellmaßstab bleiben erhalten.

GLB, Mesh, Blender-Dateien, 15-Bone-Rig, Rest Pose, UVs, Gewichte, importierte Animation und Texturen werden nicht geändert. Die zusätzliche Pose existiert nur während einer Stimulus-Sitzung. Neue Bewegungsparameter erweitern `config/stimulus.json`; Projekt- und Sequenzformat bleiben unverändert. Alte Konfigurationen ohne diese Felder verwenden die neuen Standardwerte, ohne beim Laden überschrieben zu werden.

## Animation plus additive Pose

Ein temporärer `SkeletonModifier3D` sitzt am bestehenden Skeleton. Godot wertet ihn nach der Animationspose aus und stellt die Basispose anschließend wieder her. Für jeden beteiligten Bone gilt:

`q_final = normalize(q_Swim_Test * q_Kurvenoffset)`

Die Offset-Achse wird aus der tatsächlichen globalen Bone-Restbasis und der anatomischen Hochachse abgeleitet. Beim GLB-Import entspricht Blender-Z dem Godot-Y. Dadurch wird nicht versehentlich um die Längsachse eines Bones gedreht. Es werden nur Pose-Rotationen gesetzt, keine Resttransformationen, Skalen, Translationen oder importierten Animationskeys.

Die Anwendung schreibt nicht bei jedem Frame erneut auf die zuvor veränderte Pose. Der Modifier erhält die frische Animationsbasis; es entsteht keine Aufsummierung. Pause hält die Kurvenamplitude und die Animationsphase. Beim Verlassen wird ausschließlich der eigene Modifier entfernt; Godots vorhandener PhysicalBoneSimulator bleibt erhalten. Die vorherige Viewer-Animation und Hierarchie werden wiederhergestellt.

## Verteilung entlang der Körperkette

Die tatsächlich überprüfte Kette lautet `Body_01 → Body_02 → Body_03 → Body_04 → Tail_01 → Tail_02 → Tail_Fin`. Die Werte werden auf ihre Summe normiert. Nachfolgende Bones erben die vorherigen Rotationen; die Gesamtkrümmung wächst deshalb bis zur Schwanzspitze.

| Bone | Gewicht | Maximaler zusätzlicher lokaler Winkel bei 0,95 rad Gesamtkrümmung |
| --- | ---: | ---: |
| Body_01 | 0,02 | 1,09° |
| Body_02 | 0,06 | 3,27° |
| Body_03 | 0,12 | 6,53° |
| Body_04 | 0,19 | 10,34° |
| Tail_01 | 0,24 | 13,06° |
| Tail_02 | 0,27 | 14,70° |
| Tail_Fin | 0,10 | 5,44° |

`Pectoral_Fin_Left_2` beziehungsweise `Pectoral_Fin_Right_2` erhalten abhängig vom Vorzeichen eine kleine zusätzliche Auslenkung bis 0,07 rad (etwa 4°). Rücken-, After- und Bauchflossen erhalten keine neue direkte Animation, sondern folgen ihrer bestehenden Hierarchie und Swim_Test.

## Drehrate und zeitlicher Verlauf

Die Kurvenamplitude folgt der tatsächlich integrierten Körper-Drehrate oder, wenn stärker, der tatsächlichen Änderung der Bewegungsrichtung. Sie wird nicht direkt aus einer Taste abgeleitet. Mit Geschwindigkeit `v` in cm/s:

`gain = 1 + turn_bend_speed_gain * clamp(v / max_speed_cm_s, 0, 1)`

`bend_target = clamp(-dominant_turn_rate * turn_bend_strength * gain, -max_turn_bend, max_turn_bend)`

Das negative Vorzeichen lässt den Schwanz der Kopfrotation nachlaufen. Positive Körperdrehrate bedeutet zunehmenden Yaw von Kopf rechts zu Kopf links; negative Rate den Rückweg. Die Angaben „links/rechts“ beziehen sich hier auf diese Ausrichtung, nicht auf den Beobachter vor einem gedrehten Monitor.

Die Amplitude nähert sich dem Ziel mit `1 - exp(-response * dt)`. Beim Aufbau gilt `turn_bend_response`, beim Abbau `turn_bend_recovery`. Es gibt keine Zufallswerte. Kleine numerische Restfehler unter einem Mikroradian in der Bewegungsrichtung werden ignoriert, damit beim Geradeausschwimmen keine künstliche Restkrümmung bleibt.

## Geschwindigkeit, Wenderadius und 180°-Wechsel

Die Bewegungsrichtung der Geschwindigkeit wird auf der **X/Y-Präsentationsebene** gedreht. Der minimale Bahnradius lautet:

`R_min(v) = minimum_turn_radius_cm + turn_radius_speed_factor * v²`

Standard: bei 3 cm/s mindestens 1,95 cm, bei 6 cm/s 3,30 cm, bei 10 cm/s 6,50 cm. Die Richtungsänderung ist durch `|omega_path| <= min(turn_speed, v / R_min)` begrenzt. Beim Abbremsen wird konservativ die höhere Geschwindigkeit des Integrationsschritts für die Radiusgrenze verwendet. Die Root-Tiefe bleibt exakt konstant.

Körper-Yaw und Bahnwinkel sind unterschiedliche Größen: Die bestehende Links-/Rechtsorientierung erfolgt um Y, der Bahnbogen liegt in X/Y. Für Körper-Yaw gibt es zusätzlich eine geschwindigkeitsabhängige Drehbegrenzung mit sanftem Beschleunigen/Bremsen. Im Stillstand bleibt eine stationäre TURN-Wende möglich; dort ist ein translatorischer Bahnradius nicht definiert. Vertikale Befehle behalten die seitliche Körperausrichtung des bisherigen Stimulus bei.

Bei einem bewegten 180°-Wechsel wird die Geschwindigkeit durch einen Bogen geführt, anstatt ihre Richtung sofort umzuschalten. Eine exakte 180°-Mehrdeutigkeit wird anhand der Yaw-Zielrichtung deterministisch aufgelöst. Der Antrieb ist reduziert, solange der Kopf der angeforderten Richtung noch entgegensteht (15–100 % abhängig vom Winkelfehler). Dadurch unterscheiden sich Solltempo und tatsächliches Tempo während des Wendens bewusst. Im Stillstand startet die Bewegungsrichtung aus dem neuen Kommando; die Körperorientierung und Kurvenpose bauen sich trotzdem weich auf.

**Folge für bestehende Versuche:** Bewegungswege, Ankunftszeiten und Auslenkungen können sich gegenüber der alten Steuerung ändern. Insbesondere braucht MOVE_TO gegebenenfalls mehr Zeit. Die bestehende Vorprüfung simuliert dieselbe neue Bewegung und weist nicht rechtzeitig erreichbare Ziele beziehungsweise Bildschirmüberschreitungen ab. Alte Logs bleiben interpretierbar; neue Logs enthalten alle verwendeten Konfigurationswerte. Ein auslaufendes HOLD stoppt wie bisher die Translation sofort, TURN bleibt stationär.

## Einstellbare Parameter

In der portablen `config/stimulus.json` können ergänzt beziehungsweise verändert werden:

```json
"turn_bend_strength": 0.6,
"turn_bend_response": 6.0,
"turn_bend_recovery": 4.0,
"max_turn_bend": 0.95,
"minimum_turn_radius_cm": 1.5,
"turn_radius_speed_factor": 0.05,
"turn_bend_speed_gain": 0.25,
"pectoral_turn_strength": 0.07,
"body_bend_weights": {
  "Body_01": 0.02, "Body_02": 0.06, "Body_03": 0.12,
  "Body_04": 0.19, "Tail_01": 0.24, "Tail_02": 0.27, "Tail_Fin": 0.10
}
```

Winkel sind Radiant, Drehraten rad/s, Reaktionsraten 1/s, Radius cm. `turn_bend_strength` hat die Dimension Sekunden, `turn_radius_speed_factor` s²/cm. Gesamtkrümmung wird auf höchstens 1,2 rad konfigurierbar begrenzt, Brustflossenoffset auf 0,2 rad. Stärke/Geschwindigkeitseinfluss/Brustflossenreaktion können für Kontrollbedingungen auf null gesetzt werden. Gewichte müssen vollständig, endlich, nichtnegativ und in Summe positiv sein. Die vorhandenen `turn_speed` und `turn_acceleration` gelten weiter.

## Logging und Reproduzierbarkeit

Neue Zustandsfelder: `target_turn_rate`, `actual_turn_rate`, `path_turn_rate`, `turn_bend_amount`, `turn_direction`, `minimum_turn_radius_cm`, `current_turn_radius_cm` und `turn_peak_bend`. Gerade Bewegung hat keinen endlichen aktuellen Kurvenradius: JSON `null`. Bei Pause sind die im Sequenz-Telemetriesatz gemeldeten tatsächlichen Drehraten null; die Pose bleibt eingefroren. Manuelle Logs enthalten die Felder im `state`, Sequenzlogs zusätzlich auf oberster Ebene.

Ereignisse `TURN_STARTED`, `TURN_COMPLETED` und bei Sitzungsende/Abbruch `TURN_INTERRUPTED` dokumentieren Ziel-/Istwinkel, Richtung beziehungsweise erreichte maximale Krümmung. TURN_COMPLETED folgt erst nach weitgehendem Abbau der zusätzlichen Pose. Sehr kurze Pausen zwischen entgegengesetzten Kurven können zu einem zusammenhängenden Wendemanöver gehören; dessen vorzeichenbehafteter Verlauf bleibt in den Zustandsproben sichtbar.

Sequenzen verwenden weiterhin die monotone Uhr und den festen 1/240-s-Integrator. Manuelle Steuerung benutzt weiterhin den festen Physics-Takt. Der Modifier integriert keine Zeit selbst, sondern verwendet nur den berechneten Zustand. Dadurch hängt die Pose nicht von der Anzahl der Renderaufrufe ab. Gleiche Ausgangsdaten und Integrationsschritte liefern gleiche Offsets.

`scripts/stimulus/run_turning_validation.gd` prüft Aufbau/Abbau, linke/rechte Kurven, Radiusgrenze, 180°-Wechsel, Konfigurationsvalidierung, Kombination mit Swim_Test, unveränderte Rest Pose/Skalierung und vollständige Bereinigung. Drei Läufe einer identischen MOVE/TURN/MOVE_TO-Sequenz mit verschiedenen Renderintervallen vergleichen sämtliche protokollierten Offsets, Winkel, Radien, Zeitpunkte und Positionen. Ergebnisse und Diagnosebilder: `godot/diagnostics/turning_*`.

Die Diagnosebilder sind Entwicklungsaufnahmen; keine Beschriftung wird im echten Stimulusfenster eingeblendet. Die Lösung ist ein kontrollierter anatomischer Näherungsansatz, keine hydrodynamische Simulation. In strenger Seitenansicht erscheint eine seitliche Körperbiegung perspektivisch schwächer als während einer Wende. Hautlängen und Volumen werden nicht nachträglich korrigiert; der bestehende Skinning-Algorithmus bleibt unverändert. Kalibrierung bezieht sich weiterhin auf die unverformte Gesamtlänge; deren projizierte Silhouette verkürzt sich beim Wenden erwartungsgemäß.

## Abnahme am 02.10.2026

Godot 4.7.2 / Windows / RTX 3070: 1.287 Prüfungen bestanden, jeweils im Entwicklungsprojekt, im exportierten Diagnosebuild und nach Kopieren in einen umbenannten Ordner. Die drei Reproduzierbarkeitsläufe stimmen exakt überein. Zusätzlich bestanden die fünf Regressionstests für freie Fischsteuerung, portable Speicherung einschließlich Fotoanalyse, Fotoimport, Projektverwaltung und Atlas-/Texturumschaltung. Der produktive Windows-Build wurde neu exportiert, gestartet und als portable ZIP verpackt. Keine Laufzeitfehler in diesen Läufen.

18 geschützte Dateien wurden per SHA-256 geprüft und blieben unverändert. Native Fenster-/Fokusprüfungen liefen auf einem physischen Monitor; ein echter Zweimonitor-Aufbau wurde nicht geprüft. Diagnoseberichte liegen unter `godot/diagnostics/turning_*validation.json` und `turning_regressions.json`.
