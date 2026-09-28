# Geführter Fotoimport

## Start und Ablauf

`scenes/PhotoImport.tscn` ist die neue Startszene (Godot F6 für diese Szene, F5 für das Projekt). Sie erbt den unveränderten Viewer aus `Main.tscn` und ersetzt dessen Foto-Panel. Der bisherige Versuchsablauf ist weiterhin über `Main.tscn` erreichbar.

1. **Foto auswählen**: JPG, JPEG oder PNG im Godot FileDialog öffnen. Es wird ausschließlich gelesen. Vorschau und Verarbeitung verwenden geladene Bildkopien.
2. **Linke Fischseite** oder **Rechte Fischseite** wählen. Gemeint ist die anatomische Seite, nicht die Richtung des Kopfes im Bild.
3. **Ausrichten**: zwölf Referenzpunkte in der angezeigten Reihenfolge anklicken. Bereits gesetzte Punkte sind nummeriert und können jederzeit gezogen werden. Die Statuszeile und die Legende erklären die Nummern. Koordinaten beziehen sich immer auf das Originalbild, unabhängig von Fenstergröße und Vorschauskalierung.
4. **Maske zeichnen / korrigieren**: den gesamten Fisch einschließlich sichtbarer Flossen grob mit einem Polygon umranden. Doppelklick oder **Kontur schließen** beendet die Eingabe. Punkte können danach gezogen werden; **Maske neu zeichnen** beginnt neu. Kreuzende oder unvollständige Polygone werden nicht verarbeitet.
5. **Textur erzeugen**: lokale Berechnung im Hintergrundthread. Standard sind 2048×2048 Pixel, optional 4096×4096. Danach wird die Textur ohne Neustart auf Körper und Flossen angezeigt.
6. **Originalfärbung / Generierte Färbung** erlaubt den Vergleich. **Zurücksetzen** entfernt Foto, Markierungen und generierte Textur aus dem aktiven Zustand und stellt die ursprünglichen Materialien wieder her. Gespeicherte Arbeitsdateien werden nicht automatisch gelöscht.

Links steht bei breitem Fenster das Foto, rechts der animierte Fisch. In schmalen Fenstern werden beide Bereiche übereinander angeordnet. Der Foto-Bereich scrollt. Kamera, Zoom, Kamerarückstellung und Animation bleiben unabhängig bedienbar.

## Zwölf Referenzpunkte

1. Schnauzenspitze
2. Augenmitte
3. Schwanzstiel oben am Übergang zur Schwanzflosse
4. Schwanzstiel unten am Übergang zur Schwanzflosse
5. Oberer äußerer Schwanzflossenrand
6. Unterer äußerer Schwanzflossenrand
7. Vorderer Rückenflossenansatz
8. Hinteres Ende der Rückenflosse
9. Vorderer Afterflossenansatz
10. Hinteres Ende der Afterflosse
11. Ansatz der sichtbaren Bauchflosse
12. Spitze der sichtbaren Bauchflosse

Die bekannte Modellseite liefert die entsprechenden Zielpunkte. Eine Thin-Plate-Spline-Zuordnung berücksichtigt Verschiebung, Rotation, Skalierung und moderate Proportionsunterschiede. Aus Schnauze und Schwanzstiel wird die Körperachse bestimmt. Kopf-links-Fotos werden nur in der Arbeitskopie gespiegelt. Ungültige, zusammenfallende, vertauschte oder stark faltende Zuordnungen führen zu einer verständlichen Meldung.

## Wiederverwendete Verarbeitung

- `polygon_mask.gd`: Originalpixel-Maske und Polygonprüfung.
- `fish_normalizer.gd`: freigestellte, horizontal ausgerichtete Arbeitskopie; benötigte Körperextrema werden aus der Zwölfpunkt-Zuordnung geschätzt.
- `body_texture_baker.gd`: vorhandene Body-UV-Dreiecke und maskierte Projektion; verwendet nun für diesen Aufrufer zwölf Fotoanker.
- `fin_texture_baker.gd`: lokale ARAP-/Dreiecksabbildung, gültige Maskenproben und Atlas-Randzugabe. Der Aufrufer kann die zu bearbeitenden Flossen und eine angepasste Abtastvorlage übergeben. Alte Aufrufer bleiben kompatibel.

Die Umrisse von Schwanz-, Rücken-, After-, Bauch- und Brustflossen werden zunächst aus Modellvorlagen durch die Landmark-Zuordnung ins Foto übertragen und mit der Fischmaske geschnitten. Es erfolgt keine automatische Bilderkennung. Besonders die Brustflosse besitzt noch keine eigene Landmark und wird näherungsweise aus dem angrenzenden Kopf-/Körperbereich positioniert. Bei verdeckten oder stark anders gehaltenen Flossen kann die Zuordnung ungenau sein oder mit einer Meldung abbrechen. Die manuelle Gesamtkontur erlaubt grobe Korrekturen, ersetzt aber keine präzise automatische Flossensegmentierung.

`data/photo_import_projection.json` enthält unveränderte UVs, Restkoordinaten, Flossengrenzen, Interpolationsgewichte und Modellanker. Für überlappende Seitenprojektionen räumlicher Flossen wird eine ebene Abtastvorlage aus der vorhandenen UV-Insel geschätzt. Diese Vorlage ist nur Metadaten: Mesh und UVs werden nicht geändert. Der GLB-Hash verhindert die Verwendung unpassender Modelldaten.

## Fotografierte Seite und Fallback

`photo_side` wird als `left` bzw. `right` gespeichert und bezeichnet die primäre Körper-UV-Insel. Beide Inseln werden getrennt über ihre tatsächlichen UV-Dreiecke befüllt. Für die nicht fotografierte Seite wird **vorläufig dieselbe fotografierte Zeichnung gespiegelt** verwendet; die Metadaten nennen die Fallback-Insel ausdrücklich. Das ist keine Rekonstruktion der echten Gegenseite.

Bei Bauch- und Brustflossen werden die Abtastkoordinaten der gewählten sichtbaren Seite auch für die jeweils andere Flosse verwendet. Beide Objekte behalten ihre eigenen UV-Inseln und Materialien. Augen und Mund erhalten keine neuen Materialüberschreibungen. Knochen, Skinning und Animation bleiben unverändert.

## Dateien und Speicherung

Neue Laufzeitskripte unter `scripts/photo_import/`:

- `photo_import_controller.gd`: UI, FileDialog, Arbeitszustand, Hintergrundjob, Materialwechsel.
- `landmark_editor.gd`: geführte Punkteingabe, Verschieben und Polygonkorrektur.
- `texture_projection.gd`: wiederverwendbare Verarbeitung ohne UI-Abhängigkeit.

Ergebnisse liegen unter `user://photo_import/<Zeit>_<ID>/`:

- `mask.png`: Fischmaske in Originalauflösung.
- `normalized.png`: freigestellte Arbeitskopie.
- `albedo.png`: neue Gesamttextur, niemals die Originaltextur.
- `project.json`: Originalpfad, gewählte Seite, zwölf Originalpixel-Punkte, Polygon, Normalisierung, UV-Seitenzuordnung, Fallbacks und Projektionsstatistik.

Intern hält der Controller `source_path`, `texture_path` und `metadata_path`. Ein Reset oder neue Eingaben entwerten laufende Ergebnisse durch eine Revisionsnummer; alte Jobs können den neuen Zustand nicht überschreiben.

## Abhängigkeiten und Grenzen

Zur Laufzeit werden ausschließlich Godot 4 und GDScript benötigt. Keine Python-Prozesse, KI-Modelle, Netzwerk- oder Cloud-Dienste. `extract_projection.py` ist ein optionales Entwicklungswerkzeug, das Blender/Python/NumPy nur zum erneuten **lesenden** Extrahieren der Metadaten benötigt. Die fertigen Daten liegen im Repository; Endanwender benötigen Blender nicht.

Der Prototyp wurde mit dem vorhandenen Foto und einer gespiegelten PNG-Arbeitskopie technisch geprüft. Das beweist keine zuverlässige Qualität für beliebige Fische, Perspektiven und Beleuchtung. Verdeckte Flossen, starke Perspektive, ungenaue Konturen, falsche Punkte und breite Hintergrundstreifen können sichtbare Fehler erzeugen. Eine einzelne Aufnahme kann die andere Seite nicht wahrheitsgetreu liefern. 2048 Pixel reduzieren Rechenzeit, aber auch Texturdetails. Die Funktion ist eine geführte manuelle Projektion, keine automatische Freistellung oder Erkennung.

Die Trennung zwischen Editor, `alignment()` und `generate()` bereitet spätere automatische Landmark-/Maskenlieferanten vor. Solche Erkennung kann später dieselben Originalpixel-Daten liefern, ohne Viewer oder UV-Projektion zu ersetzen.

## Regression

`scripts/photo_import/validate_photo_import.gd` prüft Laden, ungültiges Format, zwölf Punkte, Verschieben, Transformation bei kleinen und 4000px-Koordinaten, JPEG und gespiegeltes PNG, beide Seiten, Texturerzeugung, Live-Wechsel, Reset, 15 Bones, unveränderte Mesh-/Skinning-Arrays, Swim_Test und Kameraeingaben. Ergebnis und Screenshot: `godot/diagnostics/photo_import_ui_validation.json`, `photo_import_ui.png`.
