# Modellstand: Abgleich mit der Fotoaufnahme

**Aktueller Stand:** Das bestehende Modell besitzt jetzt ein Armature-Rig und
eine technische Testanimation. Bedienung, Bones und aktuelle Prüfungen stehen
in [RIG_NOTES.md](RIG_NOTES.md). Die folgenden Abschnitte dokumentieren die
abgeschlossene Modellierungsphase und ihre damaligen Diagnoseansichten.

## Gespeicherte Vergleichsansicht

`setup_reference_view.py` richtet die bestehende Blend-Datei ohne Änderung der
Mesh-Geometrie oder Modelltransformationen ein. Der Viewport startet in der
orthografischen Seitenkamera von -Y, mit +X nach rechts und +Z nach oben.
Das registrierte Foto liegt hinter dem Modell und verwendet 40 % Deckkraft.
Der Bildausschnitt (45, 200) bis (755, 590) der Originalaufnahme rahmt den Fisch eng.
Sichtbar sind Fish_Body (Cyan) sowie Dorsal_Fin, Caudal_Fin, Anal_Fin,
Pectoral_Fin_Left und Pelvic_Fin_Left (Gelb). Augen, Maul, rechte paarige Flossen
und Kamera-Hilfsgeometrie sind für diesen Vergleich im Viewport ausgeblendet.
Die linke Objektseite liegt nach bisheriger Benennung auf +Y; ihre Drahtlinien
werden für den gewünschten Vergleich durch den Körper hindurch angezeigt.

Aktuelle Diagnosebilder mit 2130 × 1170 Pixeln:

- `diagnostics/reference_wireframe_overlay.png`: vollständige Mesh-Kanten über Foto.
- `diagnostics/reference_overlay_clean.png`: klare Konturen ohne innere Mesh-Kanten.

Die Hauptkontur stimmt grob mit der Referenz überein. Sichtbar bleiben geglättete
Rückenflossenränder, leichte Abweichungen an der unteren Schwanzflossenkante,
an After-/Bauchflossenrändern und an der Schnauze. Die transparente Brustflosse
ist nur angenähert. Gerade Ansatzlinien im Overlay sind Grenzen separater Meshes.
Diese Diagnose hat keine dieser Formen verändert. Die identischen Vorher-/Nachher-
Prüfsummen stehen in `diagnostics/reference_view_check.json`.

Zum erneuten Einrichten die vorhandene Blend-Datei laden und dann
`setup_reference_view.py` ausführen. Die unten beschriebenen älteren Diagnose-
und Generierungsscripts erzeugen andere Ansichten; anschließend dieses Script
erneut ausführen, um die aktuelle Vergleichsansicht wiederherzustellen.

Erzeugung: `create_pelvicachromis_male_from_reference.py`.
Blender-Datei: `../models/Pelvicachromis_Male_Blockout.blend`.
Referenz: `reference/pelvicachromis_taeniatus_male.jpg`.

Die Referenz wurde aus `D:/Code/pelvicachromis/Pelvi1.jpg` übernommen.
Beide Dateien haben denselben SHA-256:
`C1A02F4BF3CF711A73950FD681C09F7F11FE6A55FA6A8D79C0F1B017E773DBBF`.
Die Referenzdatei ist von Git erfasst und wird nicht ignoriert. Es wurde
ausschließlich diese Aufnahme als visuelle Vorlage verwendet.

## Anatomische Änderungen

- Körperober- und -unterkante sowie Flossenumrisse werden aus manuell gesetzten
  Bildpunkten der Aufnahme aufgebaut. Der Rücken steigt zum Vorderkörper an;
  die Stirn fällt vor dem Auge zur kurzen Schnauze ab. Auge und Lippenform
  sind an die im Foto sichtbaren Positionen versetzt.
- Die maximale lokale Körperhöhe beträgt etwa 20,1 mm statt zuvor 28 mm.
  Das Verhältnis von horizontaler Körperlänge zu dieser Höhe ist etwa 3,1:1
  statt 2,3:1. Die größte Körperhöhe bleibt im vorderen/mittleren Bereich.
- Die Gesamtlänge bleibt bei rund 80 mm. Bei dieser festen Gesamtlänge ergibt
  die Fotovorlage etwa 62 mm Körperlänge. Der Körper wurde daher in seinen
  Proportionen gestreckt, nicht absolut länger skaliert. Ein größerer Anteil
  der Gesamtlänge entfällt jetzt auf die Schwanzflosse.
- Der schmale hintere Körperabschnitt ist länger ausgezogen. Die Schwanzflosse
  reicht horizontal über rund 20 mm statt rund 14 mm; ihre asymmetrische,
  breit gerundete Kontur folgt dem sichtbaren oberen und unteren Lappen.
- Die Rückenflosse beginnt an der im Foto sichtbaren vorderen Ansatzstelle,
  bleibt dort niedrig und besitzt eine nach hinten ausgezogene Membran.
  Ihre hintere Kante ist gebogen. Die Afterflosse besitzt eine breite Basis,
  eine größere hintere Fläche und die markante lange Spitze der Aufnahme.
- Die Bauchflossen sind schmale, nach hinten gezogene Membranen; ihre Spitze
  entspricht dem sichtbaren Bildpunkt (405, 511). Ihre Länge wurde direkt an
  das Foto angepasst, nicht unabhängig vom Foto weiter vergrößert.
- Die Brustflossen sind flache Fächer mit nur 0,08 mm zusätzlicher Wölbung.
  Ihre Ansatzstellen und die Wangen-/Kiemendeckelandeutung folgen dem Foto.

Die Tiefenproportionen sind eine Modellierungsannahme anhand der Seitenaufnahme,
keine aus mehreren Ansichten vermessene Rekonstruktion.

## Registrierung und Vergleich

Das Foto ist 800 × 800 Pixel groß. Der Bildpunkt (400, 400) entspricht dem
X/Z-Ursprung; ein Pixel entspricht 0,08/670 Metern. Die leichte Kopf-hoch-Haltung
des Fotos bleibt erhalten. +X zeigt nach vorne, Y bezeichnet die Breite, Z die
Höhe. Es gibt keine unabhängige Skalierung einzelner Fotoabschnitte.

`Reference_Photo` liegt als Image-Empty hinter dem Fisch bei Y = 12 mm.
Das JPEG ist zusätzlich in die Blend-Datei gepackt. `Side_Orthographic` ist
eine passend registrierte orthografische Kamera. In Blender zeigt Numpad 0
die Kameraansicht; Alt+Z schaltet die Durchsicht zum Foto um. Die gespeicherte
Viewport-Einstellung verwendet bereits Röntgenansicht.

`render_reference_comparison.py` prüft und speichert das erzeugte Modell und
erzeugt zwei Dateien:

- `previews/pelvicachromis_side.png`: reine orthografische Modellansicht.
- `previews/pelvicachromis_reference_comparison.png`: Foto mit 30 % Modellauflage
  und cyanfarbener projizierter Außenkontur. Dies ist nur ein Vergleichsbild,
  keine Textur auf dem Fisch.

Die großen Konturen von Kopf, Rücken, Bauch und Schwanzflosse sowie die langen
Flossenspitzen stimmen visuell deutlich besser mit der Vorlage überein.
Die hintere Rückenflossenkante und der Brustflossenfächer wurden im folgenden
Topologie-Schritt nachgezogen; die aktuellen Bilder stehen unter `diagnostics/`.
Verbleibende Unsicherheit betrifft vor allem die transparente Brustflosse. Feine Spitzen
einzelner Flossenstrahlen und ausgefranste Ränder sind weiterhin geglättet.
Die verdeckten Flossen der Gegenseite sind spiegelbildlich angenähert. Es wird
keine numerische Genauigkeitsquote oder vollständige anatomische Rekonstruktion
behauptet.

## Erhaltene Objekte

Alle elf Objekte bleiben getrennte Meshes:

- `Fish_Body`
- `Eye_Left`, `Eye_Right` (jeweils Augenwölbung und Hautrand in einem Mesh)
- `Mouth`
- `Dorsal_Fin`, `Caudal_Fin`, `Anal_Fin`
- `Pectoral_Fin_Left`, `Pectoral_Fin_Right`
- `Pelvic_Fin_Left`, `Pelvic_Fin_Right`

Hinzu kommen ausschließlich das Referenz-Empty und die orthografische Kamera
in der Sammlung `Reference_Comparison`.

## Grundlage für Rigging-Vorbereitung

Das Modell ist für den nächsten Vorbereitungsschritt geeignet: regelmäßige
Querloops am Körper, dichtere Geometrie am Kopf und unterteilte Flossenflächen.
Es umfasst 5.226 Vertices und 5.088 Flächen, überwiegend Quads. Kleine
Dreiecksfächer schließen die Körperenden; alle Flächen werden glatt schattiert.
Der Körper ist geschlossen. Flossen sind absichtlich dünne, offene Membranen;
ihre Ansätze überlappen den Körper geringfügig, sind aber nicht mit ihm verschmolzen.

Für ein späteres Schwimmrig sind die Bindung der Flossenwurzeln und die
Gewichtsverteilung zwischen Körper und separaten Flossen abzustimmen und durch
Biegetests zu prüfen. Die Augen sind anliegende Formmeshes; frei rotierende
Augäpfel würden eine weitere Anpassung benötigen. Eine eigenständig öffnende
Maulhöhle ist noch nicht modelliert.

Geprüft mit Blender 5.2.1: Erzeugung und registrierte Seiten-/Vergleichsansicht,
geschlossener Körper, Flächen ohne Nullgröße und Gesamtabmessungen.
Keine Armatur, Animation, UV-Maps, Schuppen oder Bildtexturen auf dem Fisch
erzeugt. Das Foto wird nur für Referenz und Vergleich verwendet.

## Prüfung vor dem Rigging

`diagnose_model.py` erstellt den maschinenlesbaren Bericht `diagnostics/mesh_audit.json`
und fünf Diagnosebilder. `baseline_audit.json` dokumentiert den Ausgangszustand.

- Fish_Body: 2.762 Vertices, 2.800 Flächen (2.720 Quads, 80 Abschlussdreiecke).
  69 Querschnittsringe mit je 40 Vertices ersetzen 106 unregelmäßige Ringe.
  Regionale Abstände betragen höchstens 1,244 mm; die kurze Schnauzenspitze
  erhält gezielt engere Ringe bis 0,119 mm. Die Abweichung von der bisherigen
  interpolierten Körperkontur beträgt höchstens 0,423 Pixel der Originalaufnahme.
  Dies misst den Erhalt der Modellkontur, nicht die Genauigkeit gegenüber dem Foto.
- Zehn konkave Flossen-Quads werden gezielt entlang einer geeigneten Diagonale
  trianguliert. Die übrige Flossengeometrie bleibt als unterteilte Membran erhalten.
- Rotation aller Modellobjekte: 0; Scale: 1. Körper-Origin auf der Mittellinie,
  Flossen-Origins an den Ansätzen; Augen und Maul behalten ihre lokalen Ursprünge.
- Geschlossener Körper, Augen und Maul: keine offenen oder nichtmanifold Kanten.
  Die sieben Flossen besitzen beabsichtigte offene Randkanten. Keine losen Kanten,
  Mehrfachflächen, doppelten Vertices/Flächen, Nullflächen, falsche Kantenorientierung
  oder transversalen Selbstüberschneidungen festgestellt. Geschlossene Meshes
  haben positives orientiertes Volumen.
- Körperkontakte der Rücken-, Schwanz- und Afterflossen sind eingebettete Ansätze.
  Verdeckte Rückseiten von Augen und Maul schließen die separaten Meshes im Körper.
  Keine zusätzlichen inneren Trennflächen im Körper. Der numerische Schnitt-Test
  erfasst keine koplanaren Kontakte; zusätzlich wurden die Drahtansichten geprüft.
- Ober- und Frontansicht bestätigen die seitliche Abflachung: maximal 7,37 mm
  Körperbreite gegenüber 20,11 mm lokaler Höhe; Schwanzstielbreite 1,80 mm.
- Zwei temporäre statische Biegeproben mit jeweils 30 Grad nach links/rechts:
  keine Selbstüberschneidungen, positives Volumen, kleinste Flächenfläche über
  97,6 % des Ausgangswerts. Die Prüfkopien werden entfernt; keine Pose oder
  Animation wird gespeichert. Die Körperstruktur eignet sich damit als Grundlage
  für seitliche Schwimmverformung. Tatsächliche Gewichte und Flossenbindungen
  müssen beim späteren Rigging separat getestet werden.

Die Hauptkonturen passen visuell zur Referenz. Flossenränder bleiben geglättet,
insbesondere an Rücken- und Schwanzflosse. Brustflossenrand und verdeckte
Gegenseite sind wegen Transparenz und Verdeckung nur angenähert. Auge und kleines
Maul bleiben vereinfachte Formen; die räumliche Tiefe ist durch das Seitenfoto
nicht messbar. Es wurde kein Rigging, UV-Mapping oder Texturieren durchgeführt.

### Diagnosebilder

- `diagnostics/01_side_model.png`: orthografische Modellansicht, 2400 × 2400.
- `diagnostics/02_reference_contours.png`: registriertes Foto mit Körperkontur
  in Cyan und separaten Flossenkonturen in Gelb, 2400 × 2400.
- `diagnostics/03_wire_side.png`: seitliche Drahtansicht, 2400 × 2400.
- `diagnostics/04_wire_top.png`: Drahtansicht von oben, 2400 × 1100.
- `diagnostics/05_front.png`: orthografische Frontansicht, 1600 × 1600.

Erneute Erzeugung aus dem Repository-Verzeichnis (ersetzt die generierte Blend-Datei):

```powershell
& 'D:\Programme\Blender\Blender\blender.exe' --background --factory-startup --python-exit-code 1 --python blender/create_pelvicachromis_male_from_reference.py --python blender/diagnose_model.py -- --render
```
