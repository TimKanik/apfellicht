# Forschung: Wie corebrightnessd Logo und Tastatur steuert

Gemessen am 12.11.2026 auf MacBook Pro Mac17,13 (M5 Pro, PROLED XDR), macOS 27.2. Alles private,
undokumentierte API, kann sich mit jedem macOS-Update ändern. Grundlage: die Notizen von LogoLight
(`docs/corebrightnessd.md` in github.com/Ark0N/LogoLight, MIT), ergänzt um eigene Messungen.

## Rechenweg fürs Logo

```
PWMNitsPreRestriction = LEPWMBrightnessNitsMapping(Display-Nits)
AppliedNits           = clamp(Pre, Min(Lux), Max(Lux))      # LEPWMLuxTo{Min,Max}NitsRestrictionMapping
FinalNits             = AppliedNits × Factor × NitsMultiplier
```

`Factor` ist die Überblendung über `DisplayLogicalState`. An ihr hängt auch die Tastatur, deshalb
nutzt Apfellicht sie nie (anders als LogoLight).

## Eigene Messungen

| Test | Ergebnis |
|---|---|
| Alle drei Tabellen flach auf 600 Nits | Erst keine Wirkung. Nach Änderung der Displayhelligkeit: 165 → 600 Nits (Duty 15 → 53 %). Blieb bei weiteren Displayänderungen fest. Tastatur unverändert 35 %. |
| Auslöser für Neuberechnung | `DisplayServicesSetBrightness` mit dem **gleichen** Wert genügt (unsichtbar). `LEBacklightMode`, `LEPWMFollowTau` lösen nichts aus. Während das Display wegen Inaktivität gedimmt ist, wird nichts neu gerechnet. |
| Lux-Grenzen | Werden nur bei einem neuen Sensorwert neu berechnet (`handleALSEvent`). Sensor abgedeckt: Min-Grenze rampt in ~4 s weich auf den neuen Tabellenwert. Danach bleibt sie, solange die Tabelle flach ist. |
| Tastatur vs. Display | Display auf 90/30/10 %: Tastatur-Duty blieb bei 0,350. Die Tastatur hängt nicht an der Displayhelligkeit. Apples Regler 100 % = 35 % Duty. Automatik war aus. |

## Was Apfellicht deshalb tut

- Haupttabelle flach auf den Zielwert, Min-Grenze flach 0, Max-Grenze flach 1000. Danach `nudgeRecompute`.
- Werte unter der alten Min-Grenze (bei 220 lux ca. 150 Nits) greifen erst beim nächsten Lichtwechsel.
  Die App zeigt dann einen Hinweis.
- Alle 10 s prüfen, ob die Tabellen noch stehen, sonst neu setzen (Neustart von corebrightnessd, Aufwachen).
- Tastatur über `KeyboardBrightnessClient setBrightness:forKeyboard:`, Automatik aus.
- Deckel zu: `ClamshellUpdate = 0` global, danach `1` an Tastaturen und externe Displays (gegen True-Tone-Tönung).

## Werkstabellen (für Reset)

```
LEPWMBrightnessNitsMapping           [0,0] [0.1,12.5] [16.84,12.5] [34.12,28.62] [50,45.37] [69.11,65.52] [140,150] [300,300] [600,1000] [3.4e38,1000]
LEPWMLuxToMaxNitsRestrictionMapping  [0,180] [190,1000] [3.4e38,1000]
LEPWMLuxToMinNitsRestrictionMapping  [0,12.5] [190,150] [560,300] [1350,1000] [3.4e38,1000]
```

Notfall-Reset ohne App: `make reset`.
