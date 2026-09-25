# PhotoUV: Vorbereitung seitlicher Fischfotos

## Stand und Erhaltung des Rigs

Alle elf Mesh-Objekte besitzen eine aktive UV-Map **PhotoUV**. Sie bilden einen
gemeinsamen Atlas im Bereich 0–1 mit **17 getrennten Inseln**. Es gibt keine
Überlagerung der beiden Körperseiten und keine gestapelten paarigen Flossen.

Sicherung vor diesem Schritt:
`blender/backups/Pelvicachromis_Male_PreUV.blend`.
Aktuelles Modell: `models/Pelvicachromis_Male_Blockout.blend`.

`blender/prepare_uv.py` vergleicht vor/nach der Bearbeitung eine Prüfsumme über
Vertexpositionen, Flächen, Objekttransformationen, Parent-Beziehungen,
Armature-Modifier, Vertex-Gewichte, Bone-Restmatrizen und Animations-Keyframes.
Diese Daten bleiben identisch. Geändert werden UV-Koordinaten und UV-Seam-Marken.
Die Neutralstellung ist weiterhin Frame 0; die Swim-Action bleibt erhalten.

## Körper und Kopf

**Left ist entsprechend der bestehenden Objektbenennung die Blender-Seite +Y;
Right ist -Y.** X bleibt die Länge und Z die Höhe. Beide Körperinseln zeigen
die Schnauze in Richtung steigendes U. Die spiegelverkehrte Schrift im Foto
der gegenüberliegenden Checker-Ansicht entsteht durch den Blick von +Y;
die UV-Bereiche liegen trotzdem vollständig getrennt.

Jede Körperseite ist eine zusammenhängende Insel einschließlich Kopf,
Stirn, Wange, Kiemendeckel, Augenregion und Schwanzstiel. Seams verlaufen auf
Rücken- und Bauchmittellinie. Die kleinen Stirnflächen am Schwanzende und
an der Schnauzenspitze sind durch ringförmige Seams als eigene Inseln abgetrennt.
Innerhalb der sichtbaren seitlichen Haut gibt es keine zusätzlichen Schnitte.

Die X-Koordinate folgt der Seitenaufnahme. In Querrichtung werden die
Oberflächenbogenlängen der vorhandenen Körperringe abgewickelt. Dadurch wird
die Seitenansicht weitgehend erhalten, ohne die gerundeten Rücken-/Bauchränder
wie bei einer rein planaren Projektion stark zusammenzudrücken. Ein Foto kann
später seitenweise zugeordnet werden; an den gekrümmten Rändern ist eine lokale
Anpassung/Projektion nötig. Ein unverändertes rechteckiges Foto wird dort nicht
automatisch verzerrungsfrei passen.

## Atlasbereiche

Koordinaten sind reservierte UV-Rechtecke, jeweils mit zusätzlichem Abstand
der Insel zum Rand. Pro Insel wird einheitlich skaliert, nicht unabhängig in U/V.
In `uv_layout.png` liegt V=1 oben und U=0 links.

| Bereich | U | V |
| --- | --- | --- |
| Linke Körperseite (+Y) | 0,02–0,70 | 0,67–0,98 |
| Rechte Körperseite (-Y) | 0,02–0,70 | 0,34–0,65 |
| Rückenflosse | 0,02–0,54 | 0,17–0,32 |
| Schwanzflosse | 0,73–0,98 | 0,64–0,98 |
| Afterflosse | 0,73–0,98 | 0,31–0,61 |
| Bauchflosse links | 0,02–0,24 | 0,02–0,145 |
| Bauchflosse rechts | 0,26–0,48 | 0,02–0,145 |
| Brustflosse links | 0,56–0,63 | 0,17–0,31 |
| Brustflosse rechts | 0,65–0,72 | 0,17–0,31 |
| Linkes Auge vorn / hinten | 0,51–0,56 / 0,58–0,63 | 0,07–0,12 |
| Rechtes Auge vorn / hinten | 0,65–0,70 / 0,72–0,77 | 0,07–0,12 |
| Mundhälften | 0,80–0,86 / 0,89–0,95 | 0,07–0,12 |
| Schwanzstiel-Abschluss | 0,77–0,85 | 0,18–0,27 |
| Schnauzen-Abschluss | 0,89–0,97 | 0,18–0,27 |

Jede Flosse bleibt eine zusammenhängende Insel. Die Flossen werden anhand ihrer
Oberfläche abgewickelt und anschließend zur ursprünglichen Seitenform ausgerichtet.
Die Schwanzflosse verwendet Blenders Minimum-Stretch-Verfahren, die übrigen
Flossen eine winkelbasierte Abwicklung. Das beseitigt kleine UV-Faltungen an
zusammenlaufenden Randstreifen, die eine einfache Seitenprojektion verursachte.
Augen besitzen vordere/hintere Scheiben, das Maul zwei winkelbasiert abgewickelte
Hälften. Diese kleinen Teile benötigen zunächst keine Fotooptimierung.

Die mittleren Flossen sind weiterhin einzelne dünne Membranen. Ihre Vorder- und
Rückansicht nutzt dieselbe Fläche/UV-Insel. Für unabhängig gefärbte Vorder- und
Rückseiten dieser Membranen wäre später eine passende Materiallösung nötig.
Die beiden Körperseiten und linke/rechte paarige Flossen sind davon unabhängig.

## Checker und Diagnose

`textures/uv_checker.png`: nummeriertes farbiges Raster, 2048 × 2048 Pixel.
Es wurde temporär über **UV_Checker_Preview** auf alle Modellmaterialslots gelegt
und mit Cycles gerendert. Danach wurden die ursprünglichen Materialien wieder
eingesetzt. Das unbenutzte Checker-Material bleibt mit Fake User in der Blend-Datei
und kann bei Bedarf erneut einem Mesh zugewiesen werden; das Bild ist gepackt.
Die GLB enthält die ursprünglichen Platzhaltermaterialien und keine Checkertextur.

Unter `blender/diagnostics/` liegen:

- `uv_layout.png`: gemeinsamer Atlas, 2048 × 2048.
- `uv_checker_side.png`: Blick von -Y auf die rechte Körperseite.
- `uv_checker_other_side.png`: Blick von +Y auf die linke Körperseite.
- `uv_checker_top.png`: Blick von +Z, Kontrolle der Rückenmittellinie.
- `uv_validation.json`: Insel-/Flächenzuordnung, Stretch-Messung und Prüfsummen.

Die UV-Prüfung untersucht Dreiecksflächen im gemeinsamen Atlas auf positive
Überlappungsfläche und auf degenerierte UV-Dreiecke: **keine gefunden**.
Alle Koordinaten liegen innerhalb 0–1. Gemeinsame Kanten benachbarter Dreiecke
gelten nicht als Flächenüberlappung.

Das Raster ist auf den großen Körperseiten und im Kiemen-/Wangenbereich
gleichmäßig. Die flächengewichtete lokale Streckungsanisotropie der sichtbaren
Flanken liegt im Median bei etwa **1,009**, im 95%-Quantil bei **1,087** (1 ist
winkelgetreu). Über den gesamten Körper einschließlich stark gekrümmter Rand-
und Abschlussflächen liegt das 95%-Quantil bei etwa **1,36**.
An Rücken-/Bauchmitte und Schnauzenspitze bleiben lokale Verzerrung und sichtbare
Textursprünge zwischen getrennten Inseln. Sie liegen außerhalb der großen
Fotoflächen und müssen bei einer späteren fertigen Textur an den Nähten angeglichen
werden. Die Schwanzflosse bleibt übersichtlich; ihr 95%-Quantil liegt bei etwa 1,12.

## GLB/Godot-Regression

`export_godot.py` exportiert nun TEXCOORD_0. `verify_rig.py` prüft PhotoUV auf allen
Mesh-Objekten, weiterhin zusätzlich das ursprüngliche Rig und die Gewichte.
`validate_fish_import.gd` prüft UV-Arrays auf jeder importierten Surface sowie
Skeleton, Skinning, Schwimmanimation und den Loop-Übergang.

Godot erkennt weiterhin elf Meshes, 15 Bones und **Swim_Test** mit zwei Sekunden
Länge. Headless- und Grafiktest prüfen zwei vollständige Zyklen. Die UV-Splits
können beim Export zusätzliche Render-Vertices erzeugen; sie verändern weder
Blenders Mesh-Topologie noch die Gewichtung der sichtbaren Oberfläche.

Export und Startbefehle stehen in [GODOT_IMPORT.md](GODOT_IMPORT.md).
Das UV-Script auf der aktuellen Blend-Datei ausführen, falls die Abwicklung
reproduziert werden soll. Es erzeugt keine neue Fischgeometrie und ersetzt eine
bereits vorhandene PhotoUV bewusst. Die erste PreUV-Sicherung bleibt erhalten.

Es wurde keine Fotoanalyse, Segmentierung, Fotoübertragung oder finale Texturierung
durchgeführt. Das Raster dient ausschließlich zur UV-Kontrolle.
