# Prototyp: Fotofärbung auf Kopf und Körper

## Bedienung

Foto laden → Polygonmaske → sechs Referenzpunkte → bestätigen. Danach **Färbung auf 3D Fisch übertragen** anklicken. Die Berechnung läuft in einem Thread; Kamera und Animation bleiben bedienbar. Nach erfolgreicher Speicherung wird die neue Textur automatisch angezeigt.

**Originalfärbung** stellt den unveränderten importierten Körperwerkstoff wieder her. **Generierte Färbung** zeigt die zuletzt erzeugte Arbeitskopie. Entfernen des Fotos stellt ebenfalls die Originalfärbung her. Ein neues Foto behält die letzte erzeugte Textur als umschaltbare Variante; veraltete Berechnungen werden verworfen, wenn sich die bestätigten Referenzpunkte währenddessen ändern.

## UV-Zuordnung: vorhandene Daten, keine neue Abwicklung

`scripts/extract_body_projection.py` öffnet die aktuelle Blender-Datei ausschließlich lesend. Es gibt keinen Aufruf zum Speichern, Modellieren, Unwrappen oder Exportieren. Das Script liest die Ruhegeometrie von **Fish_Body**, dessen aktive **PhotoUV**, Objektmatrix und die projizierten Flossenumrisse.

`data/body_projection.json` enthält 5520 tatsächliche UV-Dreiecke mit den zugehörigen seitlichen Ruhekoordinaten. Der Körper ist dadurch eindeutig über den Objektnamen zugeordnet; es werden keine UV-Rechtecke geraten. Die Dokumentation und vorhandene UV-Prüfung bestätigen:

| Körperinsel | U | V in Blender |
| --- | --- | --- |
| Left (+Y), einschließlich Kopf | 0,02–0,70 | 0,67–0,98 |
| Right (-Y), einschließlich Kopf | 0,02–0,70 | 0,34–0,65 |
| Schwanzstiel-Abschluss | 0,77–0,85 | 0,18–0,27 |
| Schnauzen-Abschluss | 0,89–0,97 | 0,18–0,27 |

Die Rasterisierung nutzt ausschließlich echte Dreiecksflächen innerhalb dieser Inseln. Für PNG-Koordinaten wird V zu `1-V`. GLB- und Blender-SHA256 sind dokumentiert; die Anwendung prüft vor der Generierung den GLB-Hash gegen die Zuordnung.

## Abbildung des Fotos

Die sechs Modellreferenzen werden aus der bestehenden Ruhegeometrie abgeleitet: Schnauzenringmitte, Augenobjekt-Ursprung, oberer/unterer hinterer Körperring, höchster Rückenpunkt und tiefster Punkt im mittleren Körperbereich. Letzterer wird bewusst nicht vom gleich hohen Schwanzabschluss genommen.

Eine **Thin-Plate-Spline-Abbildung mit sechs Kontrollpunkten** ordnet diese Modellpunkte den gespeicherten Landmarken in der normalisierten PNG zu. Die Abbildung ist glatt und nicht auf eine Skalierung des Foto-Rechtecks beschränkt. Sie registriert insbesondere das Auge getrennt von Schnauze und Körperumriss. Faltungen der seitlichen Körperdreiecke werden erkannt und abgewiesen.

Jeder vorhandene UV-Dreieckspunkt wird über seine zugehörige Ruheposition in das normalisierte Foto abgebildet. Innerhalb der kleinen Mesh-Dreiecke werden die Abtastpositionen baryzentrisch interpoliert. Dadurch folgt die Belegung dem vorhandenen UV-Layout einschließlich der verjüngten Rücken-, Bauch- und Schwanzbereiche. Geometrie und UVs werden nicht verändert.

Der verformte Körperumriss bildet eine anatomische **Körpermaske**. Die ebenfalls registrierten projizierten Flossenflächen werden konservativ ausgespart, insbesondere überlagerte Brustflossen. Die Aussparungen besitzen einen körperhöhenabhängigen Sicherheitsrand (bei Brustflossen seitlich/unten 25 %, nach oben 3,5 %, bei den übrigen Flossen 4 %). Diese Maske wird mit der Alpha-Maske der normalisierten Arbeitskopie geschnitten. Bei bilinearer Abtastung müssen alle vier Quellpixel innerhalb der gültigen Körpermaske liegen. Hintergrundfarben und transparente Bildränder werden dadurch nicht übernommen. Nicht belegbare Pixel behalten die Basistextur.

Für diesen Prototyp wird dieselbe sichtbare Fotoseite auf beide getrennten Körperinseln verwendet. Die nicht fotografierte Gegenseite wird damit angenähert; sie ist keine Rekonstruktion ihrer individuellen Zeichnung.

## Erhaltung von Modell und Materialien

Die neue 4096×4096-PNG beginnt als Kopie der vorhandenen Basistextur. Nur gültig belegte Körpertexel werden ersetzt; die übrigen Atlaspixel bleiben bytegleich. Die ursprüngliche PNG und GLB werden nie überschrieben.

In Godot erhält ausschließlich **Fish_Body** lokale Kopien seiner Materialien als Surface-Overrides. Das gemeinsame Mesh und seine gespeicherten Materialien bleiben unangetastet. Alle Flossen sowie die separaten Augen- und Mundobjekte behalten ihre ursprünglichen Materialien. Das Fotoauge wird auf die Position des vorhandenen Auges registriert; dessen separate Iris-/Pupillentextur bleibt in diesem Schritt original.

Mipmap-Stufen werden nur für die temporäre GPU-Textur erzeugt. Sie vermindern Flimmern in kleinen Viewer-Ansichten.

## Speicherung

`user://generated_textures/body_<Zeit>_<ID>` mit folgenden Endungen:

- `.png`: neue vollständige Atlastextur
- `_body_mask.png`: tatsächlich verwendete Quell-Körpermaske
- `_uv_coverage.png`: tatsächlich neu belegte Atlastexel
- `.json`: Eingabepfade, Methode, Belegungsstatistik und Zieltexturpfad

Windows normalerweise: `%APPDATA%\Godot\app_userdata\Pelvicachromis Studio\generated_textures\`.

Intern: `ReferencePhoto.texture_transfer.current_generated_path`, `current_body_mask_path`, `current_coverage_path`, `current_metadata_path` und `last_stats`. Die letzte Variante bleibt während der Sitzung umschaltbar; ein automatisches Wiederladen nach Programmneustart ist noch nicht vorgesehen. Die Tests verwenden `.godot/test_runtime/` als isolierten Benutzerordner.

## Grenzen dieses Prototyps

- Sechs Punkte liefern eine globale anatomische Registrierung; lokale Zeichnung und Schuppenrichtung stimmen noch nicht überall exakt überein.
- Unter überlagernden Flossen und außerhalb sicherer Maskenflächen bleibt die bisherige Körperfärbung sichtbar. An diesen Übergängen können Farb- und Zeichnungssprünge auftreten.
- Eine seitliche Aufnahme enthält keine vollständige Information für Rücken-/Bauchmitte. Schräg betrachtet bleiben dort Verzerrungen und sichtbare Übergänge möglich.
- Beleuchtung und Reflexe im Foto werden übernommen; es findet keine neue Entleuchtung statt.
- Augen, Mund und Flossen behalten ausdrücklich die Originalfärbung. Die dunkle Bauch-/Flossenansatzlinie ist auch in der Originalansicht vorhanden.

## Tests und Diagnose

`scripts/validate_body_transfer.gd` bedient die echte Godot-UI: 4000×3000-Foto laden, Polygon setzen, sechs Landmarken setzen, normalisieren, übertragen, umschalten und Viewer bedienen. Es prüft unveränderte Mesh-Arrays und Nicht-Körpermaterialien, 15 Bones, Swim_Test-Loop, Fenstergrößen bis 480×360, Zoom/Reset sowie das Verwerfen überholter Berechnungen.

`scripts/validate_body_projection.gd` prüft zusätzlich links gerichtete, geneigte und kleine normalisierte Fotos. Transparente Pixel werden absichtlich magenta eingefärbt: Sie dürfen nicht in die Körpertextur gelangen.

`scripts/compose_body_diagnostic.py` prüft pixelweise, dass außerhalb der Belegungsmaske und in allen Flossen-UV-Slots keine Änderungen auftreten. Zusätzlich prüft es die vorhandenen 15 geschützten Dateien per SHA256 und erstellt `godot/diagnostics/body_transfer_comparison.png` mit normalisierter Referenz, Körpermaske, neu belegten UV-Flächen und beiden Materialien aus Seiten- und Schrägansicht.

Die vollständigen Testläufe benötigen die vorhandenen Foto-/Landmark-Testdaten. Aus dem Projektordner:

```powershell
godot --path . --script res://scripts/validate_body_transfer.gd
godot --headless --path . --script res://scripts/validate_body_projection.gd
python scripts/compose_body_diagnostic.py
```

Die statischen JSON-Zuordnungsdaten müssen bei einem späteren Windows-Paketexport mit eingepackt werden. Ein finaler Windows-Paketexport gehört nicht zu diesem Prototypschritt.

Ausgangspunkt: Commit `87abbb1` (Landmarks und Normalisierung). Keine Änderungen gepusht.

## Ergebnis des geprüften Standes

Der vollständige UI-Ablauf und die drei zusätzlichen Projektionsfälle bestehen ohne Godot-Fehler oder Warnungen. Im 4096×4096-Testatlas wurden 2.733.463 Texel verändert; außerhalb der Belegungsmaske und in allen sieben Flossen-Slots jeweils null. Alle 15 geschützten Dateien sind unverändert. Die maximale rechnerische Landmark-Abweichung beträgt rund 0,00014 Pixel; dies beschreibt die Kontrollpunktregistrierung, nicht die anatomische Genauigkeit der gesamten Oberfläche.
