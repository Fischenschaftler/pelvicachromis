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

Die sechs anatomischen Landmarken liefern zunächst eine ungefähre Registrierung des Modell-Flossenrandes zum Foto. Entlang der beiden Umrisse werden passende Randpunkte gesucht: Laufrichtung wird angeglichen, der zyklische Startpunkt wird durch einen Positionsvergleich bestimmt. Der Benutzer muss somit nicht an einem bestimmten Punkt oder in einer festen Richtung beginnen.

Bevorzugt wird nur die Differenz zwischen registriertem Modellrand und markiertem Fotorand in die Innenfläche übertragen. Die harmonischen Gewichte verteilen diese Verschiebung weich. Das bewahrt lokale Strahlen- und Fleckenzeichnung besser als eine vollständige Neuparametrisierung. Kleine Faltungen in den **Foto-Abtastkoordinaten** werden lokal geprüft und begrenzt korrigiert; die tatsächliche Modellgeometrie bleibt unverändert.

Für Konturen, bei denen diese Abbildung nicht ohne Faltungen möglich ist, wird ein robuster Ersatz verwendet: Modell und Fotokontur werden über eine gemeinsame Scheibenkoordinate abgebildet. Das Modell nutzt positive harmonische Gewichte, die Fotokontur eine Dreieckszerlegung ohne Überlappungen. Eine radiale Randkorrektur gleicht die unterschiedlichen Randteilungen aus. Die Abbildung ist dann innerhalb der Dreiecke stückweise und berücksichtigt auch eingezogene Polygonkonturen. Es wird kein rechteckiger Ausschnitt aufgestreckt.

Jeder Atlastexel wird über sein vorhandenes UV-Dreieck in diese Abbildung eingesetzt. Abgetastet werden ausschließlich gültige Pixel der jeweiligen Flossenmaske. Direkt am Rand kann der nächstliegende gültige Pixel innerhalb von vier Quellpixeln verwendet werden; außerhalb der Maske liegende Farben werden niemals übernommen. Die interpolierte Quelltransparenz wird mit der bisherigen Flossen-Alpha kombiniert. Die optische Durchsichtigkeit eines Flossenfotos wird dadurch nicht vollständig rekonstruiert; die vorhandenen Materialeinstellungen bleiben erhalten.

Vier Texel Randzugabe im jeweils reservierten Flossen-Slot vermindern helle Filter-/Mipmap-Nähte. Sie kopieren bereits gültige Randfarben und berühren keine andere UV-Insel. Die Kopf-/Körpertextur wird vollständig aus der letzten Körperübertragung übernommen und nicht erneut berechnet.

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
