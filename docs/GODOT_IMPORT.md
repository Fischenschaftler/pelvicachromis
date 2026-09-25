# Blender → GLB → Godot 4: erster vollständiger Test

**UV-Erweiterung:** Alle elf Meshes besitzen inzwischen PhotoUV. Der Export
enthält TEXCOORD_0; der Godot-Test prüft UV-Arrays auf allen Surfaces zusätzlich
zum unveränderten Rig-/Animationstest. Atlasaufbau, Sicherung und Checker-Diagnosen:
[UV_MAPPING.md](UV_MAPPING.md).

Getestet mit Blender 5.2.1 und Godot 4.7.2 unter Windows.
Grafiktest: Direct3D 12, Forward+, NVIDIA GeForce RTX 3070.

## Dateien und Sicherung

- Quelle: `models/Pelvicachromis_Male_Blockout.blend`.
- Unveränderte Sicherung: `blender/backups/Pelvicachromis_Male_PreGodot.blend`.
- Austauschdatei: `models/pelvicachromis_taeniatus_male.glb`.
- Importoptionen: `models/pelvicachromis_taeniatus_male.glb.import`.
- Unabhängige Testszene: `scenes/FishRigTest.tscn`.
- Autostart: `scripts/fish_rig_test.gd`.
- Automatisierte Import-/Skinning-Prüfung: `scripts/validate_fish_import.gd`.
- Reproduzierbarer Blender-Export: `blender/export_godot.py`.

Die ursprüngliche Blend-Datei bleibt bytegleich und weiterhin auf neutralem Frame 0.
Geometrie, Rig-Gewichte, Rest Pose und Materialien wurden für den Export nicht
bearbeitet. Die Sicherung wird beim ersten Export erstellt und bei Wiederholung
nicht überschrieben. Exportänderungen an Auswahl und Framebereich passieren nur
im Speicher des Blender-Hintergrundprozesses.

## Export

Das Script prüft zunächst das gespeicherte Rig. Anschließend exportiert es nur
die Armature und elf Mesh-Objekte: Fish_Body, sieben Flossen, beide Augen und Mouth.
Es verwendet GLB, Skinning mit höchstens vier Gewichten, alle 15 Bones, unveränderte
Rest-Geometrie, einfache vorhandene Materialien und die aktive Action.
Kameras, Lichter, Referenzbilder und Diagnoseobjekte sind nicht enthalten.
Die GLB enthält keine Bilder oder Texturen. Seit der UV-Erweiterung werden
UV-Koordinaten als TEXCOORD_0 mit exportiert.

Nur **Swim_Test_Loop** wird exportiert. Sampling: Frames 1–61 bei 30 FPS,
auf Zeit 0–2 Sekunden verschoben. Frame 0 und Rig_Test_Pose bleiben außerhalb
des Exports. Frame 61 entspricht Frame 1. Animationoptimierung im Export ist aus.

Achsenumsetzung durch den Standardexport: Blender `(X, Y, Z)` → Godot `(X, Z, -Y)`.
Damit bleibt der Kopf in +X-Richtung, die Höhe liegt in Godot auf +Y und die
Körperbreite auf Z. Maßstab 1; der Fisch bleibt ungefähr 0,08 m lang.

## Godot-Import und Testszene

Godot erkennt **11 MeshInstance3D**, **ein Skeleton3D mit 15 Bones** und die Skin-
Bindungen aller Meshes. Erkannter Clip: **Swim_Test**, Länge **2,000 Sekunden**.
Godot entfernt den Namenszusatz `_Loop` und setzt den Loop-Modus. Das Testscript
setzt den Modus zusätzlich explizit und startet die importierte Animation.
Es fügt keine prozedurale Bewegung hinzu. Rig_Test_Pose wurde nicht importiert.

Für diesen genauen Vergleich sind im GLB-Import LOD-Erzeugung, Mesh-Kompression
und der Animation-Optimizer ausgeschaltet. Die normale Optimierung hatte eine
kleine Abweichung von bis zu etwa 0,127 mm gegenüber Blender verursacht.
Die Präzisionsoptionen stehen in der mitgelieferten `.glb.import`-Datei.

Die Testszene enthält das GLB-Modell, eine leicht erhöhte seitliche Kamera,
DirectionalLight3D und eine neutrale Umgebung. Die Kamera hat eine zur Größe
des Fisches passende Near-Clipping-Distanz von 1 mm.

`Main.tscn` und die Hauptszenenzuordnung bleiben unverändert. In `project.godot`
wurde lediglich `filesystem/import/blender/enabled=false` ergänzt: Das Projekt
verwendet die ausdrücklich exportierte GLB, statt die Arbeitsdatei zusätzlich
automatisch durch Blender zu importieren. `blender/.gdignore` hält Referenz,
Sicherung und Diagnosebilder aus dem Godot-Assetimport heraus.

## Ergebnisse und Grenzen der Prüfung

- Import, Headless-Test und echter Grafiktest beendet mit Exitcode 0.
- Abschließende Import- und Laufzeitlogs ohne Fehler oder Warnungen.
- Automatischer Start und zwei vollständige Loop-Durchläufe über 4,1 Sekunden
  sowohl headless als auch mit Direct3D-Renderer bestätigt.
- Bei 0 / 0,5 / 1 / 1,5 / 2 Sekunden wurden die Godot-Skins rechnerisch aus den
  tatsächlich importierten Vertices, Bones, Bind-Matrizen und Gewichten ausgewertet.
  Deren Begrenzungsboxen unterscheiden sich maximal um **0,000304 mm** von den
  unabhängig in Blender ausgewerteten Meshes. Das ist ein Abgleich der Boxen,
  keine Behauptung eines vollständigen Vertex-für-Vertex-Vergleichs mit Blender.
- Innerhalb Godots wurde der Loop-Übergang dagegen für jeden ausgewerteten
  Skin-Vertex geprüft: **0 m Abweichung** zwischen Anfang und Ende.
- Maximale Bewegung gegenüber dem Start in den Stichproben: Körper etwa
  **4,28 mm**, Schwanzflosse **7,58 mm**; alle übrigen Flossen bewegen sich ebenfalls.
- Augen und Mund verändern ihre Position gegenüber dem stabilen Kopf nicht.
- Die fünf echten GPU-Screenshots zeigen einen vollständigen Fisch ohne
  auseinandergezogene Meshteile, auffällige harte Knicke oder abgelöste Flossen.
  Der vorhandene sichtbare Übergang zwischen Schwanzstiel und separater
  Schwanzflosse gehört zum Grundmodell. Durchsichtige, überlagerte Brustflossen
  und die einfachen Materialien sind weiterhin nur Platzhalter.
- Dies ist ein technischer Pipeline-Test des vorhandenen kleinen Schwimmloops;
  extreme Posen und eine finale realistische Schwimmlogik sind nicht abgedeckt.

Bei den ersten sandboxbeschränkten Versuchen gab es Schreibrechte- und
Zertifikatsspeicher-Meldungen sowie einen fehlenden Blender-Pfad beim direkten
Blend-Import. Nach Bereinigung des Importwegs und Ausführung mit den benötigten
Prozessrechten treten diese in den abschließenden Prüfungen nicht mehr auf.

## Diagnoseartefakte

Unter `blender/diagnostics/`:

- `glb_export_validation.json`: GLB-Struktur, Quell-Prüfsumme, Blender-Vergleichswerte.
- `godot_validation_headless.json`, `godot_validation_visual.json`: Messergebnisse.
- `godot_import.log`, `godot_headless.log`, `godot_visual.log`: abschließende Logs.
- `godot_swim_00.png` bis `godot_swim_04.png`: echte Viewport-Aufnahmen bei
  0 / 0,5 / 1 / 1,5 / 2 Sekunden, 1600 × 1000 Pixel.

## Selbst starten / erneut prüfen

Im Godot-Editor `scenes/FishRigTest.tscn` öffnen und **F6** drücken.
F5 startet weiterhin die bisherige Main-Szene.

PowerShell im Repository-Verzeichnis:

```powershell
$blenderExe = 'D:\Programme\Blender\Blender\blender.exe'
$godotExe = 'D:\Programme\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'

& $blenderExe --background models/Pelvicachromis_Male_Blockout.blend --python-exit-code 1 --python blender/export_godot.py
& $godotExe --headless --editor --path . --import
& $godotExe --headless --path . --script res://scripts/validate_fish_import.gd
& $godotExe --path . --resolution 1600x1000 --script res://scripts/validate_fish_import.gd
```

Der letzte Befehl erzeugt die Screenshots mit dem Grafikrenderer. Das Prüfscript
ist für das lokale Projekt gedacht und liest die Blender-Diagnosedaten direkt;
es gehört nicht zur späteren Anwendung. Tests dieser Sitzung verwendeten
`.godot/test_runtime` als prozesslokales APPDATA-Verzeichnis, damit Testeinstellungen
von den normalen Godot-Benutzereinstellungen getrennt bleiben.

Offizielle Grundlagen:
[Godot: glTF/GLB und Blender-Import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html),
[Blender: glTF-Export und Animationsmodi](https://docs.blender.org/manual/en/5.0/addons/import_export/scene_gltf2.html).

Die erste Foto-Texturierung mit eingebettetem Atlas ist in [PHOTO_TEXTURE_PIPELINE.md](PHOTO_TEXTURE_PIPELINE.md) dokumentiert.
