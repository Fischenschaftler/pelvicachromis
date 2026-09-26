# Interaktive Polygonfreistellung

## Bedienung

1. Viewer mit F5 starten und ein Foto laden.
2. Unter dem Foto **Fisch markieren** wählen.
3. Mit linken Mausklicks die Fischkontur setzen; gelbe Punkte und Linien zeigen den Verlauf.
4. Mit Doppelklick am letzten Punkt oder **Kontur schließen** abschließen.
5. Die zusätzliche Vorschau zeigt den Fisch mit transparentem Hintergrund auf dem neutralen Panel.
6. **Markierung zurücksetzen** verwirft Punkte, Vorschau und aktiven Maskenpfad. **Fisch markieren** beginnt ebenfalls eine neue Kontur.

In kleinen Fenstern ist das Foto-/Markierungsfeld scrollbar. Ein Start der Markierung scrollt zum Foto zurück. Viewer-Steuerung und Fotobereich sind getrennt: Konturklicks drehen die Kamera nicht. Der Viewer läuft auch während der Maskenberechnung weiter.

## Daten und Speicherort

Die Auswahl ist eine manuelle Polygonmaske, keine automatische Fisch-/Flossenerkennung. Linien zwischen den gesetzten Punkten sind gerade. Das Ergebnis folgt der gesetzten Kontur; eine grobe Kontur kann deshalb Hintergrundreste enthalten oder Flossen beschneiden. Keine Texturübertragung.

- `Main/UI/ReferencePhoto.original_image`: unverändertes Originalbild im Speicher.
- `ReferencePhoto.picture.points`: Punkte als Gleitkomma-Koordinaten im Originalbild, Ursprung oben links.
- `ReferencePhoto.mask_image`: binäre L8-Maske in Originalauflösung, 255 innerhalb / 0 außerhalb.
- `ReferencePhoto.current_mask_path`: absoluter Pfad zur zuletzt erfolgreich erzeugten Maskendatei.
- `ReferencePhoto.current_photo_path`: vollständiger Pfad zum zugehörigen Originalfoto.

Masken werden unter `user://masks/fish_mask_<Zeit>_<Laufzeit>.png` gespeichert. Auf Windows normalerweise:

`%APPDATA%\Godot\app_userdata\Pelvicachromis Studio\masks\`

Die Testläufe verwenden ein separates APPDATA-Verzeichnis im ignorierten `.godot/test_runtime/`. Die Anwendung erzeugt je Abschluss eine neue Maskendatei. Reset oder Fotowechsel leeren den aktiven Pfad; bereits gespeicherte Dateien bleiben erhalten. Die letzte Auswahl wird noch nicht über Programmstarts wiederhergestellt.

Die Quelldatei wird niemals geschrieben. Die zusätzliche RGBA-Vorschau erhält Alpha 0 außerhalb der Maske. Nur diese Vorschau wird auf höchstens 1600 Pixel Kantenlänge reduziert und auf den Fischbereich mit transparentem Rand zugeschnitten. Die PNG-Maske bleibt immer exakt so groß wie das Originalfoto.

## Koordinatenumrechnung

`TextureRect` zeigt das Foto mit erhaltenem Seitenverhältnis. Aus Texturgröße und Control-Größe wird das tatsächlich gezeichnete Rechteck inklusive Randflächen ermittelt:

```
Skalierung = min(Controlbreite / Texturbreite, Controlhöhe / Texturhöhe)
Anzeigemaße = Texturmaße * Skalierung
Rand = (Controlmaße - Anzeigemaße) / 2
Originalpunkt = (lokaler Klick - Rand) / Anzeigemaße * Originalmaße
Anzeigepunkt = Rand + Originalpunkt / Originalmaße * Anzeigemaße
```

Klicks außerhalb des gezeichneten Fotos werden ignoriert. Punkte werden in Originalkoordinaten gespeichert und beim Zeichnen jeweils neu auf den aktuellen Bildbereich abgebildet. Damit bleiben sie beim Resize und Scrollen stabil; auch die auf 2048 Pixel verkleinerte Anzeigeauflösung geht nicht in die Maskenauflösung ein.

## Validierung und Berechnung

Mindestens drei verschiedene Punkte, gültige Fläche, keine Selbstkreuzungen und keine Punkte außerhalb des Originals. Unvollständige oder ungültige Konturen zeigen einen Hinweis und erzeugen keine Maskendatei. Nahe aufeinanderfolgende Doppelklickpunkte werden nicht doppelt übernommen. Ein wiederholter Endpunkt am Start wird entfernt. Maximal 512 Punkte pro Kontur.

Ein Worker-Thread rasterisiert die Fläche zeilenweise anhand der Pixelzentren. Damit werden sowohl konvexe als auch konkave einfache Polygone unterstützt. Erst eine vollständig erzeugte und erfolgreich gespeicherte Maske erhält einen aktiven Pfad. Die UI übernimmt Thread-Ergebnisse nur, wenn die Foto-/Markierungsrevision noch aktuell ist. Ein Foto-Wechsel oder Reset während der Berechnung verwirft das alte Ergebnis zuverlässig. Auf Dateisystem-/Speicherfehler folgt ein verständlicher Statushinweis.

## Dateien

Neu:

- `scripts/photo_polygon.gd`: Eingabe, Originalkoordinaten, Konturzeichnung.
- `scripts/polygon_mask.gd`: Polygonprüfung, Rasterisierung, transparente Vorschau.
- `scripts/validate_polygon_mask.gd`: automatisierter GPU-/Eingabe-/Pixeltest.
- `scripts/compose_mask_diagnostic.py`: Vergleichstafel aus Original, tatsächlichen Punkten und generierter Maske (Pillow nur für Diagnosen).
- `docs/POLYGON_MASK.md` und Diagnosebilder/Logs/JSON unter `godot/diagnostics/mask_*` sowie `photo_mask_comparison.png`.

Geändert: `scripts/reference_photo.gd` integriert Buttons, Vorschau, Worker und Speicherung; `scripts/validate_fish_viewer.gd` kann für UI-Tests Buttons in Scrollbereichen sichtbar machen. Bestehende Foto-/Viewer-Diagnosebilder wurden aktualisiert. Godot erzeugt zu neuen GDScripts .uid-Dateien.

## Durchgeführte Tests

Godot 4.7.2 auf GPU/D3D12:

- JPG 4000×3000 in verkleinerter Anzeige: geklicktes Rechteck von (800,600) bis (3200,2400). Gespeicherte Maske exakt 4000×3000; Kantenpixel und **4.320.000 weiße Pixel** exakt geprüft.
- Fenster zwischen dem zweiten und dritten Punkt geändert: gespeicherte Originalpunkte unverändert.
- PNG 600×1000 und JPEG 80×60: Maskenauflösung und Innen-/Außenpunkte geprüft.
- Doppelklick und Schaltfläche zum Schließen, Klick auf leere Bildränder, unvollständige Kontur, kollineare Punkte, selbstkreuzendes Polygon, Reset, Entfernen, Foto-Wechsel und veraltetes Worker-Ergebnis geprüft.
- Transparenz außerhalb der Kontur und deckende Pixel innerhalb geprüft.
- Große Ansicht 1600×1100, schmales Hochformat 600×900, kleines Fenster 480×360: Panel innerhalb des Fensters, Bedienung per Scrollen; Screenshots kontrolliert.
- Vorhandene Fotoimport- und Viewer-Tests vollständig erneut ausgeführt, inklusive Kamera, Zoomgrenzen, Reset, Pause/Fortsetzen und Loop. Finale Läufe ohne Godot-Fehler oder Warnungen.
- SHA256: 15 geschützte Modell-/Blender-/Texturdateien und fünf Test-Originaldateien unverändert.

Wiederholung vom Projektordner:

```powershell
python scripts/create_photo_test_fixtures.py
godot --path . --script res://scripts/validate_polygon_mask.gd
godot --path . --script res://scripts/validate_photo_import.gd
godot --path . --script res://scripts/validate_fish_viewer.gd
python scripts/compose_mask_diagnostic.py
```

Der vorab verlangte Sicherungscommit ist `6a5e10f` (Checkpoint stable viewer and reference photo import).
