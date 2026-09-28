# Automatische Fotoanalyse

## Bedienung

Nach **Foto auswählen** wird das Foto lokal analysiert. Die Kontur und zwölf
Punkte sind Vorschläge: Vor der Texturerzeugung insbesondere Flossenansätze und
transparente Ränder prüfen. Punkte und Kontur bleiben mit denselben Werkzeugen
verschiebbar. **Ausrichten** erhält die gesetzten bzw. korrigierten Punkte.

**Kopf rechts / Kopf links** korrigiert die angenommene Blickrichtung und erzeugt
die zwölf Punktvorschläge neu, mit der aktuell bearbeiteten Kontur. Dies ändert
nicht die Auswahl „Linke/Rechte Fischseite“. **Manuell beginnen** verwirft die
Vorschläge und aktiviert die manuelle Kontur. Anschließend setzt **Ausrichten**
den Editor in den Landmark-Modus.

## Lokale Methode

`scripts/photo_import/photo_analyzer.gd` arbeitet ausschließlich mit Godot-
Bilddaten, BitMap und Geometry2D. Keine Modelle, Bibliotheken oder Dienste werden
nachgeladen. Der separate Analyse-Thread berührt keine SceneTree-Objekte.

1. Analysebild auf höchstens 360 Pixel Kantenlänge verkleinern.
2. Pro Bildzeile Farben der linken/rechten Randstreifen mitteln. Vordergrund
   anhand der RGB-Distanz zu beiden Randfarben und Helligkeit/Sättigung auswählen.
   Dadurch sind ein dunkler Aquariumhintergrund und heller Bodengrund möglich.
3. Kleine Lücken morphologisch schließen (2 Analysepixel). Zusammenhängende
   Außenkonturen extrahieren. Fläche, horizontale Ausdehnung, Seitenverhältnis,
   Abstand zum Bildrand und Bildmitte dienen zur Auswahl des wahrscheinlichsten
   einzelnen Fisches. Zu kleine/große oder angeschnittene Bereiche verwerfen.
4. Kontur zurück in Originalpixel transformieren, mit Douglas-Peucker reduzieren
   und auf eine gültige, einfache Polygonfläche prüfen. Maximal 512 Punkte.
5. Kopfseite zunächst aus der vertikalen Fülle nahe den beiden Enden bestimmen:
   Das schmalere Ende ist der Kopf-Kandidat, das höhere der Schwanzfächer.
6. Im entsprechenden äußeren Körperviertel nach einem dunklen Zentrum mit
   hellerem, möglichst geschlossenem Ring suchen. Der stärkste Kandidat über
   der Kontrastschwelle ist ein Augen-Vorschlag. Andernfalls Auge geometrisch
   hinter/oberhalb der Schnauze schätzen.
7. Vertikale Konturschnitte, Körperlänge, lokale Extrema und der schmale
   Schwanzstiel-Kandidat ergeben die zwölf Landmarken. Bei getrennten Flossen
   wählt die Schwanzstielsuche den Schnitt nahe der geschätzten Körperachse.
8. Punkte geringfügig ins Polygon versetzen: Auch ihre gerasterten Pixelzentren
   und Nachbarpixel sollen innerhalb der Maske liegen.

Die Schwellen und Längenanteile sind allgemeine Heuristiken. Es gibt keine
Dateinamen-, Referenzbild- oder fest eincodierte Fotopixel-Sonderbehandlung.
Die Analyse liefert Kontur, Kopfseite, Auge, zwölf Punkte, Achse und einfache
Konfidenzhinweise. Diese sind keine kalibrierten Wahrscheinlichkeiten; die UI
fordert immer zum Prüfen auf.

## Herkunft der zwölf Punkte

| Nummer | Punkt | Grundlage / Grenze |
|---|---|---|
| 1 | Schnauzenspitze | Kopfseitiges Kontur-Ende, leicht nach innen versetzt |
| 2 | Augenmitte | Dunkles Zentrum/heller Ring; sonst geometrische Schätzung |
| 3, 4 | Schwanzstiel oben/unten | Lokales Minimum der Körperdicke im hinteren Bereich; anatomische Zuordnung geschätzt |
| 5, 6 | Schwanzflosse oben/unten | Kontur-Extrema im hinteren Fächerbereich |
| 7 | Rückenflosse vorne | Kontur bei einem relativen Längenanteil; Ansatz geschätzt |
| 8 | Rückenflosse hinten | Hintere obere Konturspitze |
| 9 | Afterflosse vorne | Unterer Körperquerschnitt bei einem Längenanteil; Ansatz geschätzt |
| 10 | Afterflosse hinten | Hintere untere Konturspitze |
| 11 | Bauchflossenansatz | Körperlänge und untere Kontur; Ansatz geschätzt |
| 12 | Bauchflossenspitze | Unteres Kontur-Extrem im mittleren Bereich |

Auch direkt aus der Kontur gewonnene Punkte sind keine semantisch sicher
erkannten Körperteile. Fehlende, gefaltete oder überdeckte Flossen können die
Zuordnung verfälschen.

## Koordinaten, Projektverwaltung und Nebenläufigkeit

Für jede Achse gilt `Originalpixel = Analysepixel * Originalgröße / Analysegröße`.
Der bestehende Editor rechnet anschließend wie bisher zwischen Originalpixeln
und dem seitenverhältnistreuen Anzeigerechteck um. Eine verkleinerte Anzeige
verändert weder gespeicherte Landmarken noch die Originalfoto-Datei.

Automatik startet nur bei einer neuen Fotoauswahl. Projektöffnung verwendet
unverändert gespeicherte Punkte/Masken und startet **keine** Analyse; Formatversion
bleibt 1. Automatisch vorgeschlagene und manuell korrigierte Koordinaten werden
identisch gespeichert. Die ursprüngliche Foto- und Texturpipeline bleibt erhalten.

Jeder Analyseauftrag trägt die Editor-Revision. Manuelle Eingabe, Reset, ein
anderes Foto oder Projektwechsel verhindern die Übernahme eines alten Resultats.
Bei fehlgeschlagener/unsicherer Segmentierung wird ein Hinweis angezeigt und der
manuelle Maskenmodus aktiviert. „Manuell beginnen“ funktioniert auch während der
Analyse. Der 3D Viewer bleibt bedienbar. Eine neue Fotoauswahl wartet höchstens
auf den noch laufenden, größenbegrenzten Analyseauftrag, bevor sie einen neuen
startet. Texturerzeugung/Speichern warten auf die aktuelle Analyse, sofern diese
nicht manuell verworfen wurde.

## Tests und beobachtete Grenzen

Automatischer Integrationstest:

```powershell
Godot_v4.7.2-stable_win64_console.exe --path . --script res://scripts/photo_import/validate_auto_photo_analysis.gd
```

Prüft Referenz-JPG, gespiegeltes Foto, 200×200 und 4000×3000 (vergrößerter
Ausschnitt derselben Aufnahme), leeres Bild/Fallback, Drag-Korrekturen,
Ausrichten, Kopfseitenkorrektur, Projekt-Speichern/Öffnen ohne Neuanalyse,
verspätete Analyseergebnisse, Reset/Neuladen, echte Texturerzeugung,
Original/Generiert-Umschaltung, 15 Bones, laufende Animation und Kamera/Zoom/Reset.
Zusätzlich werden die bestehenden manuellen Fotoimport- und Projektverwaltungstests
weiter ausgeführt. Deren manuelle Eingabetests verwerfen explizit die Automatik.

Ergebnisse: `godot/diagnostics/auto_photo_analysis.json`; Editor und generierter
Fisch in `auto_photo_editor.png` und `auto_photo_generated.png`.
`auto_photo_analysis.png` zeigt beide Kopfseiten, Kontur, Achse, Auge und alle
zwölf Punkte. Das Entwicklungsskript `render_analysis_diagnostics.py` stellt
nur die von Godot gemessenen Ergebnisse dar (vorhandenes Pillow, keine
Laufzeitabhängigkeit der Anwendung).

Beim vorhandenen Referenzfoto folgt die Kontur Kopf, Körper und den auffälligen
Flossen überwiegend gut. Das Auge liegt nahe der fotografierten Pupillenmitte.
Die transparente Brustflosse wird nicht vollständig erfasst; helle/schwache
Flossenränder und feine Konturdetails bleiben ungenau. Die Flossenansätze sind
weiterhin zu prüfen. Texturerzeugung aus den Vorschlägen funktioniert technisch;
Flossen können bei ungenauer Vorbelegung dunkle Bereiche und Verzerrungen zeigen.

Das ist ein Test mit einer realen Aufnahme und abgeleiteten Größen/Spiegelungen,
keine Validierung an vielen unterschiedlichen Fischen. Grenzen sind insbesondere
farbähnlicher/strukturierter Hintergrund, Pflanzen, mehrere Fische, angeschnittene
Fische, große gleichfarbige Foto-Rahmen, starke Neigung, unsichtbares Auge oder
ein atypisch schmaler Schwanz. Dann sind falsche Vorschläge oder manueller
Fallback möglich. Keine Art- oder Geschlechtsbestimmung.

Mesh, GLB, Blender-Dateien, UV-Daten, Texturen und Texturberechnung werden durch
diesen Schritt nicht geändert.

## Abschlussprüfung

Sechs Vorschläge (1, 5, 6, 8, 10, 12) entstehen aus lokalen Kontur-Enden bzw.
Extrema. Fünf anatomische Zuordnungen (3, 4, 7, 9, 11) werden heuristisch aus
Kontur und Körperproportionen geschätzt. Punkt 2 wird separat über Bildkontrast
gesucht und bei Unsicherheit ebenfalls geschätzt. Auch Kontur-Extrema sind
keine garantierte anatomische Erkennung.

Der Abschlusstest verschiebt jeden der zwölf Punkte einzeln, prüft den Erhalt
der Korrektur nach Ausrichten und speichert/öffnet zusätzlich das Projekt mit
der tatsächlich generierten Textur. Der Analysezähler muss dabei unverändert
bleiben, die generierte Färbung aktiv und Swim_Test abspielbar sein.
