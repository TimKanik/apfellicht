# Research: how corebrightnessd drives the logo and the keyboard

Measured on 12 November 2026 on a MacBook Pro Mac17,13 (14", M5 Pro, PROLED XDR), macOS 27.2. All of this is private,
undocumented behaviour and may change with any macOS update. It builds on the notes of
[LogoLight](https://github.com/Ark0N/LogoLight) (`docs/corebrightnessd.md`, MIT), extended with our own measurements.

## How the logo brightness is computed

```
PWMNitsPreRestriction = LEPWMBrightnessNitsMapping(screen nits)
AppliedNits           = clamp(Pre, Min(lux), Max(lux))      # LEPWMLuxTo{Min,Max}NitsRestrictionMapping
FinalNits             = AppliedNits × Factor × NitsMultiplier
```

All three tables are read and written through `BrightnessSystemClient` (`copyPropertyForKey:` /
`setProperty:forKey:`) in `CoreBrightness.framework`, without root or entitlements.

`Factor` is the fade driven by `DisplayLogicalState`. The keyboard backlight follows the same signal, so every fade
LogoLight uses to hold a level dims the keyboard a little. Apfellicht never touches `Factor`.

## Measurements

| Test | Result |
|---|---|
| All three tables written flat at 600 nits | No effect at first. After a change of screen brightness: 165 → 600 nits (PWM duty 15 → 53 %). Stayed there through further screen changes. Keyboard unchanged at 35 % duty. |
| What makes the daemon recompute | `DisplayServicesSetBrightness` with the **same** value it already has is enough, and invisible. Writing `LEBacklightMode` or `LEPWMFollowTau` doesn't. While the screen is dimmed for inactivity, nothing is recomputed. |
| Lux limits | Only recomputed when the light sensor reports a new value (`-[CBLEPWMAutoBrightnessModule handleALSEvent:]`). With the sensor covered, the minimum ramped smoothly to the new table value within about 4 s and stayed there while the table is flat. |
| Keyboard vs. screen | Screen set to 90, 30 and 10 %: keyboard duty stayed at 0.350. The keyboard doesn't follow the screen. Apple's slider at 100 % gives 35 % duty. |

## What Apfellicht does

- The brightness table is flat at the target, the lux minimum flat at 0 and the lux maximum flat at 1000 nits. Then it
  triggers a recompute.
- A target below the old lux minimum (about 150 nits at 220 lux) is reached at the next light change. The menu says so
  until then.
- Every 10 s it checks that the tables are still in place and writes them again if not (e.g. after `corebrightnessd`
  restarted or the Mac woke up).
- At first launch it saves the Mac's own factory tables for *Restore Apple default*, since other models may differ.
- Keyboard: `KeyboardBrightnessClient setBrightness:forKeyboard:`, with automatic brightness turned off.
- Lid closed: `ClamshellUpdate = 0` to everything, then `1` to the keyboards and external displays only, so the keyboard
  stays dark and external displays don't switch on True Tone for the covered light sensor.

## Factory tables on Mac17,13

```
LEPWMBrightnessNitsMapping           [0,0] [0.1,12.5] [16.84,12.5] [34.12,28.62] [50,45.37] [69.11,65.52] [140,150] [300,300] [600,1000] [3.4e38,1000]
LEPWMLuxToMaxNitsRestrictionMapping  [0,180] [190,1000] [3.4e38,1000]
LEPWMLuxToMinNitsRestrictionMapping  [0,12.5] [190,150] [560,300] [1350,1000] [3.4e38,1000]
```

Emergency reset without the app: `make reset`.
