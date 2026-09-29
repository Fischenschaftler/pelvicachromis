# Automatische Fotoanalyse mit anatomischem Template

## Bedienung und Schutz bestehender Daten

Nach **Foto auswählen** läuft ausschließlich lokal die Analyse im bestehenden
`photo_analyzer.gd`. Sie schlägt dieselbe Fischkontur und dieselben zwölf Landmarken
wie bisher vor. Punkte mit einem kleinen orangefarbenen Ring sind besonders zu
prüfen. Alle Punkte und Konturpunkte bleiben verschiebbar. Eine manuelle Korrektur
entfernt den Prüfring; **Ausrichten** erhält sämtliche Korrekturen.

**Kopf rechts / Kopf links** erzeugt ausdrücklich neue Punktvorschläge mit der
gewählten Orientierung, erhält aber die bearbeitete Maske. Die Auswahl der
fotografierten linken/rechten Körperseite ist davon unabhängig.
**Manuell beginnen** verwirft die Automatik und aktiviert die manuelle Kontur.

Projektformat bleibt Version 1. Gespeicherte Punkte und Masken haben Vorrang und
werden beim Öffnen nicht neu analysiert. Konfidenzen sind vorläufige Hinweise im
aktuellen Editor, keine neuen Pflichtfelder im Projektformat. Nach Projektöffnung
werden keine alten Prüfringe eingeblendet. Neue Fotoauswahl startet neu. Der
Revisionsschutz verwirft verspätete Worker-Ergebnisse nach Eingabe/Reset/Projektwechsel.

Mesh, PhotoUV/UV-Daten, Blender, GLB, Rig, Skeleton, 15 Bones, Gewichte und
Swim_Test bleiben unverändert. Textur-/Atlas-Berechnung bleibt unverändert;
sie erhält wie bisher Originalpixelkoordinaten und ein Polygon.

## Normalisiertes anatomisches Template

`data/anatomical_landmarks_male.json` enthält die zwölf bekannten Punktdefinitionen,
eine unterstützende Seitenkontur sowie schwach sichtbare Brust-/Schwanzflossen-
Suchbereiche. Grundlage ist die vorhandene männliche Seitenreferenz; Landmarken
wurden daran anatomisch annotiert. Die äußere Stützkontur stammt aus dem bisherigen
Konturvorschlag. Kopf zeigt in positive X-Richtung; positive Y-Richtung bedeutet
Bauchseite im 2D-Bild. Ursprung ist der Schwanzstiel, eine Einheit entspricht der
Distanz Schwanzstiel–Schnauze. Es sind keine UV-Koordinaten und keine absoluten
Fotopixel. Das Template wird auf neue Auflösungen, Größen, Spiegelungen und
leichte Neigungen transformiert; zur Laufzeit werden keine Referenzfoto-Pixel benutzt.

## Kontur und gemeinsame Template-Anpassung

1. Bild auf höchstens 360 Pixel Kantenlänge reduzieren. Farbdistanz zu den linken
   und rechten Randfarben, Helligkeit und Sättigung ergeben Vordergrundkandidaten.
   Kleine Lücken werden morphologisch geschlossen.
2. Zusammenhängende Außenkonturen anhand Fläche, Ausdehnung, Bildrand und
   Template-Übereinstimmung auswählen. Isolierte andere Komponenten werden nicht
   in die Fischmaske übernommen. Große angeschnittene Bereiche werden verworfen.
3. Falls das normale zeilenweise Hintergrundmodell keine Kontur liefert,
   zusätzlich geneigte Hintergrundschichten bei ±12° und ±24° versuchen. So
   verbindet ein schräger heller Bodengrund sich seltener mit der Fischmaske.
4. Konturen nach Bogenlänge abtasten. Hauptachsen liefern eine erste Rotation.
   Beide Kopfseiten werden geprüft. Eine begrenzte Winkelsuche und unabhängige
   Längen-/Höhenskalierung passen das gesamte Template an. Robuste Ausdehnungen
   und ein getrimmter beidseitiger Konturabstand vermindern den Einfluss einzelner
   Artefakte und schwacher Flossenkanten.
5. Die so gemeinsam platzierten zwölf Punkte bilden das anatomische Ausgangsschema.
   Fischlänge, Körperachse und ungefähre Körperhöhe folgen aus dieser Anpassung.
   Das Schwanzende wird aus mehreren stabilen hinteren Konturproben bestimmt.

## Lokale Verfeinerung

| Punkte | Verfahren |
|---|---|
| 1 Schnauze | Nahe Kopfkontur im begrenzten Fenster um den Template-Wert |
| 2 Auge | Lokale Suche um erwartete Augenlage; mehrere Pupillenradien, dunkles Zentrum, Ringkontrast in zwölf Richtungen, Position als Prior |
| 3/4 Schwanzstiel | Geglättete Querbreite senkrecht zur Körperachse; schmales anatomisches Suchfenster und breiterer Schwanzfächer dahinter |
| 5/6 Schwanzflosse | Lokale Kontur nahe den gemeinsam transformierten oberen/unteren Template-Rändern |
| 7 Rückenflosse vorne | Template-Ansatz mit geringer Konturkorrektur; springt nicht zur höchsten Flossenspitze |
| 8 Rückenflosse hinten | Lokaler hinterer Konturpunkt nahe Template |
| 9 Afterflosse vorne | Template/Bauchlage mit geringer Konturkorrektur, getrennt von der langen Spitze |
| 10 Afterflosse hinten | Lokale hintere Kontur nahe Template |
| 11 Bauchflossenansatz | Anatomischer Prior hinter/unter dem Brustflossenbereich; nur schwache Konturkorrektur |
| 12 Bauchflossenspitze | Begrenzte Kontursuche; bei größerer Abweichung niedrige Konfidenz |

Der Schwanzstiel verwendet mehrere benachbarte Querschnitte, nicht das globale
Minimum am Schwanzende. Zu schmale, breite oder weit vom Prior entfernte Treffer
werden verworfen bzw. durch Template-Werte ersetzt. Dadurch wandern die Punkte
bei schwachem Flossenrand weniger leicht auf die Schwanzflosse.

Suchradien liegen überwiegend bei 3,5–6,5 % der Körperlänge. Ansätze übernehmen
nur 45 % einer gefundenen Konturverschiebung. Raster-Sicherheit versetzt einen
Punkt bei Bedarf geringfügig ins Polygon; bei sehr dünnen kleinen Flossen genügt
ein innenliegendes Pixelzentrum. Ein völlig unsichtbarer Teil kann weiterhin eine
manuelle Maskenkorrektur benötigen.

## Transparente Flossen und Maskenprüfung

Die Brustflosse besitzt einen anatomischen Suchbereich, intern immer LOW.
Schwache Farbabweichung vom lokalen Hintergrund und Verbindung mit bereits
akzeptierten Maskenpixeln erlauben eine vorsichtige Erweiterung innerhalb dieses
Bereichs. Die Schwanzflosse erhält ebenfalls eine begrenzte Erweiterung bei
schwachem Kontrast. Keine alleinige Auswahl nach hoher Sättigung; diese würde
transparente Ränder zu stark abschneiden. Die Erweiterung darf keine separaten
fernen Flecken aufnehmen und muss wieder ein gültiges Polygon ergeben.

Dies ist keine sichere Transparenzrekonstruktion: ähnlich gefärbter Hintergrund
innerhalb eines Suchbereichs kann mit aufgenommen werden. Brustflossen und sehr
schwache Außenkanten bleiben manuell zu prüfen. Das Verfahren erweitert die
Eingabemaske, verändert aber nicht die bestehende Texturprojektion.

## Plausibilität und Konfidenz

Regeln werden im gedrehten anatomischen Koordinatensystem geprüft:
Schnauze vor Auge, Auge vor Rückenflossenansatz, Schwanzstiel vor Schwanzfächer,
obere/untere Schwanzpunkte in richtiger Reihenfolge, Bauchflossenansatz vor
Afterflossenansatz, Rückenflossenansatz oberhalb der Körperachse sowie After-/
Bauchflossenansatz darunter. Verletzungen ersetzen die betroffenen Werte durch
anatomische Template-Werte und markieren sie LOW. Dies geschieht vor und nach
der Raster-Sicherheitskorrektur.

- **HIGH:** stabile lokale Schnauzenkontur oder deutliches Pupillen-/Ringsignal.
- **MEDIUM:** plausibler Querschnitt bzw. begrenzte lokale Konturverfeinerung.
- **LOW:** reiner Template-Fallback, schwacher/mehrdeutiger Treffer, große
  notwendige Verschiebung oder unsicherer Flossenansatz. UI: kleiner Ring.
- **MANUAL:** Benutzerkorrektur; keine automatische Rückverschiebung.

Die Klassen sind heuristische Prüfhilfen, keine kalibrierten Wahrscheinlichkeiten.
Typischerweise bleiben Punkte 7, 9 und 11 LOW; bei schlechtem Foto auch Auge,
Schwanzstiel oder Bauchflossenspitze. Fehlt ein verlässliches Auge, wird das
Template-Auge angezeigt. Scheitert nur ein Teil, bleiben die anderen Vorschläge
nutzbar. Scheitert die gesamte Segmentierung, bleibt der manuelle Workflow verfügbar.

## Tests und Diagnose

Fixtures erzeugen (Entwicklung, bereits verfügbares Pillow/NumPy; keine neue
Anwendungsabhängigkeit):

```powershell
python scripts/photo_import/create_anatomy_fixtures.py
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://scripts/photo_import/validate_anatomy_variations.gd
```

Zwölf Fälle: rechts/links, ±12° Neigung, 200×200 und 4000×3000 Pixel, zwei
Fischgrößen im Bild, teilweise transparente Schwanzflosse, undeutliche Brustflosse,
schwache Bauchflossenspitze und kontrastarmes Auge. Getestet werden zwölf Punkte,
Blickrichtung, Lage im Polygon, stabile Ausrichtung, begrenzter Positionsfehler und
LOW-Fallback für schwaches Auge/Flossenspitze. Erwartete Punkte sind transformierte
manuelle Referenzannotationen. JSON enthält Abstände und Laufzeiten.

Regressionen: `validate_auto_photo_analysis.gd`, `validate_photo_import.gd`,
`validate_atlas_replacement.gd`, `scripts/project/validate_project_storage.gd`.
Sie prüfen Punkt-/Maskenkorrektur, Ausrichten, Konfidenz nach manueller Eingabe,
Texturerzeugung, Atlas Coverage, beide Farbmodi, Projekt-Speichern/Öffnen ohne
Neuanalyse, Swim_Test, Kamera/Zoom/Reset und verschiedene Fenstergrößen.

Diagnosebilder unter `godot/diagnostics/`:

- `anatomy_template_diagnostics.png`: normalisiertes Template, platziertes Template,
  finale Kontur, Körperachse, Auge, Kopfseite, zwölf Punkte und Konfidenzen.
- `anatomy_variations.png`: Übersicht aller zwölf Variationen.
- `anatomy_variations.json`: Einzelresultate, Fehler und Messwerte.
- `auto_photo_editor.png`: tatsächliche UI mit Prüfringen.

Erzeugung der Anatomiegrafiken: `scripts/photo_import/render_anatomy_diagnostics.py`.

## Grenzen

Die Tests verwenden **eine reale Aufnahme und synthetische Variationen** derselben
Aufnahme. Das Template wurde an dieser Referenz erstellt; kleine Fehler dort sind
kein Nachweis für allgemeine Genauigkeit bei fremden Fischen. Stark abweichende
Flossenstellungen, komplexer Hintergrund, mehrere Fische, angeschnittene Körper,
starke Perspektive oder vollständig unsichtbare Flossen können falsche Vorschläge
liefern. Die grobe Auflösung begrenzt feine Flossenränder. Anatomische Ansätze sind
weiterhin Prior-Schätzungen, keine zuverlässig segmentierten Strukturen.
Keine Art-/Geschlechtsbestimmung, keine Cloud und keine neue ML-Laufzeit.
