# Lokale Foto-Projekte

## Bedienung

- **Projekt speichern** speichert den aktuellen Entwurf oder fertigen Fisch. Beim ersten Speichern wird ein Name abgefragt. Später aktualisiert derselbe Button das aktive Projekt.
- **Speichern unter** erzeugt eine unabhängige Projektkopie mit neuer Kennung.
- **Projekt öffnen** zeigt Name, fotografierte Seite und Änderungszeit. Auswahl und **Öffnen** oder Doppelklick lädt das Projekt. Ungespeicherte Änderungen vorher speichern; Öffnen ersetzt den aktuellen Arbeitsstand erst nach erfolgreicher Prüfung.
- **Projekt löschen** im Browser fragt nach und verschiebt das Projekt in den lokalen Projekt-Papierkorb.
- **Zurücksetzen** leert nur den aktiven Editor und stellt Originalmaterialien wieder her. Gespeicherte Projekte bleiben bestehen.

Auch Entwürfe ohne alle zwölf Punkte oder ohne fertige Maske/Textur können gespeichert werden. Bei abgeschlossener Maske muss das Polygon gültig sein. Während einer laufenden Texturberechnung ist Speichern deaktiviert. Bereits erzeugte Texturen bleiben speicherbar, auch wenn danach Punkte geändert wurden; aktuelle Ausrichtungsdaten und Daten der letzten Texturerzeugung sind getrennt abgelegt.

Es bleibt bei **genau einem Foto pro Fischprojekt**. Die fotografierte linke/rechte Seite wird gespeichert. Die bisherige gespiegelte Gegenseite und der Fallback für paarige Flossen bleiben unverändert.

## Speicherort und Dateistruktur

Standard: `user://projects/`, unter Windows normalerweise:

`%APPDATA%\Godot\app_userdata\Pelvicachromis Studio\projects\`

```text
projects/
  <32-stellige Projekt-ID>/
    project.json
    project.json.bak                 # Metadaten des vorherigen Speicherstands
    photo_<Speicher-ID>.png           # interne verlustfreie Kopie der geladenen Pixel
    mask_<Speicher-ID>.png            # falls eine geschlossene Maske existiert
    generated_albedo_<Speicher-ID>.png # falls eine generierte Textur existiert
    ... ältere Bildrevisionen ...
  .trash/
    <Projekt-ID>_<Zeit>/              # bestätigte Löschungen
```

Dateinamen tragen eine zufällige Speicherkennung. Damit werden die Bilddateien eines bestehenden Speicherstands nicht überschrieben, während ein neuer gespeichert wird. `project.json` verweist ausschließlich auf die jeweils aktuellen Dateien. Der Anzeigename wird niemals als Dateipfad benutzt.

Die Originaldatei wird nicht verändert. Die PNG-Fotokopie enthält die geladenen Bildpixel in Originalauflösung; ursprüngliche JPEG-Kompression, EXIF und andere Metadaten werden nicht als Originaldatei archiviert. Zum Öffnen wird nur die interne Kopie benötigt. Der ursprünglich gewählte Pfad ist ein Hinweis, keine Ladeabhängigkeit.

## Projektformat Version 1

Beispiel (Punktlisten gekürzt):

```json
{
  "project_format_version": 1,
  "id": "0123456789abcdef0123456789abcdef",
  "name": "Mein Taeniatus",
  "created_at": "2026-09-28T12:00:00Z",
  "updated_at": "2026-09-28T12:10:00Z",
  "photographed_side": "left",
  "resolution": 2048,
  "photo_path": "photo_abcdef0123456789.png",
  "original_photo_path": "D:/Fotos/fisch.jpg",
  "landmark_points": [[735, 295], [670, 275]],
  "mask_points": [[60, 220], [780, 220], [780, 640], [60, 640]],
  "mask_closed": true,
  "mask_path": "mask_abcdef0123456789.png",
  "generated_texture_path": "",
  "transform_data": {},
  "generation_data": {},
  "ui_state": {"mode": "landmarks", "showing_generated": false}
}
```

- Zeitstempel sind UTC.
- `landmark_points`: null bis zwölf Originalpixel-Punkte in der Reihenfolge des Importeditors.
- `mask_points`: bearbeitbare Polygonkontur in Originalpixeln; auch offene Entwürfe bleiben erhalten. `mask.png` ist die daraus berechnete Maske in Originalauflösung.
- `transform_data`: bei gültiger vollständiger Ausrichtung berechnete Transformationsgewichte, Zielpunkte, Körperachse und Schwanzmittelpunkt. Sonst ein leeres Objekt. Vektoren sind JSON-Zahlenpaare.
- `generation_data`: Informationen der letzten erfolgreichen Texturerzeugung, unabhängig von späteren Punktänderungen. Eventuelle alte Arbeitsdateipfade darin sind rein informativ; das Projekt lädt ausschließlich seine oben genannten internen Assets.
- `ui_state`: aktueller Bearbeitungsmodus und aktive Original-/generierte Färbung.
- `resolution`: Einstellung für die nächste Texturerzeugung. Eine bereits vorhandene Textur kann noch die vorherige Auflösung besitzen.
- Optionale Assetpfade sind leer, wenn noch keine entsprechende Datei existiert.

Unbekannte zusätzliche Metadaten sind möglich; inkompatible Formatversionen werden abgelehnt. Assetpfade müssen einfache relative PNG-Dateinamen sein. Absolute Pfade und Verzeichniswechsel werden nicht akzeptiert.

## Speichern und Wiederherstellen

Die Verwaltung schreibt zuerst neue Bildrevisionen. Anschließend wird die vollständig geschriebene und geschlossene `project.json.tmp` aktiviert. Vorherige Metadaten werden als `.bak` erhalten. Scheitert die Umschaltung, wird der bisherige Stand zurückgestellt. Fehlt nach einer unterbrochenen Umschaltung die Hauptdatei, kann die vorhandene `.bak` geladen werden. Ein beschädigtes vorhandenes JSON wird ausdrücklich gemeldet und nicht stillschweigend ersetzt.

Beim Öffnen werden Format, Typen, Pfade, Koordinaten, Foto und geschlossene Polygonkontur geprüft, bevor der aktuelle Editor verändert wird:

- Fehlendes/beschädigtes Foto oder ungültige Metadaten: Laden bricht ab, bisheriger Arbeitsstand bleibt erhalten.
- Fehlende/beschädigte Maskendatei: verständliche Warnung; die gespeicherte Polygonkontur wird wiederhergestellt. Beim nächsten Speichern oder Erzeugen wird daraus wieder eine Maske aufgebaut.
- Fehlende/beschädigte Textur: Warnung und Originalfärbung. Foto und Markierungen bleiben nutzbar.
- Vorhandene Textur: unmittelbar wieder als Materialüberschreibung verfügbar. War die generierte Färbung aktiv, erscheint sie direkt; andernfalls bleibt die Originalfärbung sichtbar und die generierte Variante umschaltbar.

Das Rig wird nicht neu geladen oder aufgebaut. `Swim_Test`, Kamera und Skinning arbeiten weiter. Reset und Laden entwerten bereits laufende Texturberechnungen, damit ein altes Ergebnis den neuen Arbeitsstand nicht überschreibt.

## Architektur

- `scripts/project/project_data.gd`: Version, JSON-Datenprüfung und Punkt-/Vektorkonvertierung.
- `scripts/project/project_manager.gd`: Projektliste, Speichern, Laden, interne Assets, Sicherung und Papierkorb; ohne Viewer-/UI-Abhängigkeit.
- `scripts/project/project_browser.gd`: Liste, Namensdialog und Löschbestätigung.
- `scripts/photo_import/photo_import_controller.gd`: Übergabe des aktuellen Zustands und Anwendung geladener Daten/Materialien.

Keine neue Szene und keine externe Laufzeitabhängigkeit. Die bestehende `PhotoImport.tscn` verwendet den erweiterten Controller.

## Tests und Grenzen

`validate_project_storage.gd` verwendet einen isolierten Ordner unter `user://project_storage_tests/`. Es prüft Entwurf, Überschreiben, Speichern unter, Landmark-Koordinaten, Masken- und Textur-Pixel, beide Farbmodi, fehlende Dateien, kaputtes JSON, inkompatible Versionen, unsichere Pfade, ungültige Punkte, Metadaten-Sicherung, bestätigtes Löschen, Reset, Swim_Test, 15 Bones, Kamera, Zoom und Fenstergrößen.

Ergebnisse: `godot/diagnostics/project_storage_validation.json`, `project_browser.png`, `project_loaded.png`.

Bekannte Grenzen:

- Kein Autosave und kein automatisches Öffnen beim Programmstart. Unbestätigte Änderungen gehen beim Schließen der Anwendung verloren.
- Keine Cloud, Datenbank, Mehrbenutzer- oder Mehrfoto-Funktion.
- Ältere Bildrevisionen und Papierkorb werden nicht automatisch bereinigt; wiederholtes Speichern großer Texturen benötigt zusätzlichen Platz. Wiederherstellung aus dem Papierkorb erfolgt vorerst manuell durch Zurückverschieben des vollständigen Ordners unter seine ursprüngliche Projekt-ID.
- Speichern/Laden erfolgt synchron; bei sehr großen Bildern kann eine kurze Pause auftreten.
- Die Metadaten-Umschaltung schützt vor gemischten Speicherständen, ersetzt aber keine externe Sicherung gegen Datenträgerausfall.
- Frühere Arbeitsdateien unter `user://photo_import/` werden nicht automatisch als Projekte importiert. Ein aktuell geladener Arbeitsstand kann über **Projekt speichern** übernommen werden.
- Kamerawinkel und Animations-Abspielposition werden nicht gespeichert. Die aktuelle Viewer-Sitzung läuft beim Projektwechsel weiter.
