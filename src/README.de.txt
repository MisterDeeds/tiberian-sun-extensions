TIBERIAN SUN - ERWEITERUNGEN 1.4.0
==================================

Fan-Projekt für Command & Conquer Tiberian Sun und Feuersturm (Steam).
https://github.com/MisterDeeds/tiberian-sun-extensions

SPIELEN
1. "Tiberian Sun - Erweiterungen" starten (Desktop oder Startmenü).
2. Vorlage oder eigene Optionen wählen, "Spiel starten" klicken.
3. Im Spiel auf dem ersten Bildschirm "Feuersturm" anklicken.

RIESIGE WELTEN
Gefecht > Mehrspieler-Karte > Zufallskarte. Kartenbreite und Kartenhöhe auf "Sehr groß" stellen.
Mit der Option "Zufallskarten-Grösse: riesig" werden die Karten 200 bis 235 Felder breit und hoch,
mit "gross" bis 220 (Original: höchstens 175, mit 4 Spielern 128).
"Zufallskarten-Gelände: perfekt flach" - die ganze Karte auf einer Ebene: keine Klippen, kein Wasser, keine
Ruinen, wenig Bäume - Platz für ganze Städte. "flach" - kaum Hügel und Klippen, wenig Wasser, ein paar grosse
Hochebenen (92 % der Karte bebaubar statt 59 %); "zerklüftet" - viele Hochebenen, Hügel und Pässe.
"Zufallskarten-Tiberium: doppelt / viermal so viel" - der Generator gibt jeder Karte gleich viel Tiberium, egal
wie gross sie ist; die Option vervielfacht es, in den Feldern und bei jedem Startpunkt.
Die Regler im Zufallskarten-Dialog stehen am Anfang auf diesen Werten; du kannst sie weiter verschieben.

STÄDTEBAU
"Karte: ganze Karte von Anfang an sichtbar" - nichts Schwarzes, Unerforschtes. "Bauabstand" - deine Gebäude
bis 6 oder 10 Felder von deiner Basis entfernt bauen (Original: 2). "Viszeroiden: keine" - Infanterie, die im
Tiberium stirbt, wird nicht mehr zum Viszeroid. Meteoriten und Nebel des Krieges sind auf Zufallskarten
ohnehin aus; Ionenstürme nur mit dem Häkchen "Ionensturm" im Zufallskarten-Dialog.
Vorlage "Städtebau": riesig, perfekt flach, Tiberium x 4, ganze Karte sichtbar, keine Viszeroiden, Bauabstand 10.

STÄRKERE GEGNER
"Computergegner: stark / brutal" - mehr Geld, frühere und grössere Angriffe, harte Verteidigung ihrer Basis;
sie reparieren alle beschädigten Gebäude gleichzeitig (das Original repariert eines nach dem anderen) und
verkaufen ihre Gebäude nie.

SCHARFE GRAFIK
Standard ist die Bildschirmauflösung: das Spiel wird 1:1 gezeichnet statt gestreckt, und du siehst viel mehr
von der Karte. Die Seitenleiste reicht über die ganze Bildschirmhöhe (bis 40 Bauzeilen statt 20).
Nach dem Spiel wird die vorherige Auflösung wieder eingetragen.

SPIELTEMPO
Das Spiel rechnet so viele Bilder pro Sekunde, wie das Spieltempo erlaubt; auf "unbegrenzt" sind das mit der
Steam-Version bis 120 Bilder/s, alles läuft dann achtmal so schnell wie bei 15 Bilder/s. Die Option
"Spieltempo" stellt 60, 30 oder 20 Bilder/s ein; "unverändert" (Standard, auch bei den Vorlagen "Alles grösser"
und "Original") lässt das Tempo, wie du es hast. Mitten im Gefecht: Esc > "Spielsteuerung" >
"Spielgeschwindigkeit" - ganz rechts unbegrenzt, jede Stufe nach links langsamer (60, 30, 20, 15 ... Bilder/s),
sofort. Riesige Karten bremsen das Spiel nicht (gemessen: 235 x 235 mit 8 Spielern, konstant 120 Bilder/s).
Countdown und Angriffswellen der Missionen laufen in Spielzeit mit.

NEUE KAMPAGNEN
Neuer Feldzug > "Erweiterung - GDI: Operation Morgenröte", "Erweiterung - Nod: Kanes Erbe" oder eine
"Herausforderung". Der Schwierigkeitsgrad bestimmt Grösse und Häufigkeit der Angriffswellen.
Die Missionen wurden bei der Installation aus den Karten deines Spiels gebaut ("Missionen neu bauen" im
Startfenster baut sie erneut).

WAS WO GEÄNDERT WIRD
- Regel-Optionen: EXPAND99.MIX im Spielordner, nur solange das Spiel läuft.
- Zufallskarten (Grösse, Gelände, Tiberium), ganze Karte sichtbar, Viszeroiden, Reparaturen der Computergegner und
  Seitenleisten-Fix: nur im Arbeitsspeicher des laufenden Spiels.
- Kampagnen: TSX*.MAP und BATTLEX.INI im Spielordner.
- Auflösung und Spieltempo: [Video] und [Options] in SUN.INI, nach dem Spiel zurückgestellt.
Keine Originaldatei wird verändert. Ein Start über Steam ist immer das Original.

UPDATES
Bei jedem Start fragt der Starter GitHub nach der neusten Version. Mit "Automatisch aktualisieren" (oben rechts,
standardmässig an) wird eine neuere gleich installiert, und der Starter öffnet sich wieder; deine Einstellungen
bleiben. Nie während das Spiel läuft, höchstens ein Versuch pro Version und Tag. Ohne das Häkchen erscheint
stattdessen der Knopf "Jetzt aktualisieren". Von Hand aktualisieren: die Zeile aus dem README nochmals ausführen.

ENTFERNEN
Windows-Einstellungen > Apps > "Tiberian Sun - Erweiterungen", oder uninstall.cmd aus dem Download.

HINWEISE
- Getestet mit Game.exe 2.03 TUC (Steam). Bei einer anderen Version werden die Speicher-Patches übersprungen.
- Die Regel-Optionen gelten für Feuersturm-Spiele (Gefecht im Feuersturm-Modus, Feuersturm-Missionen,
  die neuen Kampagnen).
- Nur für das Einzelspiel.
- Technische Details: docs\FINDINGS.md


