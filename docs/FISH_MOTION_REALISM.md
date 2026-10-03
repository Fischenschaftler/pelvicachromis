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

Dies ist eine subtile Öffnungsandeutung der vorhandenen geschlossenen Oberfläche, kein neu modellierter Kiemenspalt oder frei scharnierender Deckel. Es entsteht keine Atemhöhle. Für anatomisch detaillierte Nahaufnahmen wäre später eine separate Deckelgeometrie erforderlich. Die Region ist auf dieses bestehende Modell abgestimmt; sie ist keine automatische Erkennung für beliebige andere Fischmodelle.

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
