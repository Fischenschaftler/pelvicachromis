# Referenzfoto im Viewer

Start: project.godot mit Godot 4 öffnen, F5. **Fischfoto auswählen** öffnet einen Godot-Dateidialog mit Zugriff auf das Windows-Dateisystem. Unterstützt: JPG/JPEG, PNG, WEBP. **Foto entfernen** stellt den fensterfüllenden Viewer wieder her.

## Implementierung

`scripts/reference_photo.gd` am Knoten `Main/UI/ReferencePhoto` verwaltet Dialog, Vorschau, Metadaten und Fehler. `current_photo_path` enthält den vollständigen, vereinfachten Dateipfad des erfolgreich geladenen Fotos. `original_size` enthält die Originalabmessungen. Beide Werte sind nur im Speicher dieser Sitzung; beim Entfernen werden sie geleert. Fehler beim Ersetzen lassen das bisherige Foto unverändert.

Dateien werden nur lesend per FileAccess geöffnet und anhand ihrer Endung und Signatur geprüft. Der passende Godot-Decoder erzeugt ein Image. Für die Anzeige wird dessen längste Kante auf höchstens 2048 Pixel reduziert; die Originaldatei wird niemals geschrieben. TextureRect verwendet KEEP_ASPECT_CENTERED und verändert das Seitenverhältnis nicht. Dateiname und ursprüngliche Breite/Höhe stehen unter dem Foto. Sehr lange Dateinamen werden mit Ellipse gekürzt; der Tooltip enthält den ganzen Namen. Ein einzelnes Foto darf höchstens 64 MB Dateigröße haben. Decodierung erfolgt synchron; sehr große Bilder können deshalb kurz Ladezeit verursachen.

Der 3D-Inhalt liegt unverändert unter `Main/ViewerViewport/Viewport/World`. Ohne Foto füllt dieser SubViewport das Fenster. Mit Foto werden Foto und Fisch nebeneinander angeordnet, in schmalen hohen Fenstern untereinander. Kleine Querfenster behalten zwei kompakte Bereiche. Die UI erhält Eingaben zuerst; nur übrige Mausereignisse im Viewer-Rechteck werden an die Orbit-Kamera weitergegeben. Ein Loslassen über UI beendet einen begonnenen Kamera-Drag.

Keine Analyse, Segmentierung, Texturerzeugung oder Änderungen am Fischmodell.

## Dateien

Geändert: `scenes/Main.tscn`, `scripts/fish_viewer.gd`, `scripts/orbit_camera.gd`, `scripts/validate_fish_viewer.gd`.

Neu: `scripts/reference_photo.gd` (Godot erzeugt .uid), `scripts/validate_photo_import.gd`, `scripts/create_photo_test_fixtures.py`, diese Dokumentation. Testberichte/Logs und Screenshots unter `godot/diagnostics/photo_import_*`; die Viewer-Diagnosebilder wurden aktualisiert. Temporäre Testbilder liegen ausschließlich im ignorierten `.godot/photo_import_fixtures/`.

## Prüfungen

- Dateidialog über den Auswahlbutton geöffnet; Auswahl über dessen Bestätigungsbutton und das echte file_selected-Signal geladen.
- JPG 4000×3000 -> Vorschau 2048×1536, Originalmetadaten erhalten.
- PNG 600×1000, JPEG 80×60, WEBP 900×500.
- Defekte PNG-Signatur und fehlende Datei: verständlicher Dialog, vorheriges Foto erhalten.
- Fenster 1280×800, 600×900, 480×360: Bildbereich und UI innerhalb des Fensters, keine Überdeckung des Viewers durch das Foto.
- Maus-Orbit, Zoom, Reset und Pause/Fortsetzen mit Foto; bisheriger vollständiger Viewer-Test ohne Foto inklusive Loop und Zoom-/Winkelgrenzen.
- Entfernen leert Textur/Pfad/Metadaten und stellt den vollen 3D-Bereich wieder her.
- Finale GPU-Läufe unter Godot 4.7.2 / D3D12 ohne Fehler oder Warnungen; Diagnosebilder visuell geprüft.
- SHA256-Vergleich: Modell-/Blender-Dateien, GLB, bestehende Texturen und die Test-Originaldateien unverändert.

Wiederholung (Python benötigt Pillow; die Anwendung selbst benötigt kein Python):

```powershell
python scripts/create_photo_test_fixtures.py
godot --path . --script res://scripts/validate_photo_import.gd
godot --path . --script res://scripts/validate_fish_viewer.gd
```

Noch nicht umgesetzt: EXIF-basierte automatische Drehung, dauerhafte Speicherung der Auswahl, Bildanalyse und Bearbeitung. Kein Commit oder Push in diesem Schritt.
