# Getrennte Experimentatoransicht und Stimulusausgabe

## Einstieg und Aufbau

**F12** öffnet die Experimentatoransicht im normalen Hauptfenster. F9 (bisheriger manueller Stimulus), F10 (Kalibrierung) und F11 (Sequenzeditor) bleiben erhalten. Zuerst das gewünschte Fischprojekt und dessen Original-/generierte Färbung im Viewer auswählen. Anschließend in F12:

1. Experimentator- und Stimulusmonitor auswählen, **Monitorwahl speichern**.
2. Kalibrierung für den Stimulusmonitor prüfen oder öffnen.
3. Sequenz auswählen, Versuchs-ID und optional Tier-ID eingeben, Override festlegen.
4. **Versuch vorbereiten**. Die Ausgabe wird neutral geöffnet und technisch geprüft.
5. Zusammenfassung prüfen, dann **Stimulus starten**.

Die Zusammenfassung nennt Vorschau/echter Versuch, Fischprojekt, Sequenz, Kennungen, Fischlänge in cm, Kalibrierungsprofil, Hintergrund, Monitor, Auflösung, Gesamtdauer und Override. Änderungen machen die Vorbereitung ungültig. Während eines Versuchs sind Auswahl und Bearbeitung gesperrt, Pause/Abbruch/Reset bleiben verfügbar.

## Technische Trennung

Das Hauptfenster enthält `experimenter_view.gd`. Ein unabhängiges natives Godot-`Window` mit `force_native=true`, ohne Transient-/Exclusive-Beziehung und mit `unfocusable=true` enthält die Stimulusdarstellung. Es gibt keine duplizierte Sequenzlogik: Der bestehende `StimulusMode` und `SequenceRunner` werden im zweiten Fenster verwendet. Der vorhandene Fisch wird für die Sitzung umgehängt und danach inklusive Animationszustand zurückgegeben. Mesh, Rig, UVs, Texturen und Projektdatei bleiben unverändert.

Der Stimulus-SubViewport enthält nur Welt, Licht, Kamera und Fisch. Das Fenster besitzt zusätzlich eine einfarbige Neutralfläche. Es erhält keine Labels, Buttons, Landmarks, Masken oder Diagnoseansichten. Auch eine Vorschau hat dort keine Beschriftung; PREVIEW steht ausschließlich im Experimentatorfenster und Log. Die bestehende Vorschau des alten F11-Modus bleibt unverändert.

Die Stimuluskamera ist orthografisch und hat keine Orbit-Eingabe. Mausaktionen im Bedienfenster werden nicht an die Ausgabe weitergeleitet. Tastaturbefehle werden ausschließlich im Experimentatorfenster gesammelt. Das Stimulusfenster benötigt und übernimmt keinen Fokus. Der Cursor wird über dem nativen Ausgabefenster verborgen und außerhalb wieder sichtbar; dies gilt auch für den Neutralzustand.

## Monitorwahl und Kalibrierung

`config/display_setup.json` liegt über die bestehende portable Pfadauflösung neben der EXE. Es enthält Version 1, beide Monitorindizes, Entwicklungsmodus, Neutralmodus und einen Fingerabdruck der Stimulusanzeige: Bildschirmanzahl, Auflösung, Desktopposition und Skalierung. Es werden keine Betriebssystempfade gespeichert. Godot liefert hier keinen verlässlichen Gerätenamen/EDID; die UI zeigt deshalb Index, Pixelmaße, Position und Skalierung.

Geänderte Anordnung, Anzahl, Auflösung oder Skalierung erfordern eine erneute Bestätigung der Monitorwahl. Zusätzlich muss das **aktive bestehende Kalibrierungsprofil** genau zur ausgewählten Stimulusanzeige passen. Die vorhandene Kalibrierungsmathematik, das Profilformat und die Umrechnung von cm beziehungsweise cm/s bleiben unverändert. Ein Monitorindex allein genügt nicht zur Freigabe.

„Kalibrierung öffnen / prüfen“ ist nur außerhalb eines Versuchs möglich. Es schließt die Stimulusausgabe, verschiebt das Hauptfenster vorübergehend auf den ausgewählten Stimulusmonitor und öffnet die vorhandene F10-Kalibrierung. Beim Verlassen wird das Hauptfenster auf seine vorherige Position zurückgebracht. **Kalibrierungsanzeigen gehören zur Einrichtung, nicht zur Präsentation am Versuchstier.** Vor dem Versuch wieder in F12 vorbereiten.

`validate_experiment_readiness()` prüft Monitorwahl, tatsächlichen Experimentatormonitor, Fisch/Animation, verfügbare Albedotextur, laufende Fotoverarbeitung, Projekt-/Versuchskennung, Sequenz, Kalibrierung, gesamten Bewegungsweg sowie Schreibzugriff auf portable Ordner und Versuchslogging. Die Vorbereitung erzeugt anschließend das echte native Fenster und prüft Position, Modus und Größe. Beim Start werden Bereitschaft und Fensterzustand erneut geprüft. Fehler erscheinen ausschließlich im Bedienfenster.

## Live-Anzeige und Steuerung

Die Experimentatoransicht zeigt Schrittindex/Anzahl/Typ, Gesamtzeit, Schrittzeit, Restzeit, Soll-/Istgeschwindigkeit, Soll-/Istposition, Soll-/Istorientierung, Pause-/Steuerzustand, Loggingstatus, Fenster-/Monitor-ID, Viewportgröße, Vollbildstatus und Kalibrierungsprofil. Fischprojekt, Kennungen und Darstellungsgröße bleiben in der Zusammenfassung sichtbar.

Die Zustandsvorschau zeigt Position, Blickrichtung und Animationsrate als Text. Sie rendert keinen zweiten Fisch. Die Anzeige wird ungefähr zehnmal pro Sekunde aktualisiert und beobachtet nur den bestehenden Sequenzzustand. Monotone Uhr, Integrationsschritte, Sequenzformat und Reproduzierbarkeit bleiben unverändert.

- **Pause / Fortsetzen** oder Leertaste: Zeit, Bewegung und Animationsphase werden eingefroren; keine Meldung auf der Stimulusausgabe.
- **VERSUCH ABBRECHEN** oder Esc: protokollierter Abbruch, Log schließen, Ausgabe neutralisieren. Das Experimentatorfenster bleibt geöffnet.
- **Versuch zurücksetzen**: laufenden Versuch mit `operator_reset` abbrechen und Vorbereitung verwerfen. Der nächste vorbereitete Start beginnt bei Zeit, Geschwindigkeit und Animationsphase null.
- **Manual Override**: bekannte WASD-, Q/E-, R/F- und F8-Steuerung aus dem Experimentatorfenster. Bei gesperrtem Override bleiben Befehle wirkungslos. Eingriffe werden weiterhin protokolliert.

## Neutralzustand und Fehler

Konfigurierbar sind **nur Hintergrund** (Standard) und **Fisch mittig, unbewegt**. Der zweite Modus verwendet ausschließlich zur neutralen Anzeige eine Laufzeitkopie mit derselben Geometrie/Textur und Animationsphase null. Sie wird beim nächsten Start entfernt; Quelldateien werden nicht geändert. Bei technischen Fehlern wird immer nur der Hintergrund verwendet.

Überwacht werden Existenz/Sichtbarkeit, Monitorfingerabdruck, Auflösung, Fenstergröße, Vollbild, Minimierung und Viewportgröße. Kritische Änderungen, falscher Monitor oder Verlust des Stimulusmonitors brechen den Versuch ab. Verschieben des Experimentatorfensters auf einen anderen Monitor bricht ebenfalls ab. Das Programm beendet sich dadurch nicht.

Fokusereignisse werden aufgezeichnet. Verliert das Experimentatorfenster den OS-Fokus (beispielsweise Alt-Tab), wird der Versuch kontrolliert abgebrochen; gedrückte Override-Tasten werden verworfen. Normale Bedienung innerhalb des Experimentatorfensters ändert den Fokus der Stimulusausgabe nicht. Schließen der Stimulusausgabe wird als Abbruch behandelt, Schließen der Anwendung schließt das laufende Log möglichst vor dem Beenden.

Eine Anwendung kann Windows-Overlays, fremde Fenster, Bildschirmabschaltung oder einen getrennten Monitor nicht physisch kontrollieren. Die Prüfung erkennt eigene Fenster-/Anzeigeänderungen, garantiert aber keine externe optische Sichtbarkeitsmessung oder Unterdrückung sämtlicher Betriebssystemanzeigen. Für reale Versuche Benachrichtigungen und Energiesparfunktionen passend konfigurieren.

## Logging

Bestehende Sequenzereignisse und Soll-/Istwerte bleiben erhalten. Ergänzt werden `experimenter_screen`, `experimenter_window_id`, `stimulus_screen`, `stimulus_resolution`, `stimulus_window_position`, `fullscreen_state`, `stimulus_window_created`, `stimulus_window_ready`, `stimulus_window_id`, `stimulus_viewport_size`, `calibration_profile`, gespeicherte Anzeigeidentifikation und Entwicklungskennzeichnung.

Zusätzliche Ereignisse: `STIMULUS_WINDOW_READY`, `FOCUS_EVENT` mit Richtung/Quelle, `STIMULUS_FOCUS_IN/OUT`, `WINDOW_CLOSE_REQUEST`, `DISPLAY_CHANGE_EVENT` und `CALIBRATION_WARNING`. Abbrüche besitzen den konkreten Grund, beispielsweise `stimulus_monitor_lost`, `stimulus_resolution_changed`, `stimulus_minimized` oder `application_focus_lost`. Zeit und aktueller Schritt stammen aus dem bestehenden Logger/Runner. Vorschauprotokolle bleiben getrennt unter `data/experiments/previews/`, echte Versuche unter `data/experiments/`.

## Einmonitor-Entwicklung und Grenzen

Bei nur einem Monitor **Einmonitor-Entwicklung** speichern und **Vorschau** aktivieren. Die Ausgabe ist ein separates Fenster mit bis zu 960×600 Pixeln. Physikalische Skalierung bezieht sich weiterhin auf den Bildschirm, nicht auf eine automatisch gestreckte Fischgröße. Der geringere sichtbare Bereich kann große Sequenzwege ausschließen.

Ein echter Versuch wird bei identischen Monitoren oder aktiviertem Entwicklungsmodus mit verständlicher Meldung blockiert. So verdeckt die Ausgabe nicht versehentlich die benötigte Experimentatorsteuerung. Vollbild kann mit „Stimulusfenster testen“ separat geprüft werden. Die Auswahl erfolgt in Godot mit nullbasierten Indizes; Windows-Anzeigenummern können davon abweichen.

Die portable EXE benötigt keine zusätzlichen Laufzeitbibliotheken. Sequenzen, Monitorwahl, Profile, Projekte und Logs bleiben im portablen Ordner. Nach einem Rechner-/Monitorwechsel müssen Monitorwahl und Kalibrierung neu geprüft werden.

## Tests und Hardwaregrenze

`godot --path . --script res://scripts/experiment/run_experimenter_validation.gd` prüft native Fenstertrennung, UI-Abwesenheit, Auswahl/Speicherung, Bereitschaft, Pause, Ablauf, Abbruch, Neutralmodi, Override aus dem Hauptfenster, Logging, Fokuswechsel, reale Fenstergrößenänderung, Minimierung und Vollbild. Zusätzlich laufen die bisherigen Sequenz-, Reproduzierbarkeits-, Kalibrierungs- und Stimulusprüfungen. Weitere Regressionen decken Fotoimport, Analyse, Texturierung, Projekte und portable Speicherung ab.

Auf dem Entwicklungsrechner ist **ein physischer Monitor** angeschlossen. Zwei native Fenster, Vollbild, Größenänderung und Fokusübergabe werden tatsächlich ausgeführt. Ein physisch zweiter Monitor und dessen Abziehen können hier nicht geprüft werden; Monitorverlust/Änderung werden über den realen Überwachungspfad mit fehlendem Index beziehungsweise veränderten Anzeigedaten simuliert. Vor einem wissenschaftlichen Einsatz bleibt ein Test am tatsächlichen Zweimonitor-Aufbau erforderlich. Diagnosebilder und maschinenlesbare Berichte liegen unter `godot/diagnostics/experimenter_*`.
