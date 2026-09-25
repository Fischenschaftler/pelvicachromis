# Körperbreite: Faktor 1,5

## Sicherung und Änderung

Vor der Änderung wurden die funktionierenden Dateien gesichert:

- `blender/backups/width_before/Pelvicachromis_Male_Blockout.blend`
- `blender/backups/width_before/pelvicachromis_taeniatus_male.glb`

Die Körperlängsachse in Blender ist X, die Höhe Z. Senkrecht zur Seitenansicht liegt **Y**; nach glTF-Konvertierung entspricht die Breite Godot Z.

`blender/widen_body.py` multipliziert ausschließlich Y-Koordinaten von Fish_Body symmetrisch um Y=0 mit 1,5. Die maximale Körperbreite steigt von 7,37452 auf 11,06178 mm. Alle X-/Z-Koordinaten und damit Länge/Höhe bleiben erhalten. Mouth wird entlang Y passend verbreitert. Die Objekttransformationen und Origins bleiben unverändert; verändert werden nur Mesh-Koordinaten.

Augen werden je Seite um etwa 1,127 mm nach außen versetzt, Brustflossen um 1,554 mm, Bauchflossen um 0,889 mm. Diese Objekte werden nicht skaliert: Augenform und Flossendicke bleiben erhalten. Die mittigen Rücken-, After- und Schwanzflossen benötigen keine seitliche Versetzung und bleiben geometrisch unverändert. Die paarigen Flossen behalten ihre Form; ihre Versetzung richtet sich nach der bisherigen Ansatzbreite.

Keine neue Texturierung, keine Farbänderung, kein Neuaufbau des Rigs. UVs, Topologie, Vertex Groups, Gewichte, 15 Bones, Animationskurven und Materialzuweisungen sind vor/nach per Fingerprint identisch. Die PNG-Dateien unter textures sind per SHA256 unverändert.

## Ausführen und Diagnose

Das Script wird in Blender mit dem gesicherten Ausgangsmodell geladen und ausgeführt. Ein Marker verhindert versehentliche wiederholte Verbreiterung des schon angepassten Modells. Es rendert vor/nach, validiert die vorhandene Animation und speichert den neuen Stand. `render_width_front.py` erstellt bei Bedarf den Frontalvergleich ohne die Eingangsdateien zu speichern. `compare_width.py` setzt mit Pillow die Renderbilder nebeneinander.

- `blender/diagnostics/width_comparison_front.png`
- `blender/diagnostics/width_comparison_oblique.png`
- `blender/diagnostics/width_before_side.png` / `width_after_side.png`
- `blender/diagnostics/width_validation.json`

Kamera, Maßstab und Beleuchtung sind je Vorher-/Nachher-Paar gleich. Die Stirn-/Bauchtextur zeigt frontal weiterhin die bereits vorhandenen Projektionsstreifen. Wegen der unveränderten UVs und Textur verteilen sich diese Farben nun über eine breitere Oberfläche. Das ist keine neue Texturierung.

## Export und Tests

Aktualisiert: `models/Pelvicachromis_Male_Blockout.blend` und `models/pelvicachromis_taeniatus_male.glb`. Der bestehende Main-Viewer nutzt automatisch dieselbe GLB-Ressource. Seine Szenen- und Steuerungsskripte benötigen keine Änderung.

`verify_rig.py` prüft für die markierte Breitenrevision den neuen, im Prüfbericht dokumentierten Geometrie-Hash. Für ältere Modelle bleibt die bisherige Baseline erhalten.

Blender: alle 61 Frames der vorhandenen Schwimmschleife geprüft, keine kollabierten oder übermäßig gestreckten Flächen; Selbstüberschneidungstest bei neun Posen ohne Befund. Rest-Pose neutral, Loop-Ende deckungsgleich. Seiten-, Frontal- und Schrägansichten visuell kontrolliert; keine auffällig abgelösten Augen oder Flossenansätze.

Godot 4.7.2: GLB importiert, 11 Meshes mit UV/Foto-Material, 15 Bones, Skinning, Swim_Test (2 s) und zwei Schleifen geprüft. Loop-Seam-Fehler 0, maximale Skin-Bounds-Abweichung zu Blender ca. 0,000000306 m. Augen und Mund bleiben am stabilen Kopf. Der GPU-Viewer-Test prüft Maus-Orbit, Zoomgrenzen, Pause/Fortsetzen, Reset und drei Fenstergrößen ohne Fehler. Logs unter `godot/diagnostics/width_*`, aktuelle Viewer-Screenshots unter `godot/diagnostics/viewer_*`.

Blender zeigt die bereits bekannte glTF-Samplerwarnung bei Color/Alpha desselben Bildknotens; Godot-Import und GPU-Test laufen ohne Fehler. Kein Commit, kein Push. Der vorher unterbrochene Commit-Vorgang hatte keinen Commit erstellt.
