# Portable Windows-Version

Pelvicachromis Studio speichert reguläre Arbeitsdaten ausschließlich lokal im
Programmordner. Keine Installation, Registry-Einträge oder Dienste. Keine
Umleitung nach AppData bei fehlenden Schreibrechten.

## Ordnerstruktur

```text
PelvicachromisStudio/
  PelvicachromisStudio.exe   # eingebettetes PCK
  projects/                # Projektordner mit project.json und PNG-Kopien
  data/                    # Arbeitsmasken, Normalisierung, erzeugte Atlanten
  config/                  # reserviert für spätere Einstellungen
  logs/studio.log          # Startprotokoll, Rotation bei 1 MiB
```

Die zentrale Komponente `scripts/storage/portable_paths.gd` unterscheidet mit
`OS.has_feature("editor")` die Editor-Binary (auch CLI-Testläufe) vom Export.
Editor: `<Repository>/dev_portable_data/`. Export: Elternordner von
`OS.get_executable_path()`. Das aktuelle Arbeitsverzeichnis ist unerheblich.
Der Autoload `PortableStorage` erstellt und prüft alle vier Verzeichnisse durch
Schreiben, Flush und Löschen einer eindeutigen Testdatei. Bei einem Fehler wird
die Bedienung gesperrt und ein verständlicher Umzugshinweis angezeigt.
Godots standardmäßiges Dateilogging nach user:// ist deaktiviert. Das eigene
Startprotokoll liegt unter logs/. Engine-interne Cache-/Treiberdateien sind
keine Projekt- oder Arbeitsdaten und werden damit nicht kontrolliert.

## Projekte, Umzug und Backup

Projektformat 1 bleibt erhalten. Fotokopie, Maske und generierte Textur werden
über relative Dateinamen im jeweiligen Projektordner referenziert. Absolute
Quellfoto- und alte Arbeitsdateipfade werden beim Speichern aus den Metadaten
entfernt. Bereits gespeicherte Projekte bleiben lesbar. Originalfotos werden
nicht verändert und müssen zum Wiederöffnen nicht vorhanden sein.

Anwendung schließen und den **gesamten Programmordner** kopieren, einschließlich
projects/, data/, config/ und logs/. So funktionieren Umzug und Backup auf
USB-Stick oder einen anderen Rechner. Der neue Ordner muss beschreibbar sein;
Program Files ist ohne passende Rechte ungeeignet. Projekte löschen verschiebt
wie bisher nach projects/.trash; dieser Papierkorb gehört zum Backup.

## Alte Entwicklungsprojekte importieren

Explizit, nur mit der Editor-Binary:

```powershell
& $Godot --headless --path . --script res://scripts/storage/migrate_legacy_projects.gd
```

Liest `user://projects/` des aktuellen Benutzerkontos und schreibt vollständige
Projekte nach dev_portable_data/projects/. Vorhandene IDs werden übersprungen;
unvollständige Projekte werden gemeldet. Originaldaten bleiben unangetastet.
Es findet keine automatische Migration beim Start statt.

## Windows-Ordnerexport vorbereiten

```powershell
./scripts/storage/export_windows.ps1 -Godot 'Pfad/zur/Godot_console.exe' -PrepareOnly
./scripts/storage/export_windows.ps1 -Godot 'Pfad/zur/Godot_console.exe'
```

Preset: `Windows Portable`, Windows x86_64, eingebettetes PCK. Ziel:
`dist/PelvicachromisStudio/`. Das Skript erstellt Ordner und README.txt ohne Daten
zu löschen. Für den eigentlichen EXE-Export werden zur Godot-Version passende
Exportvorlagen benötigt. Es wird kein Installer erstellt.

Das kleine Editor-Exportplugin nimmt zusätzlich die unveränderte GLB-Rohdatei
für die bestehende Hashprüfung und die originale Albedo-PNG für CPU-Texturierung
ins PCK auf. Die importierten Ressourcen bleiben ebenfalls erhalten. JSON-
Projektionsdaten werden ausdrücklich eingeschlossen; Entwicklungsfotos,
Blender-Dateien, Diagnosen und Benutzerdaten werden nicht ausgeliefert.

Grundlagen: [Godot Windows-Export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)
und [EditorExportPlugin](https://docs.godotengine.org/en/stable/classes/class_editorexportplugin.html).

## Reproduzierbare Tests

Mit grafischer Godot-Binary im Repository starten:

```powershell
& $Godot --path . --script res://scripts/storage/validate_portable_storage.gd
& $Godot --path . --script res://scripts/project/validate_project_storage.gd
& $Godot --path . --script res://scripts/photo_import/validate_photo_import.gd
& $Godot --path . --script res://scripts/photo_import/validate_atlas_replacement.gd
```

Der Portabilitätstest umfasst den automatischen Analyse-/Korrektur-/Generierungs-
Workflow, speichert ein vollständiges Projekt, kopiert den gesamten lokalen
portablen Ordner unter .godot/portable_relocation/ und lädt das Projekt dort.
Er vergleicht Foto-, Masken-, Texturpixel und Landmarken, prüft relative Metadaten,
kein erneutes Analysieren, Materialumschaltung, Swim_Test, Kamera, Zoom, Speichern
und Löschen am neuen Ort. Zusätzlich werden Editor-/EXE-Pfadlogik und ein nicht
beschreibbarer Zielpfad geprüft. Berichte stehen in godot/diagnostics/.

Der Atlas-Test verwendet absichtlich ein historisches user://-Testprojekt als
Legacy-Fixture. Dies ist kein regulärer Speicherpfad der Anwendung.

Die Datenportabilität auf demselben Windows-Rechner ersetzt keinen Test einer
fertigen EXE auf einem zweiten Rechner. Der bestehende Forward+-Renderer
benötigt weiterhin passende Grafiktreiber und kompatible Hardware.

## Ergebnis dieser Umstellung

Bestanden: Portabilität inklusive vollständigem Fotoanalyse-/Texturworkflow,
Fotoimport, Projektverwaltung, Atlas-Regression und Start des exportierten PCK
mit GLB-Hashprüfung, Albedo-Laden, Skeleton und laufender Animation.
Die Entwicklungsmigration wurde mit einer isolierten vollständigen Projektkopie
geprüft: gleiche Foto-/Masken-/Texturdateien und Erstellungszeit; erneuter Import
überspringt das bereits vorhandene Projekt.

Für den Pakettest (ohne Exportvorlagen):

```powershell
& $Godot --headless --path . --export-pack 'Windows Portable' dist/PelvicachromisStudio/validation.pck
& $Godot --headless --main-pack "$PWD/dist/PelvicachromisStudio/validation.pck" --script "$PWD/scripts/storage/validate_export_pack.gd"
```

Die Windows-Exportvorlagen für Godot 4.7.2.stable sind installiert. Der erste
eigenständige Release-Build wird mit eingebettetem PCK erzeugt. `validation.pck`
ist ausschließlich ein früheres Testartefakt und gehört nicht zur Auslieferung.
Ein Test auf einem zweiten physischen Windows-PC bleibt erforderlich.

## Erster Windows-Release-Build (2026-09-29)

Godot 4.7.2.stable.official.ed1daf0bf, Vorlage windows_release_x86_64.exe aus
4.7.2.stable, Preset Windows Portable. Ausgabe:
`dist/PelvicachromisStudio/PelvicachromisStudio.exe`.

Beim ersten echten Release-Test fehlten transitiv per preload geladene Skripte.
Der frühere Editor-PCK-Test konnte diese noch aus dem Repository finden. Das
Preset wählt deshalb jetzt die Runtime-GDScripts ausdrücklich als Ressourcen aus.
Analyse, Projektion und Modelldaten wurden dafür nicht geändert. Künftige neue
Runtime-Skripte müssen ebenfalls in diese Exportauswahl aufgenommen werden.

Die offizielle Release-Vorlage unterstützt weder externe --script-Testläufe
noch --main-pack-Pfadüberschreibungen. Die Windows-UI-Automation wurde von der
Tool-Freigabe abgelehnt. Deshalb prüft ein separater, nicht ausgelieferter
Release-Diagnosebuild denselben Produktcode mit einer eingebetteten Testszene.
Diese lädt die reguläre Hauptszene und verwendet dieselben Controller und
Viewport-Mausereignisse. Das editor-Feature muss fehlen. Die finale unveränderte
EXE wird zusätzlich ohne Diagnosecode normal gestartet. Dies ersetzt keinen
vollständigen manuellen UI-Abnahmetest der finalen EXE.

Testablauf: Referenzfoto auswählen, zwölf Vorschläge und Kontur abwarten,
Textur erzeugen, Original/Generiert umschalten, Projekt speichern und erneut
laden. Skeleton mit 15 Bones, fortschreitende Swim_Test-Animation, Kamera,
Zoom und Reset prüfen. Anschließend Anwendung beenden, gesamten Ordner an
neuen Pfad mit Leerzeichen kopieren und dort die EXE mit einem fremden
Arbeitsverzeichnis starten. Gespeicherte Bilddateien und Landmarken müssen
identisch sein, erneute Analyse darf nicht stattfinden. Danach den kopierten
Programmordner nochmals umbenennen/verschieben und wiederholen.

Die ZIP enthält den obersten Ordner PelvicachromisStudio samt Testprojekt.
Keine EXE, ZIP, Arbeitsdaten oder Testscreenshots werden in Git aufgenommen.
Die Distribution enthält keinen Installer und keine separate PCK-Datei.

Einschränkungen: x86_64 Windows 10/11, passende Direct3D-12-Grafiktreiber für
Forward+. EXE nicht signiert; Windows SmartScreen kann warnen. Kein Test auf
einem zweiten physischen Rechner und keine Kompatibilitätszusage für sämtliche
Grafikkarten. Schreibzugriff auf den Programmordner bleibt erforderlich.

### Prüfergebnis des ersten Builds

- Finale EXE mit eingebettetem PCK erfolgreich erzeugt; normaler Start im dist-
  Ordner und am verschobenen/umbenannten Pfad ohne Engine-Fehler.
- Release-Diagnosebuild: Fotoimport, automatische zwölf Landmarken, Kontur,
  Texturerzeugung, Original/Generiert, Speichern/Öffnen, 15 Bones, Swim_Test,
  Kamera, Zoom und Reset ohne Testfehler.
- Wiederöffnen nach Kopieren und Umbenennen: identische SHA-256-Prüfsummen für
  Foto, Maske und Textur sowie identische Landmarken; keine erneute Analyse.
- Projektmetadaten enthalten keine absoluten Pfadabhängigkeiten. Geschützte
  Modelldateien sind unverändert. Die finale EXE enthält keinen Testcode.
- Build einschließlich Beispielprojekt: 152.916.268 Bytes (145,83 MiB).
- ZIP: 58.410.607 Bytes (55,70 MiB), Integritätsprüfung bestanden.
- ZIP-Pfad: `dist/PelvicachromisStudio_Windows_Portable.zip`.
- EXE SHA-256: `99cd9ceb32158f23d0903d9c2d222f3bb0319a5496278cb985faf11d75722b45`.

Die Größen beziehen sich auf diesen Build einschließlich Startprotokoll und
Beispielprojekt; sie ändern sich nach weiterer Nutzung. Testberichte und
Screenshots liegen lokal unter `.godot/release_*` und
`.godot/windows_release_summary.json` und werden nicht ausgeliefert.

Der normale Start der finalen EXE wurde zusätzlich nach Entpacken der ZIP in
ein neues Verzeichnis geprüft und ohne Fehler beendet.
