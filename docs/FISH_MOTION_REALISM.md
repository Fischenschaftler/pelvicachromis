# Pitch, Kiemendeckel und Boost

## Bedienung

Im wissenschaftlichen Stimulusmodus: **Bild↑** hebt die Schnauze, **Bild↓** senkt sie. Q/E bleiben für die vorhandene Wende reserviert. **Shift** aktiviert den Boost. Die Actions `stimulus_pitch_up`, `stimulus_pitch_down`, `stimulus_boost` werden bei der Initialisierung registriert, ohne bestehende Belegungen zu überschreiben. Sie funktionieren auch über die Experimentatoransicht bei erlaubtem manuellen Override. Die freie Viewer-Steuerung ist unverändert.

Pitch ist eine Rotation um die lokale Querachse (+Z im Godot-Modell), nach der Yaw-Orientierung: `Basis(Y, yaw) * Basis(Z, pitch)`. Damit zeigt die Schnauze bei positivem Pitch auch beim linksgerichteten Fisch nach oben. Pitch verschiebt den Fisch nicht. Kamera, orthografische Projektion, Root-Tiefe und kalibrierter Maßstab bleiben unverändert. Die projizierte Körperlänge kann sich durch die Pose verkürzen.

## Kontrollierbare Parameter

Die Werte gehören in die portable `config/stimulus.json`. Alte Konfigurationen verwenden für fehlende Felder die Standardwerte.

| Parameter | Standard | Bedeutung |
| --- | ---: | --- |
| max_pitch_up_deg / max_pitch_down_deg | 25 / 25 | Grenzen in Grad; maximal je 45 konfigurierbar |
| pitch_speed_deg_s | 30 | maximale manuelle Neigungsrate |
| pitch_acceleration / pitch_deceleration | 60 / 90 | Grad/s² |
| pitch_return_speed | 18 | Rückkehrrate Grad/s |
| pitch_return_to_neutral | true | Loslassen kehrt weich auf neutral zurück; false hält den Winkel |
| boost_multiplier | 2.5 | Faktor auf die aktuelle Sollgeschwindigkeit |
| max_stimulus_speed_cm_s | 20 | absolute Geschwindigkeitsgrenze einschließlich Boost |
| operculum_frequency_hz | 1.0 | Basis-Atemfrequenz |
| operculum_amplitude | 0.00035 | lokale maximale Öffnung in Modellmetern; höchstens 0.0007 |
| operculum_phase | 0.0 | Startphase in Zyklen, modulo 1 |
| operculum_speed_coupling | 0.15 | maximale relative Frequenzerhöhung; 0 deaktiviert die Kopplung |
| operculum_response | 2.0 | Frequenzanpassung in 1/s |

Manuell bleibt die reguläre Sollgeschwindigkeit mit R/F bis `max_speed_cm_s` einstellbar. Shift multipliziert sie, ohne diesen Basiswert zu verändern: 4 cm/s werden zu 10 cm/s. Explizite Sequenzgeschwindigkeiten dürfen bis zur absoluten Grenze reichen. Beschleunigung und Verzögerung bleiben in cm/s² definiert. Die tatsächliche Geschwindigkeit steuert Animation und Wenderadius. Die Animationsrate bleibt auf `fast_animation_speed` begrenzt. Der Start aus Ruhe und Wendemanöver können die erreichbare Geschwindigkeit zusätzlich reduzieren.

## Kiemendeckel: Modellbefund und Umsetzung

Das Modell besitzt keine separaten Kiemendeckel, Kiemen-Bones oder entsprechenden lokalen Gewichte. Die vorhandene Operculumkontur ist Teil von Fish_Body. Das Erzeugungsscript beschreibt ihren Rand bei Referenzpixel (591,329), mit 0,08 m / 670 px. Diese vorhandene anatomische Position wird für die lokale Verformung verwendet.

Eine private Runtime-Kopie von Fish_Body erhält zwei Blendshapes `Operculum_Left` und `Operculum_Right`. Eine glatte, kompakt begrenzte Verformung hebt nur die seitlichen Kiemenbereiche an. Ihre Stärke fällt am Rand auf null ab. X/Y bleiben gleich; nur die lokale Breitenachse Z wird verändert. Die Normalen werden mit der invers transponierten lokalen Ableitung angepasst. Augen, Maul, Flossen, UVs, Skinning-Arrays und Basiskoordinaten werden nicht verändert. Die beiden Seiten werden symmetrisch angesteuert.

**Das gespeicherte Rig bleibt bei 15 Bones.** Zusätzliche Bones und Blender-/GLB-Änderungen sind nicht notwendig. Die Runtime-Blendshapes sind die minimale zusätzliche Deformationsschicht. Beim Verlassen wird die ursprüngliche Mesh-Resource exakt zurückgesetzt. Die importierte Resource wird nie direkt verändert.

Die Öffnungsandeutung wird jetzt durch zwei schmale, dunkelbraune, an das Skeleton gebundene Innenrandflächen ergänzt (siehe Erweiterung unten). Es entsteht keine vollständige Atemhöhle. Für anatomisch detaillierte Nahaufnahmen wäre später eine separate Deckelgeometrie erforderlich. Die Region ist auf dieses bestehende Modell abgestimmt; sie ist keine automatische Erkennung für beliebige andere Fischmodelle.

Die Atemkurve verwendet quintisches Smoothstep: 42 % des Zyklus öffnen, 13 % offen halten, 40 % schließen, 5 % geschlossen. Geschwindigkeit koppelt deterministisch über `f = Basisfrequenz * (1 + Kopplung * clamp(v / max_stimulus_speed_cm_s, 0, 1))`. Die Frequenz wird exponentiell geglättet. Keine Zufallswerte und keine Renderzeitintegration.

## Zusammenspiel

1. Lokale Kiemen-Blendshapes ergänzen den neutralen Meshzustand.
2. Das bestehende Skinning verwendet die Swim_Test-Pose.
3. Der temporäre SkeletonModifier ergänzt die Kurvenrotationen nach der Animation.
4. Der übergeordnete Bewegungsknoten orientiert den Fisch mit Yaw und Pitch.

Alle Zustände werden im gemeinsamen physikalischen Schritt berechnet. Sequenzen verwenden weiterhin das feste 1/240-s-Raster. Pause friert Pose, Atemphase und Animation ein; die protokollierte Atemfrequenz bleibt dabei der eingefrorene Oszillatorparameter. Es werden keine Rest-Pose, Bones oder importierten Animationstracks überschrieben.

## Sequenzen

Bestehende Schritte bleiben gültig. Im Sequenzeditor lassen sich pro Schritt optional Pitch-Zyklus, Boost und Atemfrequenz einschalten. Beispiel eines HOLD-Schritts:

```json
{
  "step_type": "HOLD", "duration_s": 5.0,
  "target_speed_cm_s": 0.0, "direction": "NONE", "comment": "Pitch isoliert",
  "target_pitch_deg": 20.0,
  "pitch_transition_s": 1.0, "pitch_hold_s": 2.0, "pitch_return_s": 1.0,
  "operculum_frequency_hz": 1.2
}
```

Die Übergänge folgen einer quintischen Kurve vom Winkel bei Schrittbeginn zum Ziel und zurück auf neutral. Die Dauerangaben sind verbindlich, statt die manuelle Beschleunigungsregel zu verwenden. Restzeit des Schritts wird neutral gehalten. Die drei Zeiten müssen zusammen in den Schritt passen; Übergang und Rückkehr müssen positiv sein. Die Vorprüfung kontrolliert die konfigurierten Winkelgrenzen. Ein MOVE-Schritt kann zusätzlich `"boost": true` verwenden. Fehlt die Atemfrequenz, gilt die Konfiguration; explizite Werte gelten für den jeweiligen Schritt und werden weich angefahren.

Sequenz-Pitch verändert niemals die Zielposition. Die bestehende Vorprüfung simuliert auch Boost und die daraus entstehenden größeren Wendebögen. Dadurch können bisher passende Bewegungsdauern oder Bildschirmgrenzen bei aktiviertem Boost nicht mehr ausreichen. Manuelle Overrides werden wie bisher protokolliert und verändern die tatsächlich präsentierte Bewegung.

## Logging und Diagnose

Zustandsproben enthalten `target_pitch_deg`, `actual_pitch_deg`, `pitch_input`, `pitch_transition_state`, `boost_active`, `boost_multiplier`, `target_speed_cm_s`, `actual_speed_cm_s`, `operculum_frequency_hz`, `operculum_amplitude`, `operculum_speed_coupling`, `operculum_phase`, `operculum_opening`. Pitch-Ereignisse heißen `PITCH_TRANSITION`, `PITCH_TARGET_REACHED`, `PITCH_HOLD`, `PITCH_RETURNING`, `PITCH_NEUTRAL`. Bestehende Wendeereignisse bleiben erhalten.

Die Experimentatoransicht zeigt Pitch Soll/Ist, tatsächliche Geschwindigkeit, Boost und Atemfrequenz. Das Stimulusfenster enthält keine neuen Bedienelemente oder Anzeigen.

`scripts/stimulus/run_motion_realism_validation.gd` prüft Bewegungsgrenzen, sanfte Übergänge, exakte Sequenzzeiten, Atemkurve, Boost, Logging, unveränderte Basisarrays, Skin und UVs, Wiederherstellung der Originalresource sowie die bisherigen Wende-, Sequenz-, Kalibrierungs- und Fenstertests. Drei identische Sequenzen mit unterschiedlichen Renderintervallen vergleichen sämtliche Zustände und Bone-Offsets. Screenshots liegen unter `godot/diagnostics/motion_realism_*`; Kiemenaufnahmen verwenden ausschließlich für die Diagnose eine vergrößerte Kameraansicht.

## Abnahme am 03.10.2026

48 reine Bewegungsprüfungen sowie 1.342 Prüfungen im exportierten Windows-Diagnosebuild bestanden. Auch nach Kopieren in einen umbenannten Ordner: 1.342 Prüfungen ohne Fehler. Drei Sequenzläufe mit unterschiedlichen Renderintervallen lieferten exakt identische Zustände. Die fünf zusätzlichen Regressionstests (freie Fischsteuerung, portable Speicherung einschließlich Fotoanalyse, Fotoimport, Projektverwaltung, Atlas-/Texturumschaltung) bestanden ebenfalls. Der reguläre portable Build wurde neu exportiert.

18 geschützte Dateien und die vorhandene Kalibrierungsrechnung sind unverändert. Testsystem: Godot 4.7.2, Windows, RTX 3070. Native Fenster-/Fokusprüfungen wurden auf einem physischen Monitor durchgeführt; kein Test mit zwei physischen Monitoren. Die Atmung ist eine kontrollierbare geometrische Näherung, keine validierte physiologische Simulation.


## Erweiterung: räumliche Orientierung und funktionale Flossen

### Zentrale Zustandsquelle

`stimulus_fish_controller.gd` erzeugt pro physikalischem Schritt `motion_state`: tatsächliche Geschwindigkeit, Sollgeschwindigkeit, Beschleunigung in cm/s², Drehraten, Pitch, Präsentations-Yaw, Boost, Bremsanteil, Atemphase und Öffnung. Die Beschleunigung stammt aus der tatsächlich integrierten Geschwindigkeitsänderung, nicht aus einer zweiten Positionsmessung. `fin_motion.gd` erhält genau diesen Zustand. Atmung und Orientierung integrieren ebenfalls nur in diesem gemeinsamen Schritt. Die Rendering-Modifier integrieren keine eigene Zeit.

Die vorhandene Wendeorientierung (`orientation_y_radians`) bleibt separat von der unabhängigen Präsentationsorientierung (`actual_yaw_deg`). Eine reine Präsentationsrotation erzeugt keine zusätzliche Wendekrümmung und keine Translation. Eine gleichzeitig ausgeführte Wende kann den Fisch weiterhin krümmen.

### Yaw-Bedienung und Winkel

**Ende** erhöht Yaw, **Pos1** vermindert Yaw. Die Actions heißen `stimulus_yaw_right` und `stimulus_yaw_left`. Bild↑/Bild↓ bleiben Pitch, Q/E bleiben Wenden, Shift bleibt Boost. Nach Loslassen bremst die Präsentationsrotation weich ab und hält ihren Winkel. **F8** setzt den gesamten Stimulus einschließlich unabhängiger Orientierung zurück.

Der Fisch zeigt lokal nach +X; die feste Kamera steht auf +Z. Daher wird die neue positive Yaw-Orientierung als `Basis(Y, -deg_to_rad(yaw))` umgesetzt:

| Yaw | Ansicht |
| --- | --- |
| 0° | definierte Ausgangsseite, Kopf rechts |
| 45° | schräge Ausgangsseite, Kopf zur Kamera |
| 90° | Frontansicht, Schnauze zur Kamera |
| 135° | schräge Gegenseite |
| 180° | Gegenseite, Kopf links |
| 270° | Rückansicht |
| 360° | wieder Ausgangsseite |

Keine künstliche Verbreiterung der Frontansicht. Kamera, Tiefe und Modellskalierung bleiben konstant. Positive Pitch-Werte heben die Schnauze weiterhin bei jedem Yaw. Ohne aktivierte unabhängige Orientierung folgt das Modell wie bisher der Bewegungsorientierung. Nach erstmaliger manueller Yaw-Eingabe oder einem Yaw-Sequenzziel bleibt die unabhängige Orientierung aktiv, bis F8 beziehungsweise ein neuer Versuch sie zurücksetzt. Weiteres Wenden/Bewegen verändert dann die Präsentationsorientierung nicht automatisch.

Manuelle Parameter: `yaw_speed_deg_s=45`, `yaw_acceleration=90`, `yaw_deceleration=120` (Grad/s beziehungsweise Grad/s²). Die manuelle Rotation ist nicht auf ±25° begrenzt und kann beide Seiten vollständig durchlaufen. Der manuelle Sollwinkel im Log bezeichnet den aktuellen berechneten Bremsendpunkt. Sequenzen speichern absolute, nicht modulo 360 gefaltete Winkel: Der Übergang von 0° auf 270° läuft tatsächlich über 270°, nicht über die kürzere Gegenrichtung.

### Sequenzfelder

Kein neuer Schritttyp ist nötig. Bestehende Schritte akzeptieren zusätzlich:

```json
{
  "step_type": "HOLD", "duration_s": 7,
  "target_speed_cm_s": 0, "direction": "NONE", "comment": "Frontansicht",
  "target_yaw_deg": 90,
  "yaw_transition_duration_s": 2,
  "yaw_hold_duration_s": 5
}
```

Die Bewegung folgt einer quintischen Kurve vom Winkel zu Schrittbeginn zum Ziel. Danach bleibt der Winkel erhalten, auch über folgende Schritte ohne neues Yaw-Ziel. Übergangs- plus Haltedauer müssen in den Schritt passen; Restzeit hält ebenfalls den Zielwinkel. Nach dem Beispiel kann ein weiterer Schritt mit Ziel 180° folgen. Pitch kann gleichzeitig definiert werden. Zusätzlich zu den bisherigen kurzen Pitch-Zeitnamen werden `pitch_transition_duration_s`, `pitch_hold_duration_s` und `pitch_return_duration_s` akzeptiert. Widersprüchliche Aliaswerte werden abgewiesen. Bestehende Sequenzen bleiben lesbar. Die Sequenzzeiten sind verbindlich; die manuellen Geschwindigkeitsparameter gelten für die Tastatursteuerung.

### Sichtbare Kiemenöffnung

`gill_interior.gd` erzeugt ausschließlich zur Laufzeit zwei schmale Innenrandflächen mit zusammen **128 Dreiecken**. Ihre Positionen und Skin-Gewichte werden baryzentrisch aus dem bestehenden Körpermesh bestimmt; sie verwenden dieselbe Skin-Resource und dasselbe Skeleton. Die zusätzlichen Flächen bewegen sich synchron mit den lokalen Operculum-Blendshapes. Absolute Blendshape-Koordinaten werden ausdrücklich im NORMALIZED-Modus verwendet, damit keine doppelte Translation auftritt. Im geschlossenen Zustand sind die Innenflächen ausgeblendet.

Bei Standardamplitude 0,00035 m beträgt die maximale lokale Öffnung **0,35 mm** am 8-cm-Basismodell. Die dunkle Spaltzone erreicht bis zu ungefähr **0,35 mm Breite** und folgt einem etwa 11 mm langen, an den Enden auslaufenden Rand. Bei anderer kalibrierter Fischgröße skaliert sie proportional. Ihre tatsächliche Pixelausdehnung hängt von Bildschirmkalibrierung und Blickwinkel ab. Es handelt sich um eine optische Innenranddarstellung auf dem lokal verformten Modell, nicht um eine neue anatomisch vollständige Kiemenhöhle. Gespeicherte GLB-/Blender-Geometrie, UVs und Rig werden nicht verändert. Beim Verlassen werden die beiden Hilfsmeshes entfernt.

Neu konfigurierbar: `operculum_open_ratio=0.42`, `operculum_close_ratio=0.40`. Beide Werte müssen positiv sein, ihre Summe darf 0,95 nicht überschreiten. Die verbleibende Zeit bis 95 % des Zyklus ist maximale Öffnung; die letzten 5 % bleiben geschlossen. Frequenz, Amplitude, Phase und Geschwindigkeitskopplung bleiben wie oben beschrieben.

### Brustflossen und passive Flossen

Der bestehende post-animation SkeletonModifier nutzt jetzt **14 vorhandene Bones**: Körperkette und alle verfügbaren Flossen-Bones, ohne Root. Das Rig hat weiterhin 15 Bones. Die zusätzlichen Offsets werden nach Swim_Test auf die frische Animationspose angewendet, nicht über Frames aufaddiert.

| Parameter | Standard | Bedeutung |
| --- | ---: | --- |
| pectoral_frequency_hz | 1.2 | reproduzierbarer Flossentakt |
| pectoral_hover_amplitude | 0.14 rad | sichtbare, schwache Bewegung beim Schweben |
| pectoral_cruise_amplitude | 0.045 rad | weniger dominante Bewegung bei Fahrt |
| pectoral_brake_amplitude | 0.28 rad | beidseitiges Ausstellen proportional zur Verzögerung |
| pectoral_turn_amplitude | 0.14 rad | zusätzliche asymmetrische Auslenkung beim Wenden |
| pectoral_pitch_amplitude | 0.025 rad | subtile Unterstützung bei Neigung |
| passive_fin_amplitude | 0.035 rad | sehr schwache passive Flossenbewegung |
| fin_response | 5 /s | weiche Anpassung der Flossenwinkel |

Bei positiver bestehender Heading-Drehrate öffnet sich die linke (-Z) Brustflosse stärker, bei negativer die rechte (+Z). Das ist eine kontrollierbare Näherung für äußeren Widerstand, kein validiertes hydrodynamisches Modell. Die unabhängige Präsentationsrotation allein löst diese Asymmetrie nicht aus. Der Bremsanteil ist `clamp(-acceleration_cm_s2 / deceleration_cm_s2, 0, 1)`. WAIT beziehungsweise Loslassen bremst physikalisch; HOLD behält wie bisher seine explizite Positionshalte-Semantik.

Bauchflossen, Dorsal_01, Dorsal_02 und Anal_Fin_2 erhalten deutlich kleinere passive Winkel. Vorhandene Swim_Test-Schwanzamplituden bleiben erhalten; höhere Geschwindigkeit erhöht weiterhin die begrenzte Animationsrate. Es gibt keine zusätzliche unkontrollierte Verstärkung der Schwanzamplitude.

### Licht und Fototextur bei Frontansicht

Bei der räumlichen Prüfung wurden schwarze Bauchflächen auf eine fehlende Umgebungslichtquelle zurückgeführt: Der Stimulus verwendete AMBIENT_SOURCE_SKY ohne Sky. `StimulusMode.tscn` verwendet nun AMBIENT_SOURCE_COLOR mit der bereits vorhandenen neutralen Lichtfarbe/Energie. Hintergrund, Kamera und Größenkalibrierung bleiben gleich. Dies verändert die Ausleuchtung des Fisches und sollte bei der Planung neuer visueller Versuche berücksichtigt werden. Die Texturdateien und ihre Projektion wurden nicht verändert.

Die generierte Textur wurde bei 0/45/90/135/180° sowie Frontansicht mit ±15° Pitch geprüft. Nach der Lichtkorrektur sind die zuvor schwarzen unbeleuchteten Bauchflächen nicht mehr vorhanden; die Körpermaterialien sind deckend, und die generierte Albedo bleibt auch auf der Runtime-Meshkopie aktiv. Gewollte dunkle Zeichnung, Maulspalt und Kiemeninnenflächen bleiben dunkel. Die Gegenseite ist aus einem einzelnen Seitenfoto abgeleitet. Besonders frontal bleiben breite, teils bandförmig gestreckte Farbübergänge an Stirn/Bauch und vereinfachte Kopfdetails sichtbar. Das sind vorhandene Rekonstruktionsgrenzen, keine fehlenden UV-Flächen; eine realistische Frontaltextur kann aus dem Seitenfoto allein nicht garantiert werden.

### Logging, Diagnose und Reproduzierbarkeit

Neu: `actual_yaw_deg`, `target_yaw_deg`, `yaw_speed_deg_s`, `yaw_transition_state`, `independent_yaw`, `acceleration_cm_s2`, `braking_amount`, `operculum_open_amount`, `operculum_open_ratio`, `operculum_close_ratio`, `pectoral_left_angle`, `pectoral_right_angle`, `fin_phase`, `passive_fin_angle`. Flossenwinkel sind Radiant. `YAW_TRANSITION`, `YAW_HOLD` und `YAW_TARGET_REACHED` dokumentieren die Präsentationsorientierung. Die Experimentatoransicht zeigt Yaw Soll/Ist und Kiemenöffnung zusätzlich zu Pitch, Tempo und Atmung. Im Stimulusfenster erscheinen keine zusätzlichen Anzeigen.

`run_spatial_motion_validation.gd` erweitert alle bisherigen Tests. Drei identische Sequenzen mit unterschiedlichen Renderintervallen vergleichen Pose, Winkel, Atem-/Flossenphasen, Geschwindigkeit, Radien, Zeit und Endposition exakt. Die optionalen `-- --spatial-video`-Aufnahmen erzeugen Entwicklungsframes für die Diagnoseanimation. Diese Aufnahme hält den Fisch absichtlich zentriert und verwendet eine vergrößerte Diagnosekamera, damit Öffnung und Flossen erkennbar sind; sie ist **kein wissenschaftlicher Stimuluslauf** und kein Standardversuch. Die Produktionskamera wird dadurch nicht verändert.

### Abnahme der räumlichen Erweiterung am 03.10.2026

91 reine Bewegungsprüfungen bestanden. Der vollständige grafische Lauf besteht 1.447 Prüfungen; ebenso der exportierte Windows-Diagnosebuild und der in einen umbenannten Ordner kopierte Build. Die fünf zusätzlichen Regressionstests für Fotoimport, Analyse, Texturerzeugung, Projektverwaltung, freie Fischsteuerung und portable Speicherung sind erfolgreich. 18 geschützte Dateien sowie die Kalibrierungsrechnung blieben unverändert.

Frühere Exporttests wurden durch Fokuswechsel bei parallel geöffneter älterer Anwendung gestört; die abschließenden getrennten Läufe sind fehlerfrei. Die alte laufende EXE blockierte außerdem vorübergehend das Überschreiben des Builds. Nach ihrem Ende konnte der reguläre `dist/PelvicachromisStudio`-Ordner aktualisiert werden. Ein tatsächlicher Zweimonitor-Aufbau wurde weiterhin nicht getestet.

Die 43-sekündige Diagnoseanimation liegt in `godot/diagnostics/spatial_motion_demo.mp4`, die zugehörigen Zustände in `spatial_video.json`. Blickwinkel-, Kiemen- und Bewegungsbilder beginnen mit `spatial_`.
