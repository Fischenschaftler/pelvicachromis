# Vollständige generierte Atlas-Abdeckung

## Ursache

Der Fehler war hauptsächlich ein Atlas-Füllproblem, nicht das Durchscheinen eines
zweiten Originalmaterials. `Body.bake` begann mit einer Kopie der Basistextur.
Außerhalb gültiger Fotopixel und in den konservativ ausgesparten Flossenansätzen
wurde mit `continue` abgebrochen: dort blieb die alte RGB-Färbung stehen. Das ist
am Rücken besonders sichtbar. Die ursprüngliche Körper-Alphakomponente wurde
ebenfalls übernommen; Körper-Padding fehlte vollständig. Bei den Flossen gab es
nur 16 Pixel Padding, sodass weiter entfernte ungefüllte Bereiche alt blieben.

Die GLB-Prüfung ergab je eine Surface für Körper und alle sieben Flossen. Augen
und Mund haben mehrere Surfaces. Im geprüften Modell gibt es keine übergeordnete
Material-Override, die die Surface-Zuweisung verdeckt. Die bestehenden separaten
Augen-/Mundmaterialien bleiben bewusst wie bisher erhalten; alle Körperflächen
(einschließlich Körper-Endkappen) und sieben Flossen verwenden den neuen Atlas.

## Behebung

- `scripts/atlas_coverage.gd`: Mehrquellen-Dilation aus erfolgreich generierten
  Pixeln bis zur vollständigen Füllung des jeweiligen reservierten UV-Slots.
  Keine RGB-Fallbacks aus der Originaltextur. Slots bleiben getrennt; dadurch
  werden andere Inseln nicht überschrieben. Auch Filter-/Mipmap-Ränder sind gefüllt.
- `scripts/body_texture_baker.gd`: gültige Körperpixel immer Alpha 1; abgewiesene
  Samples und beide Endkappen aus generierten Farben ergänzen. Wenn eine kleine
  Endkappe überhaupt keine gültigen Samples hat, generierter Körper-Farbmittelwert.
- `scripts/fin_texture_baker.gd`: vollständige Slot-Füllung statt begrenztem
  16-Pixel-Padding. Nur die bereits bewusst angelegte Flossen-Transparenz wird
  übernommen; Freistellungs-Alpha dient zur Auswahl gültiger Fotopixel, erzeugt
  aber keine zusätzlichen Löcher im Flossenmaterial.
- `scripts/photo_import/photo_import_controller.gd`: eigene tiefe Materialkopie
  pro Mesh/Surface, generierter Albedo-Atlas, weiße Albedo-Multiplikation, kein
  zusätzlicher Materialpass; Körper explizit undurchsichtig. Originalfärbung stellt
  die exakt gespeicherten Material-Overrides wieder her.
- `scripts/photo_import/texture_projection.gd`: Körper-Füllstatistik und
  `atlas_fill_version=1` in der Generierungsmetadatenstruktur.

Projektformat bleibt Version 1. Alte gespeicherte generierte PNGs werden nicht
still verändert. Beim Öffnen erscheint für ältere Generationen ein Hinweis:
**Textur erzeugen** erneut ausführen und anschließend das Projekt speichern.
Originalfoto und Basistextur bleiben erhalten.

## Prüfung und Diagnose

`res://scripts/photo_import/validate_atlas_replacement.gd` startet den echten
Viewer und prüft:

1. Automatische Referenzpunkte und Maskenerzeugung als Eingabe.
2. Einfarbiges Cyan-Foto als eindeutiges Kontrollsignal bei 512 Pixel Atlasgröße:
   alle reservierten Körper-/Flossenslots haben ausschließlich die neue RGB-Farbe;
   sämtliche Körperpixel sind deckend. So lassen sich alte Farben auch dann
   erkennen, wenn echtes Referenzfoto und Basistextur ähnlich aussehen.
3. Drei Wechsel Original → Generiert → Original, pro Surface eigene Material-ID,
   Dorsal_Fin eingeschlossen, unveränderte Importmaterialien.
4. Echte Fotoprojektion mit 2048 Pixeln, Atlas/Alpha und Rückenansicht.
5. Swim_Test nach Umschaltung, 15 Bones, unveränderte Mesh-Arrays.

`godot/diagnostics/atlas_replacement_validation.json` enthält alle Mesh-/Surface-
Materialien, die Runtime-Zuweisungen, Füllstatistiken und Testergebnisse.
`atlas_before_after.json` vergleicht denselben synthetischen Fotofarbtest mit dem
vorherigen Code aus Git. Gezählt wird der ganze reservierte Slot, also auch
Padding außerhalb der tatsächlich belegten Dreiecke; nicht jede vorher gezählte
Originalfarbe war auf dem Mesh sichtbar.

Bilder:

- `atlas_fill_comparison.png`: Atlas vor/nach Korrektur mit Cyan-Kontrollsignal.
- `atlas_sentinel_view.png`: tatsächliche 3D-Materialzuweisung, Rücken schräg.
- `generated_atlas_fixed.png` und `generated_atlas_alpha.png`: echter neuer Atlas.
- `generated_back_fixed.png` und `original_back.png`: beide Farbmodi.

Die Ergänzung verhindert Originalfarbreste und ungewollte Körper-Alpha-Löcher.
Sie rekonstruiert keine fehlende fotografische Zeichnung: In größerflächig
verdeckten/ausgesparten Regionen können gestreckte Schuppen oder Farbstreifen
entstehen. Anatomische Flossenansätze bleiben von der Landmark-Qualität abhängig.
Die bewusst vorhandene Flossen-Transparenz bleibt bestehen. Keine Mesh-, UV-,
Rig-, Blender- oder GLB-Änderungen.

## Abschlussprüfung 29.09.2026

Alle vier Suiten erneut bestanden: `validate_atlas_replacement.gd`,
`validate_auto_photo_analysis.gd`, `validate_photo_import.gd` und
`validate_project_storage.gd`. Fehlerlogs leer. Kamera/Zoom/Reset, Swim_Test,
beide Materialwechsel, neue Texturerzeugung sowie Speichern/Öffnen geprüft.

Zusätzliche Ansichten: `atlas_final_left.png`, `atlas_final_right.png`,
`atlas_final_back.png`, `atlas_final_perspective.png`; zusammen in
`atlas_final_views.png`. Körper, Rückenflossenübergang, Bauch, Schwanzstiel und
alle Flossen zeigen keine alte Körperfärbung mehr. Augen und separates Munddetail
bleiben wie bisher außerhalb der Fotoprojektion.

Ein vorhandenes, vor dem Fix gespeichertes Integrationsprojekt aus
`user://auto_analysis_tests/` wurde geöffnet, neu texturiert, als separate
Projektkopie gespeichert und erneut geöffnet. Die neue Textur blieb bytegleich,
die generierte Färbung aktiv und der Analysezähler unverändert. Pfade und Resultat
stehen unter `legacy` in `atlas_replacement_validation.json`;
`atlas_final_legacy.png` zeigt das wieder geöffnete Ergebnis. Für diesen erweiterten
Regressionstest muss ein älteres gespeichertes Testprojekt vorhanden sein.

`atlas_final_alpha_check.json`: sämtliche Körper-Slots Alpha 255/255; alle sieben
Flossen-Slots enthalten weiterhin teilweise transparente Pixel. Keine Alpha-0-
oder vollständig schwarzen RGB-Pixel in den untersuchten Körper-/Flossen-Slots.
Natürlich dunkle Zeichnungen werden dadurch nicht als Fehler behandelt.

Bekannte optische Grenzen: verlängerte/gestreckte Schuppenzeichnungen in den
ergänzten Rücken- und Schwanzstielbereichen, sichtbare Übergänge zwischen
separaten Flossen und Körper, vereinfachte Brustflossen und Streifen in den
Bauchflossen. Dies sind Projektions-/Darstellungsgrenzen, keine stehengebliebenen
Originalfarben oder ungefüllten Atlas-Löcher.
