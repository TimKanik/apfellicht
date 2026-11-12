import Foundation

/// Das leuchtende Apple-Logo auf der Rückseite (MacBook Pro mit PROLED XDR Display).
///
/// So rechnet `corebrightnessd` (gemessen, siehe docs/forschung.md):
///
///     PWMNitsPreRestriction = LEPWMBrightnessNitsMapping(Display-Nits)
///     AppliedNits           = clamp(Pre, Min(Lux), Max(Lux))
///     FinalNits             = AppliedNits × Factor × NitsMultiplier
///
/// Apfellicht schreibt alle drei Tabellen flach: Die Helligkeitstabelle liefert für jede
/// Displayhelligkeit denselben Zielwert, die Lux-Grenzen werden auf 0 und 1000 Nits geöffnet. So
/// hängt das Logo weder am Display noch am Umgebungslicht. `Factor` (die Überblendung, an der auch
/// die Tastatur hängt) wird nie angefasst.
///
/// Die Haupttabelle wirkt, sobald der Dienst neu rechnet (`nudgeRecompute`). Die Lux-Grenzen rechnet
/// er nur bei einem neuen Wert des Lichtsensors neu, also beim ersten Lichtwechsel nach dem Setzen.
@MainActor
public final class LogoControl {
    enum Key {
        static let mode = "LEBacklightMode"
        static let nitsMapping = "LEPWMBrightnessNitsMapping"
        static let maxMapping = "LEPWMLuxToMaxNitsRestrictionMapping"
        static let minMapping = "LEPWMLuxToMinNitsRestrictionMapping"
        static let clamshell = "ClamshellUpdate"
        static let daemonLidState = "CBClamshellState"
    }

    /// Oberes Ende der Tabellen. So schreibt Apple selbst den letzten Stützpunkt (FLT_MAX).
    static let top = 3.402823e38
    /// Höchste Logo-Helligkeit, die Apples eigene Tabellen vorsehen.
    public static let maxNits = 1000.0

    /// Apples Werkstabellen, ausgelesen auf Mac17,13 mit macOS 27.2.
    static let factory: [String: [[Double]]] = [
        Key.nitsMapping: [[0, 0], [0.1, 12.5], [16.84, 12.5], [34.12, 28.62], [50, 45.37], [69.11, 65.52],
                          [140, 150], [300, 300], [600, 1000], [top, 1000]],
        Key.maxMapping: [[0, 180], [190, 1000], [top, 1000]],
        Key.minMapping: [[0, 12.5], [190, 150], [560, 300], [1350, 1000], [top, 1000]],
    ]

    private let service: BrightnessService

    public init(service: BrightnessService) {
        self.service = service
    }

    /// Ob dieser Mac ein ansteuerbares Logo hat.
    public var isAvailable: Bool { service.value(Key.mode) != nil && !service.logoState.isEmpty }

    // MARK: An / Aus

    public var isOn: Bool { (service.value(Key.mode) as? NSNumber)?.intValue != 0 }

    /// 0 aus, 2 an. Der Dienst speichert das selbst (wie Apples `defaults write … LEBacklightMode`).
    public func setOn(_ on: Bool) {
        service.set(NSNumber(value: on ? 2 : 0), Key.mode)
    }

    // MARK: Feste Helligkeit

    /// Reglerwert 0–1 → Logo-Nits. Quadratisch, damit der Regler sich gleichmäßig anfühlt.
    public static func nits(forLevel level: Double) -> Double {
        let l = max(0, min(1, level))
        return (l * l * maxNits * 100).rounded() / 100
    }

    /// Setzt eine feste Helligkeit (0–1).
    public func apply(level: Double) {
        let target = Self.nits(forLevel: level)
        service.set(flat(target), Key.nitsMapping)
        if !isFlat(Key.minMapping, 0) { service.set(flat(0), Key.minMapping) }
        if !isFlat(Key.maxMapping, Self.maxNits) { service.set(flat(Self.maxNits), Key.maxMapping) }
        service.nudgeRecompute()
    }

    /// Prüft, ob der Dienst noch mit Apfellichts Tabellen rechnet, und setzt sie sonst neu, etwa nach
    /// einem Neustart von `corebrightnessd` oder dem Aufwachen. Liefert `true`, wenn es nachsetzen musste.
    @discardableResult
    public func ensure(level: Double) -> Bool {
        let target = Self.nits(forLevel: level)
        let tablesOK = isFlat(Key.nitsMapping, target) && isFlat(Key.minMapping, 0) && isFlat(Key.maxMapping, Self.maxNits)
        if !tablesOK {
            apply(level: level)
            return true
        }
        if let pre = service.logoState("PWMNitsPreRestriction"), abs(pre - target) > 0.5 {
            service.nudgeRecompute()
            return true
        }
        return false
    }

    /// Ob der Zielwert noch an Apples alten Lux-Grenzen hängt. Das löst sich beim nächsten
    /// Lichtwechsel am Sensor von selbst.
    public func waitsForLightChange(level: Double) -> Bool {
        let target = Self.nits(forLevel: level)
        guard let min = service.logoState("MinNitsRestriction"),
              let max = service.logoState("MaxNitsRestriction") else { return false }
        return min > target + 0.5 || max < target - 0.5
    }

    public var appliedNits: Double? { service.logoState("AppliedNits") }

    /// Zurück zu Apples Automatik: Werkstabellen, Logo an.
    public func restoreApple() {
        for (key, table) in Self.factory { service.set(table, key) }
        setOn(true)
        service.nudgeRecompute()
    }

    // MARK: Deckel zu

    /// Sagt dem Logo, der Deckel sei offen, damit es bei zugeklapptem Deckel leuchtet. Tastatur und
    /// externe Displays bekommen gleich danach wieder „zu“: Die Tastatur bleibt dunkel, und die
    /// Displays schalten kein True Tone für den abgedeckten Lichtsensor an.
    public func overrideLid() {
        service.set(NSNumber(value: false), Key.clamshell)
        service.setKeyboards(NSNumber(value: true), Key.clamshell)
        service.setDisplays(NSNumber(value: true), Key.clamshell, onlyExternal: true)
    }

    /// Beendet `overrideLid()`: Das Logo wird dunkel, wie Apple es bei zugeklapptem Deckel macht.
    public func endLidOverride() {
        service.set(NSNumber(value: true), Key.clamshell)
    }

    // MARK: Hilfen

    private func flat(_ nits: Double) -> [[Double]] { [[0, nits], [Self.top, nits]] }

    private func isFlat(_ key: String, _ nits: Double) -> Bool {
        guard let rows = service.value(key) as? [[NSNumber]], rows.count == 2 else { return false }
        return rows.allSatisfy { $0.count == 2 && abs($0[1].doubleValue - nits) < 0.01 }
    }
}
