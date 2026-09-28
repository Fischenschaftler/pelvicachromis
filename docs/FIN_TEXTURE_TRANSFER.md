# Fototextur für Schwanz-, Rücken- und Afterflosse

## Bedienung

Nach Fotoimport, Freistellung, Landmark-Bestätigung und erfolgreicher **Körperübertragung** erscheint **Flossen markieren**.

1. Auf dem normalisierten Foto die Schwanzflosse umranden. Flossenansatz und äußeren Rand einschließen.
2. Mit **Kontur schließen** oder Doppelklick abschließen. Die Rückenflosse wird als nächste Auswahl aktiviert.
3. Rücken- und Afterflosse ebenso markieren.
4. **Flossenfärbung übertragen** erzeugt eine neue Gesamttextur und zeigt sie direkt an.

Die Auswahl benennt die aktuelle Flosse. Gespeicherte Konturen bleiben farbig sichtbar: Schwanz gelb, Rücken türkis, After rosa. Über die Auswahlliste und **Flosse zurücksetzen** lässt sich jede Kontur einzeln neu zeichnen. Die letzte fertige Textur bleibt bis zur erneuten Übertragung verfügbar.

**Originalfärbung** stellt alle Originalmaterialien wieder her. **Generierte Färbung** zeigt die letzte Gesamttextur mit Körper und drei Flossen. Augen, Mund, Bauch- und Brustflossen behalten ihre Originalmaterialien. Entfernen des Fotos aktiviert die Originalfärbung. Neue Referenzpunkte oder eine neue Körpertextur verwerfen die bearbeitbaren Flossenmasken; laufende Ergebnisse der alten Referenz werden nicht angewendet.

## Bestehende UV-Inseln

`scripts/extract_fin_projection.py` liest die aktuelle Blender-Datei, die aktive **PhotoUV** und die Rest-Geometrie. Es speichert die Blender-Datei nicht. Die Zuordnung erfolgt über die Objektnamen und deren echte UV-Dreiecke, nicht über geschätzte Bildrechtecke.

| Objekt | U | V in Blender | Mesh-Vertices | Randpunkte |
| --- | --- | --- | --- | --- |
| `Caudal_Fin` | 0,73–0,98 | 0,64–0,98 | 258 | 94 |
| `Dorsal_Fin` | 0,02–0,54 | 0,17–0,32 | 387 | 100 |
| `Anal_Fin` | 0,73–0,98 | 0,31–0,61 | 315 | 84 |

`data/fin_projection.json` enthält UVs, Dreiecksindizes, den geordneten Inselrand und positive harmonische Interpolationsgewichte für die Innenpunkte. Die Gewichte werden einmal aus der vorhandenen Mesh-Nachbarschaft berechnet. Weder Vertexpositionen noch Topologie oder UV-Koordinaten werden dabei verändert. PNG-Koordinaten verwenden `1-V`; vor einer Berechnung wird der GLB-Hash geprüft.

## Formgerechte Abbildung

Die gezeichneten Konturen werden in **Pixelkoordinaten der normalisierten PNG** gespeichert. Anzeige-Leerräume und Skalierung werden genauso berücksichtigt wie bei der vorhandenen Polygonfreistellung. Die Masken besitzen die volle Auflösung dieser Arbeitskopie und werden mit deren vorhandener Alpha-Maske geschnitten. Sie enthalten damit keine Hintergrundpixel außerhalb der Freistellung.

Die Körperlängsachse aus Schnauze und Schwanzstiel definiert eine längen- und winkeltreue Startabbildung. Die frühere TPS-Extrapolation außerhalb des Körpers sowie die Kreisparametrisierung der Schwanzflosse entfallen. Basis und Außenkontur erhalten lokale, geordnet bleibende Entsprechungen auf der Fotokontur. Dadurch müssen einzelne Merkmale nicht mehr einer einzigen Umfangsskalierung folgen.

Eine lokale/globale **ARAP-Optimierung** verteilt die Formanpassung auf die vorhandenen Dreiecke. Sie bevorzugt lokale Rotationen bei gleicher Ausgangsskalierung und begrenzt dadurch Scherung und ungleichmäßige Flächenverteilung. Die endgültige Abbildung ist pro Dreieck affin/baryzentrisch. Eine separate Prüfung verhindert Faltungen; bei schwierigen Konturen wird begrenzt zur harmonischen Anfangslösung zurückgeblendet. Sämtliche Berechnungen betreffen ausschließlich Foto-Abtastkoordinaten, niemals Mesh, UVs oder Rig.

Bilineares Sampling berücksichtigt nur gültige Pixel innerhalb der jeweiligen Maske und gewichtet RGB mit Alpha. Fehlt eine gültige Probe, wird eine gültige Quellkoordinate aus einem Distanzfeld verwendet. Anders als zuvor bleiben dadurch keine alten Atlaspixel in der Flossenfläche stehen. 16 Texel Randzugabe innerhalb des reservierten Slots verhindern das Einfiltern alter Atlasfarben auf den üblichen Mipmap-Stufen.

Am freien unteren Afterflossenrand erfolgt zusätzlich eine begrenzte Hintergrundprüfung: Nur wenn die Farbe direkt innerhalb der Kontur zum tatsächlich sichtbaren Außenbereich passt und wenige Pixel weiter innen ein anhaltender Farbwechsel liegt, wird dieser schmale Streifen aus der internen Samplingmaske ausgeschlossen. Ist der Außenbereich in der normalisierten Arbeitskopie bereits transparent, wird seine Farbe über die gespeicherte inverse Normalisierung aus dem Originalfoto gelesen. Diese Außenfarbe dient ausschließlich der Entscheidung; sie wird niemals in die Textur übernommen. Fehlt das Originalfoto, entfällt dieser zusätzliche Kontext. Die Prüfung nutzt Farbunterschiede, keinen pauschalen Helligkeitsfilter. Sie verändert weder das Foto noch die gespeicherte Benutzermaske. Mehrdeutige bzw. zu breite Streifen bleiben bewusst erhalten. Echte helle oder halbtransparente Pixel werden ansonsten übernommen.

## Ursachen und Ergebnis der Projektionskorrektur

- Die alte Kreisabbildung verteilte Flächen in der Schwanzflosse ungleichmäßig; die globale Umfangszuordnung konnte Basis und Außenrand gegeneinander verschieben. Schwarze Flecken wurden dadurch lokal vergrößert.
- Die Extrapolation der Körper-TPS lieferte außerhalb der Körperlandmarken keine kontrollierte lokale Skalierung. Rücken- und Afterflossenzeichnung wurde sichtbar gestreckt.
- Sampling außerhalb der Polygonmaske war bereits ausgeschlossen. Der Saum hatte weitere Quellen: Hintergrundpixel **innerhalb** der groben Markierung, nicht beschriebene Randtexel und zu knappe Atlas-Randzugabe. Die normalisierte Referenz zeigt diesen eingeschlossenen Hintergrundstreifen bereits vor der Projektion.

Der Ausgangsstand ist Commit `bcb52a8`. Vorher-/Nachherbilder verwenden dieselbe Kamera, Pose und Ausschnittgröße. Die Flächenverteilungsstreuung der Schwanzflosse sank im Dreiecksvergleich von 0,646 auf 0,505. Das ist keine Garantie für identische Fleckenformen: Die globale Formanisotropie der Schwanzflosse verbessert sich nicht durchgehend (0,458 → 0,479 im flächengewichteten logarithmischen Maß). An groben Konturecken bleiben lokale Verzerrungen. Rücken- und Afterflosse sind deutlich gleichmäßiger. Diese Werte vergleichen Abtastdreiecke; die frühere nichtlineare Kreisabbildung wird dabei an deren Eckpunkten angenähert.

## Speicherorte und Zustand

- `user://fin_masks/`: für jede Markierung eine eigene PNG und JSON mit Flossenname, normalisierten Konturpunkten, Referenz- und Körpertexturpfad.
- `user://generated_textures/combined_<Zeit>_<ID>.png`: vollständige neue Gesamttextur.
- Gleichnamige `.json`: verwendete Masken, Konturen, Körpertextur und Projektionsstatistik.
- `combined_…_fin_coverage.png`: tatsächlich neu belegte UV-Texel einschließlich Randzugabe.

Windows verwendet normalerweise `%APPDATA%\Godot\app_userdata\Pelvicachromis Studio\`. Tests laufen isoliert unter `.godot/test_runtime/`.

Intern: `ReferencePhoto.fin_transfer.mask_paths`, `polygons`, `current_path`, `metadata_path` und `coverage_path`. `texture_transfer.body_texture_path` hält weiterhin die reine Körpertextur, `texture_transfer.current_generated_path` die zuletzt erzeugte Gesamttextur. Änderungen einer Kontur werden stets erneut auf der reinen Körpertextur aufgebaut; alte Flossentexturen werden nicht mehrfach übereinandergelegt.

## Dateien

- Geändert: `scripts/reference_photo.gd`, `scripts/body_texture_transfer.gd`.
- Neu: `scripts/fin_texture_transfer.gd`, `scripts/fin_polygon_canvas.gd`, `scripts/fin_texture_baker.gd`.
- Neu: `scripts/extract_fin_projection.py`, `data/fin_projection.json`.
- Tests/Diagnose: `scripts/validate_fin_transfer.gd`, `scripts/compose_fin_diagnostic.py`, `godot/diagnostics/fin_*`.

## Prüfung und Grenzen

Der Integrationstest durchläuft das Laden des 4000×3000-Fotos, Fischpolygon, sechs Landmarken, Normalisierung, Körperübertragung und alle drei Flossenmasken mit echten Godot-Mauseingaben. Er prüft unvollständige Konturen, Einzel-Reset, umgekehrte Zeichenrichtung, Größenänderung während des Markierens, getrennte Speicherung, Original-/Generiert-Umschaltung, 15 Bones, unveränderte Mesh-Arrays, geschützte Materialien, Swim_Test, Kamera, Zoom, Reset und veraltete Berechnungsergebnisse.

Die Diagnose prüft pixelweise, dass außerhalb der drei Flossen-Slots nichts gegenüber der bereits generierten Körpertextur verändert wurde. Alle 15 geschützten Modell-/Blender-/Texturdateien werden per SHA256 geprüft.

Konturen und Modell haben nicht genau dieselbe Form. Schwarze Flecken können deshalb in Größe und Position abweichen; Strahlen und Farbflächen können lokal gestreckt sein. Körper-/Flossenübergänge sind durch die bisherige Körpertextur und manuelle Masken begrenzt. Belichtung aus dem Foto bleibt erhalten. Die Masken können keine Bereiche zurückholen, die bereits bei der ursprünglichen Fischfreistellung abgeschnitten wurden.

```powershell
godot --path . --script res://scripts/validate_fin_transfer.gd
python scripts/compose_fin_diagnostic.py
```

Ausgangsstand lokal gesichert mit `dda22ed`. Keine Änderungen gepusht.

Abschließender Test: keine Godot-Testfehler; keine gefalteten Projektionsdreiecke. Pixelvergleich: keine Änderungen außerhalb der drei Flossen-Slots, Körpertextur pixelgleich. Alle 15 geschützten Dateien unverändert. Geprüfte Fenstergrößen schließen 600×900 und 480×360 ein. Sichtbar bleiben vergrößerte Schwanzflecken, lokale Streckungen und ein heller Rand an der Afterflosse.

## Zusätzliche Regression und Diagnose

- `scripts/validate_fin_sampling.gd`: 1024 absichtlich mit falscher Außenfarbe umgebene Proben; echte helle/transparente Kanten bleiben erhalten; eingeschlossener Hintergrundstreifen wird erkannt.
- `scripts/validate_fin_projection.gd`: liest den alten Baker aus Commit `bcb52a8` und vergleicht seine Abtastkoordinaten mit der aktuellen Version.
- `scripts/compose_fin_refinement.py`: erzeugt `godot/diagnostics/fin_projection_diagnostic.png`, `fin_before_after.png` und `fin_distortion_metrics.json`.
- Der vollständige Godot-Test prüft weiterhin Swim_Test, 15 Bones, identische Mesh-Arrays, geschützte Materialien, Kamera, Zoom, Reset, Texturumschaltung und schmale Fenster.

Keine Änderungen gepusht. Die Projektionskorrekturen sind noch nicht committet.

Die aktuelle Referenzprüfung weist 3336 kontaminierte Randpixel der Afterflosse aus der internen Samplingmaske zurück. `fin_anal_sampling_mask.png` zeigt die effektiv verwendete Maske. Das Körperatlas bleibt pixelgleich; sämtliche 15 geschützten Modell-/Blender-/Originaltexturdateien bleiben unverändert. Am Schwanz bleiben Unterschiede in Fleckenform und -position sowie lokale Streckungen nahe den polygonalen Außenkanten. Ein sicherer allgemeiner Nachweis, dass jede helle Kante Hintergrund ist, ist aus einem einzelnen Foto nicht möglich; unklare helle Bereiche bleiben erhalten.
