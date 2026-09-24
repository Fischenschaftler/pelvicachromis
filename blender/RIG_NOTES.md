# Pelvicachromis: technisches Schwimmrig

**Pipeline inzwischen geprüft:** Der GLB-Export und die Godot-Testszene sind
fertig. Aktuelle Importergebnisse und Startanleitung stehen in
[GODOT_IMPORT.md](../docs/GODOT_IMPORT.md). Die Exportvorbereitung unten
dokumentiert den vorherigen Rigging-Abschluss.

Datei: `../models/Pelvicachromis_Male_Blockout.blend`.
Erzeugung: `rig_pelvicachromis.py`, Prüfung: `verify_rig.py`.
Die vorhandenen elf Meshes, ihre Vertices und Flächen bleiben unverändert.
Fish_Body besitzt weiterhin 2.762 Vertices und 2.800 Flächen.

## Bones und Bindung

Armature: **Pelvicachromis_Rig**, 15 Bones.

| Bones | Aufgabe |
| --- | --- |
| Root | Gesamtes Rig verschieben/drehen; kein direkter Deform-Bone |
| Body_01 → Body_02 → Body_03 → Body_04 → Tail_01 → Tail_02 → Tail_Fin | Verbundene Körperkette, Kopf nach +X; Schwanz nach -X |
| Dorsal_01, Dorsal_02 | Vorderer/hinterer Teil der Rückenflosse, unter Body_02 bzw. Body_04 |
| Anal_Fin | Afterflosse, unter Body_04 |
| Pectoral_Fin_Left, Pectoral_Fin_Right | Unabhängige Brustflossen, unter Body_01 |
| Pelvic_Fin_Left, Pelvic_Fin_Right | Unabhängige Bauchflossen, unter Body_01 |

Fish_Body, sämtliche sieben Flossen, Eye_Left, Eye_Right und Mouth sind direkt
an die Armature geparentet und besitzen jeweils einen Armature-Modifier.
Der Kopf sowie Augen und Maul folgen dem stabilen Body_01. Am Körper werden
je Vertex höchstens zwei benachbarte Bones weich ineinander überblendet.
Die Loop-Amplitude nimmt von 0 Grad vorne auf 5 Grad am Tail_02 und 6 Grad
am Tail_Fin zu. Die Bone-Winkel sind lokal und addieren sich entlang der Kette.

Die Gewichte wurden deterministisch als normalisierte Vertex Groups angelegt.
Flossenwurzeln folgen der Körperbindung; freie Membranbereiche gehen in die
eigenen Flossen-Bones über. Schwanz-, After- und Brustflossengewichte werden
räumlich verteilt, um abrupte Übergänge an zusammenlaufenden Mesh-Streifen zu
vermeiden. Brustflossen schwenken im Test um die Linie ihres Ansatzes.
Maximal vier Gewichte je Vertex, lineares Skinning, keine Constraints oder Driver.

## Bedienung

1. Blend-Datei öffnen. Gespeichert ist **Frame 0**, vollständig neutrale Pose.
   Die ursprüngliche Kopf-hoch-Ausrichtung der Fotovorlage bleibt erhalten.
2. Für den Schwimmtest zu **Frame 1** wechseln und Leertaste drücken.
   **Swim_Test_Loop** ist bereits die aktive Action. Wiedergabe: Frames 1–60,
   30 FPS. Frame 61 wiederholt Frame 1 und schließt den Zyklus bei 2 Sekunden.
3. Frame 0 dient ausschließlich der neutralen Inspektion und gehört nicht zum
   definierten Action-/Exportbereich 1–61. Nach dem Test zu Frame 0 zurückkehren.
4. Die separate Action **Rig_Test_Pose** im Dope Sheet / Action Editor wählen
   und Frame 1 einstellen: leichte S-Biegung, stärkere Schwanzrotation,
   Schwanzflosse und leicht ausgeschwenkte Brustflossen. Diese Action verändert
   keine Rest-Bones. Anschließend wieder Swim_Test_Loop und Frame 0 wählen.
5. Für manuelle Posen Pelvicachromis_Rig auswählen und in den Pose Mode wechseln.
   Seitliche Körperbiegung erfolgt um die globale Z-Richtung. Root bewegt den
   gesamten Fisch. Frame-Wechsel überschreiben manuelle Änderungen durch die
   aktive Action; zum freien Posen die Action zuvor lösen.

Die Testpose und der Loop sind technische Prüfungen, keine finale Animation.
Die Testpose bleibt über einen Fake User als eigene Action gespeichert.

## Diagnose und Ergebnis

- `diagnostics/rig_side.png`: neutrales Modell seitlich mit projizierten Bones.
- `diagnostics/rig_pose_test.png`: Testpose schräg von oben, damit die seitliche
  S-Kurve sichtbar ist. Cyan: Körperkette; Gelb: Flossen und Root. Verdeckte Bones
  werden zur Diagnose ebenfalls eingeblendet.
- `diagnostics/rig_validation.json`: Gewichte, Geometrie-Prüfsummen und Messwerte.

Alle 61 Loop-Stellungen wurden auf endliche Koordinaten und Flächenänderungen
geprüft. Die Körperflächen bleiben zwischen 97,35 % und 102,47 % ihrer neutralen
Fläche; über alle Meshes liegt der Bereich bei etwa 95,10–105,44 %. Keine
kollabierten Flächen. Alle Meshes stimmen an Frames 1 und 61 positionsgleich
überein. Neutrale Abweichung zur ungeänderten Geometrie unter 0,00001 mm.

An neun verteilten Loop-Stellungen wurden alle Meshes auf transversale
Selbstüberschneidungen geprüft: keine gefunden. Auch die separate stärkere
Testpose besteht diese Prüfung; Körperflächen etwa 92,71–106,01 %.
Die Diagnoseansichten zeigen keine auffälligen Risse oder harten Körperknicke.
Die numerische Schnittprüfung schließt koplanare Kontakte aus. Kleine eingebettete
Flossenansätze sowie die separaten Augen-/Maulabschlüsse bleiben wie zuvor erhalten.
Extreme Posen außerhalb dieser Tests und gegenseitige Flossenkollisionen sind
nicht allgemein abgesichert; das Rig enthält keine Kollisionsautomatik.

## Exportvorbereitung für Godot 4

Strukturell geeignet: ein FK-Skelett, eindeutige Namen, direkte Mesh-Armature-
Bindungen, maximal vier normalisierte Gewichte, lineares Skinning, direkt
gekeyte Quaternion-Rotationen und keine Blender-spezifischen Constraints.
Die Mesh-Form wurde nicht angewendet oder in eine Testpose gebacken. UVs oder
Texturen wurden nicht erzeugt.

glTF/GLB ist der von Godot empfohlene 3D-Austauschweg:
[Godot: verfügbare 3D-Formate](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).

Noch kein Export durchgeführt. Beim späteren Export nur Armature und elf
Modell-Meshes auswählen, Referenz/Kamera ausschließen; Skinning und Animation
aktivieren. Nur Swim_Test_Loop, Bereich 1–61, mit 30 FPS sampeln; Frame 0 und
Rig_Test_Pose nicht in den Schwimmclip aufnehmen. In Godot den Clip als Loop
konfigurieren und Skinning, Achsenumsetzung, 8-cm-Maßstab und die beidseitige
Darstellung der offenen Flossen prüfen. Dieser Importtest steht noch aus.

## Reproduzierbarkeit

Das Rig-Script wird auf der bestehenden ungeriggten Blend-Datei ausgeführt.
Bei vorhandenem Rig bricht es standardmäßig ab. `-- --rebuild` ersetzt bewusst
die generierten Bones, Gewichte und beiden Actions; nicht nach manueller
Rig-Bearbeitung verwenden. Es erzeugt keine neue Fischgeometrie.

Gespeicherten Stand ohne Änderungen prüfen:

```powershell
& 'D:\Programme\Blender\Blender\blender.exe' --background models/Pelvicachromis_Male_Blockout.blend --python-exit-code 1 --python blender/verify_rig.py
```

Die älteren Modellgeneratoren erzeugen eine neue ungeriggte Szene. Sie sind
keine Aktualisierungsroutine für die jetzt geriggte Blend-Datei.
