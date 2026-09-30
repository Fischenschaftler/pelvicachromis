# Physikalische Bildschirmkalibrierung

## Bedienung

1. Den normalen Viewer auf den gewünschten Präsentationsmonitor verschieben und **F10** drücken. Das separate Setup öffnet sich auf diesem Monitor im Vollbild. Während eines Stimulusversuchs ist es gesperrt.
2. Die tatsächlich sichtbare Bildschirmbreite in Zentimetern eingeben: von linker bis rechter Bildkante, **ohne Rahmen**. Automatische DPI-Angaben werden nicht zur Größenbestimmung verwendet.
3. Die gewünschte **Gesamtlänge des Fisches** einstellen, beispielsweise 5, 6, 7, 8 oder 5.25 cm. Freie Werte in 0.01-cm-Schritten sind möglich.
4. Die 10-cm-Referenzlinie mit einem echten Lineal zwischen den Mitten der beiden Endstriche messen. Die Sollänge der Linie kann geändert werden, falls 10 cm auf einem kleinen Display nicht hineinpassen. Eine zu lange Linie wird nicht heimlich verkleinert.
5. Bei Abweichung den tatsächlich gemessenen Wert eingeben und **Messkorrektur anwenden** drücken. Danach erneut messen. **Kalibrierung speichern** übernimmt das Profil. Esc verwirft ungespeicherte Änderungen und kehrt in den Viewer zurück.
6. **F9** startet den Versuch mit dem ausgewählten Fisch. Ohne gültiges, zum aktuellen Bildschirm passendes Profil wird der Start mit einer Meldung abgewiesen. Esc beendet wie bisher den Versuch.

Die Eingabe einer Bildschirmbreite ist keine automatische physische Messung. Für wissenschaftliche Verwendung muss die Referenzlinie am tatsächlichen Präsentationsmonitor geprüft werden. Der Diagnose-Screenshot ist skaliert dargestellt und selbst kein Maßstab.

## Bildschirm und Pixelmaßstab

Godot liefert Monitorindex, Bildschirmauflösung, Position des Monitors im Desktop, Skalierungsfaktor und Anzahl der Monitore. Im Setup werden zusätzlich die tatsächliche Vollbild-Fenstergröße und die berechneten Pixel/cm angezeigt. Die Skalierung beim Versuch verwendet die reale SubViewport-Auflösung **nach** dem Vollbildwechsel sowie die Ausgabegröße des Fensters.

Seien `Sx` die Bildschirmbreite in Pixeln und `B` die manuell gemessene sichtbare Breite in cm:

```
pixels_per_cm_x = Sx / B * correction_factor
pixels_per_cm_y = pixels_per_cm_x
physical_screen_height_cm = B * screen_pixel_height / Sx
```

Dieser erste Stand nimmt quadratische physische Pixel und eine unverzerrte Monitorausgabe an. Die Höhe wird daraus abgeleitet und als solche gekennzeichnet; sie wird nicht unabhängig gemessen. Stretch-/Overscan-Einstellungen am Monitor müssen passend eingestellt und die Linie erneut geprüft werden. Eine spätere unabhängige Y-Kalibrierung kann an den getrennten X/Y-Umrechnungsfunktionen ansetzen.

DPI-Angaben allein sind unter Windows keine verlässliche physische Messung. OS-Skalierung wird als Änderungssignal gespeichert, aber nicht als reale Bildschirmgröße interpretiert.

## Messkorrektur

Für eine Sollinie `L` cm, die am Bildschirm nur `M` cm misst:

```
new_correction_factor = old_correction_factor * L / M
```

Beispiel: 10.0 / 9.7 = 1.0309278. Die Linie wird um etwa 3.09 % länger. Die ursprünglich eingegebene Bildschirmbreite bleibt im Profil nachvollziehbar; der getrennte Korrekturfaktor beeinflusst die effektiven Pixel/cm. Mehrere Korrekturen sind möglich, immer bezogen auf die aktuell dargestellte Linie. Eine neue Bildschirmbreite setzt die bisherige Korrektur zurück. Null, nicht endliche oder unverhältnismäßige Korrekturwerte werden abgewiesen.

## Orthografische Projektion und Fischgröße

Die Kamera bleibt orthografisch mit KEEP_HEIGHT. Seien `Vw/Vh` die Render-Viewport-Größe, `Ow/Oh` die Ausgabegröße des Fensters und `C` die Camera Size (vertikale Ausdehnung in Weltkoordinaten):

```
render_pixels_per_world_unit = Vh / C
output_pixels_per_world_unit_x = (Vh / C) * (Ow / Vw)
output_pixels_per_world_unit_y = (Vh / C) * (Oh / Vh)
world_units_per_cm = pixels_per_cm_x / output_pixels_per_world_unit_x
world_fish_length = target_fish_length_cm * world_units_per_cm
model_display_scale = world_fish_length / native_model_total_length
```

Im normalen Vollbild entspricht die Ausgabe dem Viewport, also `Pixel/Welteinheit = Vh/C`. Auch eine gleichmäßige Render-Verkleinerung wird rechnerisch berücksichtigt. Eine ungleichmäßige Viewport-Skalierung verhindert den Start. Die Kamera und der berechnete Darstellungsfaktor bleiben während des Versuchs fest.

`display_calibration.gd` stellt `cm_to_world_units()`, `world_units_to_cm()`, `reference_pixels()` und `model_scale()` bereit.

### Längendefinition und Modellmessung

**Total Length:** X-Ausdehnung der geraden, unverformten Mesh-Geometrie von der äußersten Schnauzenspitze bis zum äußersten Ende der Schwanzflosse. Alle vorhandenen Mesh-Surfaces werden einmal je Fischinstanz in dessen lokalen Koordinaten ausgelesen. Weder Bones noch Meshes werden verändert. Die gemessene Länge wird zentral zwischengespeichert; pro Frame findet keine Vertex-/Bounding-Box-Messung statt.

Am aktuellen Modell beträgt die Gesamtlänge ungefähr **0.08008537 Godot-Einheiten**. Die Körperlänge ohne Schwanzflosse wird zusätzlich separat erfasst, aber nicht zur aktuellen Skalierung verwendet. Damit kann später eine andere Längendefinition ergänzt werden. Die alte reine Fish_Body-Skalierung ist abgelöst.

Schwimmbewegung und räumliche Richtungswechsel verkürzen zeitweise die sichtbare Projektion. Die eingestellte Länge beschreibt die gerade Ruheform, nicht eine künstlich pro Frame nachskalierte Silhouette.

## Geschwindigkeiten und Konfiguration

`config/stimulus.json` verwendet nun:

- `speed_cm_s`: 4.0, `min_speed_cm_s`: 1.0, `max_speed_cm_s`: 10.0.
- `speed_adjustment_cm_s2`: 2.5 für R/F.
- `acceleration_cm_s2`: 3.5, `deceleration_cm_s2`: 5.0.

Beim Start werden Geschwindigkeit und Beschleunigung jeweils mit `world_units_per_cm` multipliziert. So entsprechen beispielsweise 5 cm/s derselben physischen Bewegung auf unterschiedlich kalibrierten Monitoren. R/F und das diagonale Geschwindigkeitslimit bleiben erhalten. Swim_Test folgt weiterhin dem Betrag der tatsächlichen Geschwindigkeit.

Die aktive Profilgröße `target_fish_length_cm` aus F10 ist maßgeblich und wird in die Laufkonfiguration als `fish_display_length_cm` übernommen. Änderungen an der gewünschten Länge bitte im Setup vornehmen. Die Laufkonfiguration enthält zusätzlich Bildschirmbreite/-höhe, Pixel/cm, Kalibrierzeitpunkt und Version. Die vollständige Konfiguration wird für jeden Versuch eingefroren und protokolliert.

Bestehende nominale Konfigurationen werden beim Lesen im Speicher migriert: alte Geschwindigkeiten in Welt/s werden durch das frühere `units_per_cm` geteilt (Standard 0.01), um cm/s zu erhalten. Alte Dateien werden dabei nicht ungefragt überschrieben. Ein altes Größenverhältnis gilt ausdrücklich nicht als gültige Bildschirmkalibrierung; F10 muss zuerst durchgeführt werden.

## Persistenz und Monitorwechsel

Die Kalibrierung liegt ausschließlich unter **`config/display_calibration.json` neben der portablen EXE**. Im Entwicklungsmodus: `dev_portable_data/config/display_calibration.json`. Kein Fischprojekt enthält diese Daten.

```
{
  "version": 1,
  "active_profile": "Display_01",
  "profiles": {
    "Display_01": {
      "calibration_version": 1,
      "calibration_timestamp": "…Z",
      "screen_pixel_width": 2560,
      "screen_pixel_height": 1440,
      "physical_screen_width_cm": 60.0,
      "physical_screen_height_cm": 33.75,
      "height_method": "inferred_square_pixels",
      "pixels_per_cm_x": 42.6666667,
      "pixels_per_cm_y": 42.6666667,
      "correction_factor": 1.0,
      "target_fish_length_cm": 8.0,
      "monitor": { "…": "Identifikationsdaten" }
    }
  }
}
```

Das Beispiel enthält fiktive Maße. Ein aktives Profil wird unterstützt; weitere Profile können künftig über eine Auswahloberfläche zugänglich gemacht werden. Bereits enthaltene andere Profile bleiben beim Speichern erhalten. Schreiben erfolgt über eine temporäre Datei und anschließenden Austausch.

Vor dem Start werden Monitorindex, Monitoranzahl, Desktopposition, Auflösung und OS-Skalierung verglichen; nach dem Vollbildwechsel wird erneut geprüft. Änderungen während eines Laufs beenden diesen mit Protokollgrund `monitor_changed` beziehungsweise `window_resized`. Änderungen im Kalibrierungssetup verlangen eine neue Breitenangabe.

**Grenze der Erkennung:** Godots DisplayServer liefert hier keine Hardware-Seriennummer. Ein Austausch durch einen anderen Monitor bei identischem Index, identischer Position, Auflösung und Skalierung ist deshalb nicht automatisch unterscheidbar. Nach einem physischen Monitorwechsel muss die Linie erneut mit einem Lineal geprüft werden, auch wenn keine Warnung erscheint.

## Logging und Diagnose

Die bestehenden JSONL-Versuchslogs unter `data/experiments/` enthalten zusätzlich:

- Vollständiges Kalibrierprofil inklusive Monitorauflösung, gemessener Breite, abgeleiteter Höhe, Pixel/cm, Korrekturfaktor, Zeitstempel und Version.
- Ziellänge in cm, native Modell-Gesamtlänge, Darstellungsfaktor und Welt/cm.
- Anfangsgeschwindigkeit in cm/s sowie pro Stichprobe tatsächliche Geschwindigkeit, Sollgeschwindigkeit und Position in cm zusätzlich zu den Weltkoordinaten.

Das F10-Setup ist zugleich Diagnosemodus: Referenzbalken, Pixel/cm, Viewportauflösung, Camera Size, Modelllänge, berechnete Weltlänge und Skalierungsfaktor. Im echten Stimulusbild bleibt es unsichtbar.

## Tests und Grenzen

`Godot --headless --path . --script res://scripts/stimulus/run_calibration_validation.gd` prüft die reinen Formeln, mehrere Auflösungen/Breiten, 5/8 cm, Messkorrektur, cm/s und Profilpersistenz. Ohne `--headless` folgen Vollbild-Setup, Messung der tatsächlich gerenderten Linienpixel, Kamera-Projektion, F10/Esc, Monitorwarnung, Logging und die vollständige Stimulus-Regressionssuite. Ein separat exportierter Windows-Testbuild führt dieselben Prüfungen aus.

Testmaße sind ausdrücklich synthetisch und werden nur in Testdateien gespeichert, niemals als gültiges Benutzerprofil ausgeliefert. Eine reale Zentimeterprüfung mit Lineal kann die Software nicht selbst durchführen. Andere Grenzen: quadratische Pixel angenommen; keine Hardware-Erkennung identischer Monitorkonfigurationen; kein Ausgleich für optische Brechung durch Aquarienscheiben/Wasser und keine winkelabhängige Größenkorrektur. Maßgeblich ist zunächst die Bildschirmoberfläche.
