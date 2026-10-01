Pelvicachromis Studio - Windows Portable

Pelvicachromis Studio ist portabel und benötigt keine Installation.
Zum Start PelvicachromisStudio.exe ausführen.
Projekte werden im Unterordner projects gespeichert.
Für ein vollständiges Backup oder einen Umzug die Anwendung schließen und
anschließend den gesamten PelvicachromisStudio-Ordner kopieren.
Der Ordner muss beschreibbar sein.

Voraussetzung: Windows 10/11 (64 Bit), geeignete Grafiktreiber und eine
Direct3D-12-fähige Grafikkarte für den vorhandenen Forward+-Renderer.
Die EXE ist nicht digital signiert. Windows kann einen Warnhinweis anzeigen.

Linke Maustaste halten und bewegen: Kamera drehen. Mausrad: Zoom.
Animation starten/stoppen und Ansicht zurücksetzen über die Oberfläche.

Enthaltenes Beispiel: Unter Projekt öffnen ist der portable Build-Test mit
Referenzfoto, Maske, zwölf Landmarken und generierter Textur verfügbar.

Fisch steuern: W vorwärts, S bremsen, A/D drehen, Q/E tiefer/höher,
Shift + W schneller. Esc oder Steuerung beenden kehrt zum Betrachten zurück.

Wissenschaftlicher Stimulusmodus: F9 startet die feste orthografische
Vollbildansicht mit dem aktuell gewählten Fisch. WASD bewegt auf der
Bildschirmebene, Q/E richtet links/rechts aus, R/F verändert das Tempo.
F8 setzt zurück, Esc beendet. Kein Mauszoom oder Kameradrehen im Versuch.
Einstellungen: config/stimulus.json (nach erstem Start).
Versuchsprotokolle: data/experiments/. Fenstergrößenänderung/Fokusverlust beendet den Versuch.

Vor dem ersten Versuch F10 öffnen: sichtbare Bildschirmbreite in cm eingeben,
Fisch-Gesamtlänge einstellen und die 10-cm-Linie mit einem echten Lineal prüfen.
Bei Abweichung die gemessene Linienlänge eingeben und Messkorrektur anwenden.
Speichern unter config/display_calibration.json. Ohne gültige Kalibrierung
startet F9 keinen Versuch. Nach Monitorwechsel erneut prüfen.
Geschwindigkeit in config/stimulus.json über speed_cm_s (cm/s) einstellen.

F11 öffnet den Sequenzeditor für reproduzierbare Stimulusabläufe.
Sequenzen: data/sequences/. Leertaste pausiert, Esc beendet den Versuch.
Vorschauprotokolle: data/experiments/previews/. Echte Versuche benötigen
ein geöffnetes Fischprojekt, gültige Kalibrierung und eine Versuchs-ID.
