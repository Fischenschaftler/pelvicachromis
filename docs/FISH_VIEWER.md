# Interaktiver Fisch-Viewer

`project.godot` in Godot 4 öffnen und **F5** drücken. Hauptszene: `scenes/Main.tscn`.

- Linke Maustaste halten und ziehen: horizontal/vertikal um den Fisch drehen.
- Mausrad: zoomen. Abstand und vertikaler Winkel sind begrenzt.
- **Animation stoppen / starten**: Swim_Test pausieren bzw. fortsetzen.
- **Ansicht zurücksetzen**: zentrierte perspektivische Seitenansicht mit passendem Abstand für das aktuelle Fenster. Der Animationsstatus bleibt erhalten.

Godot verwendet einen Camera3D mit Perspektivprojektion (keinen separaten PerspectiveCamera3D-Knotentyp). Das GLB wird direkt instanziiert; importierte Meshes, UVs, Texturen, Bones, Gewichte und Animationsressourcen werden nicht verändert. Die vorhandene Loop-Einstellung wird genutzt.

Fenster: initial 1280 × 800, Minimum 480 × 360. UI in nativer Fensterauflösung, Kamera passt sich dem Seitenverhältnis an. Neutraler dunkler Hintergrund, Hauptlicht, schwaches Fülllicht und Umgebungslicht. Da der Viewer keinen Ton verwendet, ist der Dummy-Audiotreiber eingestellt; so entsteht auf Systemen ohne verfügbaren Audio-Ausgang kein WASAPI-Startfehler.

## Dateien

- `scenes/Main.tscn`: Viewer, GLB, Umgebung, Lichter, Kamera, UI.
- `scripts/fish_viewer.gd`: Modellzentrierung, Autoplay und UI.
- `scripts/orbit_camera.gd`: Orbit, Grenzen, Zoom, Reset, Größenanpassung.
- `project.godot`: Fenster- und Audioeinstellungen; Main bleibt Hauptszene.
- `scripts/validate_fish_viewer.gd`: reproduzierbarer Funktionstest.
- `godot/diagnostics/viewer_*`: Testbericht, Logs, Screenshots und Hashliste.

## Durchgeführte Prüfungen

Godot 4.7.2: Headless und D3D12-GPU. Reale Godot-Viewport-Eingabeereignisse prüfen Ziehen, Mausrad, Winkel-/Zoomgrenzen, Loslassen über UI, Klicks auf Reset und Pause/Fortsetzen. Animation läuft über ihre zweisekündige Schleifengrenze. Fenstergrößen 1280 × 800, 600 × 900 und 480 × 360: UI innerhalb des Fensters und Modell vollständig im Bild. GPU-Bilder visuell kontrolliert. Finaler GPU-Lauf ohne Fehler oder Warnungen.

Aufruf zum Wiederholen:

```powershell
godot --path . --script res://scripts/validate_fish_viewer.gd
```

18 bestehende Modell-, Textur- und Blender-Skriptdateien wurden vor/nach der Implementierung per SHA256 verglichen: unverändert. Kein Blender-Lauf, kein erneuter GLB-Export. Keine Commits oder Pushes.
