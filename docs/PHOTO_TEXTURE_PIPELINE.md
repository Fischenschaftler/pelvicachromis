# Texturüberarbeitung – Revision 2

Die aktuelle Texturierung ersetzt die unten beschriebene erste Materialfassung. Die Sicherung der funktionierenden Revision 1 liegt unter `blender/backups/photo_v1/`: Blender, GLB, Atlas, Maske und beide Bake-Skripte. Die Fischmaske und alle geschützten Modelldaten bleiben unverändert. Auch das UV-Layout bleibt identisch.

## Änderungen

- Die Fotoabtastung an gekrümmten Rücken-/Bauchbereichen und am Schwanzansatz berücksichtigt die Bogenlänge des bestehenden Körperquerschnitts. Eine weiche Mischung erhält die Registrierung der zentralen Flanke und verringert zusammengezogene/gezogene Randmuster. Am Kopf ist diese Korrektur schwächer, damit Kiemenzeichnung und Augenposition erhalten bleiben. Es werden ausschließlich Quellkoordinaten für das Bake berechnet; kein Mesh und keine UV-Koordinate wird verändert.
- Beide Augen nutzen jetzt ihre vorhandenen PhotoUV-Inseln mit der echten fotografierten Pupille, Iris, goldgelben Umrandung und dunklen Kontur. Material `Pelvicachromis_Photo_Eyes`, Roughness 0,38. Auch hier ist die nicht fotografierte Seite ein Fallback aus derselben Aufnahme.
- Brustflossen: vorsichtige Entmischung mit der benachbarten Aquariumfarbe, 70 % korrigierte Farbe / 30 % Original. Die aufgenommenen Strahlen bleiben erhalten. Alpha nimmt von ca. 0,74 an der Wurzel bis 0,35 am distalen Rand ab.
- Die in den Körper eingebetteten Flossenwurzeln erhalten eine weiche Alpha-Absenkung, damit überlagerte Körperzeichnung weniger auffällt. Äußere Flossen behalten ca. 0,90 Alpha und die originalen Rot-/Violett-/Gelbtöne und Punkte.
- Breite Helligkeitsverläufe auf dem Körper werden aus einem maskierten 42-Pixel-Gaußfilter geschätzt und mit geringer Stärke korrigiert (Gain begrenzt auf 0,90–1,13). Chroma und hochfrequente Schuppenzeichnung bleiben erhalten. Die Flossenfarben werden nicht mit dieser Körperkorrektur aufgehellt.
- Der bestehende 4096²-Atlas wird aktualisiert und enthält jetzt einen Alpha-Kanal für die Membranen; 20 Pixel Padding bleiben bestehen. Maske und Atlaspfad bleiben gleich.

## Diagnosen und Wiederholung

Der vorhandene Aufruf von `bake_reference_texture.py` führt sämtliche Schritte einschließlich Rendern aus. `photo_raster.py` übernimmt Rasterisierung und Vergleichsmontage. Die Vergleichsansicht verwendet beschnittene Ansichten mit nahezu gleicher Fischlänge.

Blender-Bilder unter `blender/diagnostics/`:

- `photo_textured_side.png`: rechte fotografierte Seite.
- `photo_textured_left.png`: linke Fallback-Seite.
- `photo_textured_perspective.png`: schräg von vorne.
- `photo_textured_rear.png`: schräg von hinten.
- `photo_reference_comparison.png`: Referenz neben aktueller rechter Seite.
- `photo_reference_four_views.png`: vier Vergleichspaare mit �hnlich gro�er Darstellung.
- `photo_texture_atlas.png`: Atlasübersicht.

Die Exportprüfung erwartet jetzt vier Foto-Materialien. Der Godot-Test prüft elf foto-texturierte Meshes einschließlich Augen, 15 Bones, UVs, Skinning und Swim_Test. Die Quellgeometrie, Bones, Gewichte, UVs und Animationskurven werden vor/nach dem Bake per Fingerprint verglichen.

## Ergebnis der ausgef�hrten Regression

Godot 4.7.2, Headless und GPU/D3D12: 11 texturierte Meshes, 15 Bones, Skinning/UVs vorhanden, Swim_Test 2 Sekunden, zwei vollst�ndige Loops ohne Fehler. Loop-Seam-Fehler 0; Blender/Godot-Skin-Bounds weichen maximal 0,000000304 m ab. Der gesch�tzte Fingerprint bleibt `05a38e19d6a5ee32d4d6839d09602d7978a8281be3ad6e67079d5077765a1d30`; die Masken-SHA256 vor/nach ist ebenfalls identisch (`C58DB100B060D67F4F94054B4D781B3F658E5ED45FA53FA3511226A9FD477A90`).

Der Blender-5.2-glTF-Exporter warnt bei den zwei transparenten Materialien vor mehreren Bildknoten. Pr�fung des lokalen Exportercodes (`material/texture.py`, `__gather_sampler`) zeigt: Er z�hlt die beiden verbundenen Sockets Color und Alpha ohne Deduplizierung. Beide kommen hier aus demselben Bildknoten mit identischem Sampler; die exportierte Transparenz ist im Godot-Bild vorhanden. Kein Godot-Testfehler. Blender meldet au�erdem die bekannte zuk�nftige use_nodes-Abk�ndigung.

## Verbleibende Grenzen

Ein einzelnes Seitenfoto liefert keine echte Farbe der Ober-/Unterseite oder verdeckter Bereiche. Die Korrektur verteilt beobachtete Muster besser, kann diese fehlenden Ansichten aber nicht rekonstruieren. Am Kopfende und Flossenansatz bleiben perspektivabhängige Unterschiede. Die Brustflossen sind durch die bereits im Foto enthaltene Hintergrundmischung nur näherungsweise korrigierbar. Breite natürliche Pigmentverläufe und Beleuchtung lassen sich aus einem Foto nicht eindeutig trennen: Die Helligkeitskorrektur ist bewusst begrenzt, kein vollständiges De-Lighting. Glanzpunkte im Auge und Irisieren im Kiemenbereich sind teilweise weiterhin eingebrannt. Der Atlas erhält echte Fotoinformation; keine neu erfundenen Schuppen.

---

## Archiv: erste Fassung (durch Revision 2 ergänzt)

# Foto-Texturierung: erster reproduzierbarer Prototyp

## Gesicherter Stand

`blender/backups/Pelvicachromis_Male_PrePhoto.blend` sichert den ersten Stand vor der Foto-Texturierung. Das Bake-Script überschreibt diese Sicherung bei Wiederholungen nicht. Die aktuelle Datei ist `models/Pelvicachromis_Male_Blockout.blend`.

Der Fingerprint in `blender/diagnostics/photo_texture_validation.json` umfasst Mesh-Koordinaten und Faces, PhotoUV und Seams, Objekttransformationen, Parenting, Armature-Modifier, Bones, Vertex-Gewichte und Animationskurven. Vor und nach dem Bake sind diese Daten identisch. Frame 0 bleibt neutral; Swim_Test_Loop und Rig_Test_Pose bleiben erhalten.

## Ausführen

Vom Repository-Verzeichnis aus, mit Blender und einem Python mit NumPy und Pillow:

```powershell
blender --background models/Pelvicachromis_Male_Blockout.blend --python-exit-code 1 --python blender/bake_reference_texture.py -- --python-runtime "C:/Pfad/zu/python.exe"
blender --background models/Pelvicachromis_Male_Blockout.blend --python-exit-code 1 --python blender/export_godot.py
godot --headless --editor --path . --import
godot --headless --path . --script res://scripts/validate_fish_import.gd
```

Ohne `--python-runtime` wird `python` aus PATH verwendet. `photo_raster.py` ist der Bild-/Raster-Helfer. Temporäre Dreiecksdaten liegen unter `textures/work/`, werden automatisch neu erzeugt und nicht versioniert. Der Blender-Quellstand muss beim Start geladen sein. Der alte Modellgenerator und prepare_uv.py werden nicht ausgeführt.

## Referenz und Maske

Einzige Farbquelle: `blender/reference/pelvicachromis_taeniatus_male.jpg`, 800 × 800 Pixel. Registrierung: `u = x / (0.08/670) + 400`, `v = 400 - z / (0.08/670)`. Die Foto-Perspektive wird als orthografisch angenähert.

Die Maske entsteht aus manuell nachgezeichneten Polygonen für Körper, Schwanz-, Rücken-, After-, Bauch- und Brustflosse. Diese festen Koordinaten sind im Raster-Helfer dokumentiert; keine KI-Segmentierung. Die Vereinigungsmaske wird als `textures/reference_fish_mask.png` gespeichert. Für Farbproben werden die einzelnen Masken um einen Pixel erodiert. Farben außerhalb der sicheren Bereiche werden durch schrittweise Erweiterung aus dem jeweiligen Bauteil ersetzt. Dadurch werden keine direkten Aquarium-Proben außerhalb dieser Masken verwendet. Subpixel-Mischfarben und Fehler der manuellen Kontur sind damit nicht vollständig ausgeschlossen.

Die transparente Brustflosse enthält bereits durchscheinenden Hintergrund. Ein einfacher, aus ihrer fotografierten Wurzel abgeleiteter Farbton reduziert dessen neutralen Anteil. Das ist eine Näherung und keine vollständige physikalische Trennung von Hintergrund und Membran.

## PhotoUV-Projektion und Seiten

Jedes vorhandene UV-Dreieck wird auf dem 4096 × 4096 Atlas rasterisiert. Baryzentrische Koordinaten interpolieren die unveränderten Weltpositionen, daraus werden registrierte Foto-Koordinaten berechnet und bilinear abgetastet. Es gibt keine kamerabhängige Laufzeitprojektion und keine neue UV-Abwicklung.

- Tatsächlich fotografiert: **rechte Modellseite, -Y** (`Body_Right`).
- **Vorläufiger Fallback:** `Body_Left` (+Y) erhält dieselbe registrierte Fotozeichnung in seiner eigenen UV-Insel. Die beiden Inseln bleiben unabhängig und überlappen nicht.
- Die gegenüberliegenden paarigen Flossen verwenden ebenfalls dieselbe Projektion als vorläufige Kopie.
- Medianflossen nutzen ihre bestehenden Inseln; beide Seiten der dünnen Membran teilen die fotografierte Farbe.
- Kopf und Maul verwenden die vorhandene Registrierung. Augen behalten ihre bisherigen separaten Materialien einschließlich des einfachen Randes.

Der Atlas heißt `textures/pelvicachromis_taeniatus_male_albedo.png`. 20 Texel Dilation erweitern die Inselränder für Mipmapping. Der ungenutzte Bereich bleibt schwarz; er wird durch den UV-Innenbereich und Padding nicht direkt abgetastet. Die 4096-Auflösung erleichtert die spätere Erweiterung, erzeugt aber keine zusätzliche Detailinformation gegenüber dem 800-Pixel-Foto.

## Materialien

`Pelvicachromis_Photo_Material` verwendet den Atlas als sRGB Base Color. Die Varianten `Pelvicachromis_Photo_Fins` (Alpha 0,88) und `Pelvicachromis_Photo_Pectoral` (Alpha 0,48) verwenden denselben Atlas, sind doppelseitig und leicht transparent. Keine zusätzlichen Normal-, Roughness-, Metallic- oder Displacement-Maps. Die vorhandene Beleuchtung des Fotos ist im Farbwert enthalten; es handelt sich noch nicht um eine beleuchtungsbereinigte Albedo.

## Diagnose und beobachtete Grenzen

Unter `blender/diagnostics/`:

- `photo_textured_side.png`: orthografische fotografierte Seite.
- `photo_textured_perspective.png`: räumliche Ansicht mit beiden paarigen Flossen.
- `photo_texture_atlas.png`: verkleinerte Übersicht des gesamten Atlas.
- `photo_reference_comparison.png`: Foto und Blender-Ergebnis nebeneinander.
- `photo_texture_validation.json`: Unverändertheitsnachweis.

Die Seitenflächen zeigen die echte gelbe Grundfarbe, Schuppenzeichnung, den türkisfarbenen Kiemenbereich sowie die Schwanz- und Afterflossenmuster. Es wurden keine Schuppen erfunden. An Rücken-/Bauchmitte und Endkappen wird die Zeichnung durch die Seitenprojektion komprimiert bzw. gestreckt; diese Bereiche sind im Foto nicht direkt beobachtet. An Flossenansätzen sind Übergänge/Überlagerungen noch sichtbar. Insbesondere die Brustflosse bleibt blass; die separate Augenfassung wirkt einfacher als das Foto. Die verdeckte Körperzeichnung unter der fotografierten Brustflosse lässt sich aus einem Foto nicht rekonstruieren und bleibt teilweise mitprojiziert. Es sind keine auffälligen schwarzen UV-Nähte in den geprüften Ansichten sichtbar; extreme Verkleinerung und alle Blickwinkel sind nicht abschließend geprüft.

## GLB und Godot

`models/pelvicachromis_taeniatus_male.glb` enthält die eingebettete PNG-Textur und drei Foto-Materialvarianten, 11 Meshes, einen Skin und 15 Joints. Exportiert wird ausschließlich Swim_Test_Loop (2 Sekunden); Godot erkennt **Swim_Test**. Die Hauptszene bleibt unverändert.

Headless- und GPU-Test in Godot 4.7.2 erfolgreich:

- ein Skeleton3D, 15 Bones, Skinning und PhotoUV auf allen Oberflächen;
- neun foto-texturierte Meshes; zwei Augen behalten ihre Materialien;
- Autoplay und zwei vollständige Loops;
- Loop-Positionsfehler 0; maximale Abweichung der Skin-Bounds von Blender etwa 0,000000304 m;
- Augen und Maul ohne Relativbewegung zum stabilen Kopf;
- keine neuen sichtbaren Deformationsprobleme oder abgelösten Flossen in den fünf geprüften Posen;
- keine Godot-Import-/Testfehler oder Warnungen im erfolgreichen Lauf.

Screenshot: `godot/diagnostics/photo_texture_test.png`. Weitere fünf animierte Stichproben und JSON-Prüfberichte liegen unter `blender/diagnostics/`. Blender meldet lediglich einen Hinweis zur zukünftigen Abschaffung von use_nodes in Blender 6.0.

## Für beliebige Benutzerfotos noch erforderlich

Auflösung und Registrierung müssen aus Bildmerkmalen/Benutzermarkierungen statt fester Koordinaten bestimmt werden. Masken müssen pro Foto ermittelt und korrigierbar sein. Linke/rechte Seite und verdeckte Flossen müssen erkannt bzw. zugeordnet werden; separate Fotos sollen die heutigen Fallbacks ersetzen. Perspektive, unterschiedliche Posen, Farbkalibrierung, Beleuchtungsbereinigung, transparente Membranen und verdeckte Körperzeichnung benötigen eigene Verfahren. Die gegenwärtige Pipeline macht dazu keine allgemeine automatische Erkennung.

## Dateien dieses Schritts

Neu: bake_reference_texture.py, photo_raster.py, PrePhoto-Sicherung, Albedo und Fischmaske mit Godot-Importmetadaten, vier Blender-Diagnosebilder, Foto-Prüfbericht, Godot-Diagnosebild und .gdignore, diese Dokumentation sowie Ausschlussdateien in textures/work.

Aktualisiert: aktuelle .blend und .glb, export_godot.py, validate_fish_import.gd, GLB-Prüfbericht, Godot-Prüfberichte, Logs und fünf Godot-Posenbilder. Die uncommittierten UV-Arbeiten aus dem vorherigen Schritt bleiben enthalten.

Godot extrahiert den eingebetteten Atlas zusätzlich als models/pelvicachromis_taeniatus_male_pelvicachromis_taeniatus_male_albedo.png samt .import-Datei. Diese beim Import erzeugte Abhängigkeit bleibt im Repository verfügbar; die maßgebliche Bake-Ausgabe liegt unter textures/.
