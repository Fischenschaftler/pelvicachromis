# Anatomische Referenzpunkte und Normalisierung

Nach einer erfolgreichen Polygon-Freistellung erscheint **Referenzpunkte setzen**. Die sechs Punkte werden auf der transparenten Freistellung in dieser Reihenfolge angeklickt:

1. Schnauzenspitze
2. Augenmitte
3. Oberer Schwanzflossenansatz am Schwanzstiel
4. Unterer Schwanzflossenansatz am Schwanzstiel
5. Höchster Körperpunkt ohne Rückenflosse
6. Tiefster Körperpunkt ohne Bauch-/Afterflossen

Die Eingabe zeigt den erwarteten Punkt. Nummerierte Bildmarken entsprechen der beschrifteten Legende; bei breiten Ansichten stehen zusätzlich Namen direkt im Bild. **Letzten Punkt entfernen**, **Referenzpunkte zurücksetzen** und **Referenzpunkte bestätigen** erlauben Korrekturen. Nach sechs plausiblen Punkten startet die Bestätigung die Berechnung im Hintergrund. Ein neues Foto oder eine neue Polygonmaske verwirft den aktiven Landmark-Stand einschließlich verspäteter Rechenergebnisse. Bereits gespeicherte Arbeitskopien bleiben auf der Festplatte.

## Koordinaten und Maße

Alle Eingabepunkte bleiben in Originalpixeln (Ursprung oben links, X nach rechts, Y nach unten). Die Anzeige verwendet eine proportional verkleinerte Freistellung des vollständigen Bildrahmens. Es gilt:

`original = (mausposition - angezeigter_bildursprung) / angezeigte_bildgröße * originalgröße`

Leerraum wird nicht als Bild interpretiert. Punkte außerhalb der Maske werden abgewiesen; direkt an der Kontur gilt eine Toleranz von drei Originalpixeln. Die Landmarken werden bei Fenstergrößenänderungen aus den Originalkoordinaten neu gezeichnet.

Der Schwanzstielmittelpunkt `T` ist der Mittelwert der beiden Schwanzansätze, die Schnauze ist `S`. Die Körperachse verläuft von `T` nach `S`:

- `S.x > T.x`: Kopf rechts, andernfalls Kopf links.
- Körperlänge: euklidischer Abstand `|S - T|`, ohne Schwanzflosse.
- Körperhöhe: Abstand zwischen oberem und unterem Körperpunkt senkrecht zur Körperachse.
- Achsenwinkel: `atan2(S.y - T.y, S.x - T.x)` in Grad im Bildkoordinatensystem, positive Werte im Uhrzeigersinn.

Dies sind Näherungen aus manuellen Punkten. Ungültige Anzahlen, doppelte Punkte, vertauschte obere/untere Punkte, ein Auge in der hinteren Körperhälfte sowie eine zu kurze oder nahezu senkrechte Achse werden abgefangen. Anatomische Genauigkeit bleibt von der Eingabe abhängig.

## Normalisierte Arbeitskopie

`u = normalize(S - T)` zeigt immer zum Kopf. Die zweite Basisrichtung ist `v = (-u.y, u.x)` bei Kopf rechts und `v = (u.y, -u.x)` bei Kopf links. Dadurch wird ein links gerichteter Fisch horizontal gespiegelt und anschließend ausgerichtet, ohne Ober- und Unterseite zu vertauschen.

`normalisiert = ((P-T)·u, (P-T)·v) * scale + offset`

Die Körperachse liegt horizontal, der Kopf rechts. Alle Richtungen werden mit demselben Faktor skaliert. Die Arbeitskopie wird nicht hochskaliert; die längste Seite beträgt höchstens 2048 Pixel einschließlich transparentem Rand. Die JSON-Datei enthält Basis, Skalierung und Versatz für die spätere Rückrechnung. Originalfoto und Originalmaske bleiben in voller Auflösung erhalten.

Die PNG wird direkt aus dem Originalfoto und der bestehenden Maske berechnet, nicht aus dem verkleinerten Vorschaubild. Bilineare Abtastung mit vormultipliziertem Alpha verhindert Farbsäume aus vollständig transparenten Hintergrundpixeln. Die vorhandene grobe Polygonkante wird nicht automatisch verbessert.

## Speicherorte und Datenstruktur

- `user://normalized/fish_<Zeit>_<ID>.png`: normalisierte RGBA-Arbeitskopie.
- Gleichnamige `.json`: Version, sechs benannte Originalpunkte, Originalmaße und Pfade, Richtung, Länge/Höhe, Achsenwinkel, Transformationsbasis, Skalierung, Versatz, normalisierte Punkte und Zielbildmaße.
- Windows normalerweise: `%APPDATA%\Godot\app_userdata\Pelvicachromis Studio\normalized\`.
- Intern in `ReferencePhoto.landmarks`: `landmark_data`, `current_landmark_path`, `current_normalized_path`.
- Punktnamen: `snout`, `eye`, `tail_upper`, `tail_lower`, `body_upper`, `body_lower`.

Die Daten sind nach Bestätigung gespeichert; automatisches Wiederladen früherer Sitzungen ist in diesem Schritt nicht vorgesehen.

## Dateien

- `scripts/reference_photo.gd`: Einbindung in Foto-/Maskenlebenszyklus und responsive Anzeige.
- `scripts/landmark_canvas.gd`: Eingabe und Zeichnung in Originalkoordinaten.
- `scripts/reference_landmarks.gd`: Workflow, Validierungsmeldungen, Hintergrundberechnung, Speicherung und Vorschau.
- `scripts/fish_normalizer.gd`: Maße, affine Transformation und RGBA-Bildberechnung.
- `scripts/validate_landmarks.gd`: Godot-Integrationstests.
- `scripts/create_landmark_test_fixtures.py`, `scripts/compose_landmark_diagnostic.py`: ausschließlich Test-/Diagnosewerkzeuge; Python wird von der Anwendung nicht benötigt.
- `godot/diagnostics/landmark_*`: Testergebnisse und Diagnosebilder.

## Tests wiederholen

Zuerst die bestehenden Fotoimport-Testbilder erzeugen, falls sie noch fehlen. Die gespeicherte Fischmaske aus dem Polygon-Test liegt unter `godot/diagnostics/mask_fish_4000x3000.png`.

```powershell
python scripts/create_photo_test_fixtures.py
python scripts/create_landmark_test_fixtures.py
godot --path . --script res://scripts/validate_landmarks.gd
godot --path . --script res://scripts/validate_polygon_mask.gd
godot --path . --script res://scripts/validate_photo_import.gd
godot --path . --script res://scripts/validate_fish_viewer.gd
python scripts/compose_landmark_diagnostic.py
```

Tests verwenden rechts/links gerichtete Fische, beide Neigungsrichtungen, 4000×3000 und 160×120 Pixel, echte Viewport-Mauseingaben, Größenwechsel während der Eingabe, Undo/Reset, Transparenz, gespeicherte JSON-Daten, ungültige Eingaben, veraltete Worker-Ergebnisse und Viewer-Bedienung. Details stehen im JSON-Testbericht.

Ausgangspunkt ist der bereits vorhandene Commit `f657eec`. Fischmodell, UVs, Rig, Animationen und Basistexturen bleiben unverändert; es erfolgt keine Texturübertragung.

## Prüfergebnis

Alle fünf Landmark-Fälle, der bestehende Polygonmasken-Test, der Fotoimport-Test und die Viewer-Regression bestehen ohne Godot-Fehler. Die 15 geschützten Modell-/Blender-/Texturdateien und fünf Test-Originalfotos sind per SHA256 unverändert. Die Testläufe verwenden einen separaten Benutzerordner unter `.godot/test_runtime/`; die produktive Anwendung verwendet den normalen Godot-Benutzerordner.
