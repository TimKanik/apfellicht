# Apfellicht

Menüleisten-App für das leuchtende Apple-Logo und die Tastaturbeleuchtung am MacBook Pro mit PROLED XDR
Display. Beide bekommen eine feste Helligkeit per Regler, unabhängig von Displayhelligkeit und Umgebungslicht.

- Menüleiste: Regler und Schalter für Logo und Tastatur, Logo bei zugeklapptem Deckel (mit externem Monitor),
  Autostart, „Apple-Standard wiederherstellen“
- Kontrollzentrum: je ein Schalter für Logo und Tastatur
- Beenden lässt die Werte bis zum Neustart stehen, beim Anmelden setzt die App sie neu

```sh
make install   # bauen, nach /Applications, starten
make status    # was corebrightnessd gerade rechnet
make reset     # Notfall: Apples Werkstabellen zurück
```

Wie es funktioniert: [docs/forschung.md](docs/forschung.md). Build-Aufbau der Kontrollzentrum-Erweiterung und
Teile der Forschung nach LogoLight von Ark0N (MIT, siehe docs/LICENSE-LogoLight.txt).
