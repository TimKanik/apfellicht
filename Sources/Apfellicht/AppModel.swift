import AppKit
import ApfellichtCore
import Observation
import ServiceManagement
import WidgetKit

/// Hält die festen Werte und setzt sie immer wieder durch.
@MainActor
@Observable
final class AppModel {
    private enum Pref {
        static let logoLevel = "logoLevel"
        static let logoOn = "logoOn"
        static let keyboardLevel = "keyboardLevel"
        static let keyboardOn = "keyboardOn"
        static let lidGlow = "lidGlow"
        static let appleMode = "appleMode"
        static let launchAtLogin = "launchAtLogin"
    }

    private let defaults = UserDefaults.standard
    private let service: BrightnessService?
    private let logo: LogoControl?
    @ObservationIgnored private var server: ControlLinkServer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var lidOverride = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var logoLevel: Double { didSet { defaults.set(logoLevel, forKey: Pref.logoLevel); leaveAppleMode(); applyLogo() } }
    var logoOn: Bool {
        didSet {
            defaults.set(logoOn, forKey: Pref.logoOn)
            if appleMode { logo?.setOn(logoOn) } else { applyLogo() }
            reloadControls()
        }
    }
    var keyboardLevel: Double { didSet { defaults.set(keyboardLevel, forKey: Pref.keyboardLevel); applyKeyboard() } }
    var keyboardOn: Bool { didSet { defaults.set(keyboardOn, forKey: Pref.keyboardOn); applyKeyboard(); reloadControls() } }
    var lidGlow: Bool { didSet { defaults.set(lidGlow, forKey: Pref.lidGlow); updateLid() } }
    /// Nach „Apple-Standard wiederherstellen“: Das Logo läuft wieder mit Apples Automatik, bis du den
    /// Logo-Regler anfasst. An/Aus geht in dem Modus weiter.
    private(set) var appleMode: Bool { didSet { defaults.set(appleMode, forKey: Pref.appleMode) } }
    private(set) var waitsForLightChange = false
    private(set) var appliedNits: Double?
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Pref.launchAtLogin); registerLogin() } }

    var isAvailable: Bool { logo?.isAvailable ?? false }

    init() {
        let service = BrightnessService()
        self.service = service
        logo = service.map(LogoControl.init(service:))

        defaults.register(defaults: [Pref.logoLevel: 0.45, Pref.logoOn: true, Pref.keyboardOn: true,
                                     Pref.lidGlow: false, Pref.appleMode: false,
                                     Pref.launchAtLogin: true])
        launchAtLogin = defaults.bool(forKey: Pref.launchAtLogin)
        logoLevel = defaults.double(forKey: Pref.logoLevel)
        logoOn = defaults.bool(forKey: Pref.logoOn)
        keyboardOn = defaults.bool(forKey: Pref.keyboardOn)
        lidGlow = defaults.bool(forKey: Pref.lidGlow)
        appleMode = defaults.bool(forKey: Pref.appleMode)
        if defaults.object(forKey: Pref.keyboardLevel) != nil {
            keyboardLevel = defaults.double(forKey: Pref.keyboardLevel)
        } else {
            keyboardLevel = Double(service?.keyboardBrightness ?? 0.5)
        }

        service?.disableKeyboardAutoBrightness()
        applyLogo()
        applyKeyboard()
        startServer()
        startObserving()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        registerLogin()
    }

    /// Trägt die App bei jedem Start neu ein, damit das Anmeldeobjekt auf den aktuellen Ort zeigt.
    private func registerLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Apfellicht: Anmeldeobjekt: \(error)")
        }
        if launchAtLogin, SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    // MARK: Logo

    private func applyLogo() {
        guard let logo, !appleMode else { return }
        logo.setOn(logoOn)
        if logoOn { logo.apply(level: logoLevel) }
        refreshStatus()
        updateLid()
    }

    private func leaveAppleMode() {
        if appleMode { appleMode = false }
    }

    func restoreApple() {
        endLidOverride()
        appleMode = true
        if !logoOn { logoOn = true }
        logo?.restoreApple()
        refreshStatus()
        reloadControls()
    }

    private func refreshStatus() {
        guard let logo else { return }
        appliedNits = logo.appliedNits
        waitsForLightChange = !appleMode && logoOn && logo.waitsForLightChange(level: logoLevel)
    }

    // MARK: Tastatur

    private func applyKeyboard() {
        service?.setKeyboardBrightness(keyboardOn ? Float(keyboardLevel) : 0)
    }

    /// Übernimmt Änderungen über die Helligkeitstasten der Tastatur als neuen festen Wert.
    private func adoptKeyboardKeys() {
        guard let current = service?.keyboardBrightness.map(Double.init) else { return }
        let expected = keyboardOn ? keyboardLevel : 0
        guard abs(current - expected) > 0.01 else { return }
        if current > 0.001 {
            if !keyboardOn { keyboardOn = true }
            keyboardLevel = current
        } else if keyboardOn {
            keyboardOn = false
        }
    }

    // MARK: Deckel

    private func updateLid() {
        guard let logo else { return }
        let closed = Lid.isClosed ?? false
        let want = closed && lidGlow && logoOn && !appleMode && (service?.hasExternalDisplay ?? false)
        if want && !lidOverride {
            // Erst wenn der Dienst den Deckel selbst verarbeitet hat, sonst überschreibt er uns gleich wieder.
            guard (service?.value("CBClamshellState") as? NSNumber)?.boolValue == true else { return }
            logo.overrideLid()
            lidOverride = true
        } else if !want && lidOverride {
            endLidOverride()
        }
        if !closed { lidOverride = false }
    }

    private func endLidOverride() {
        guard lidOverride else { return }
        lidOverride = false
        if Lid.isClosed == true { logo?.endLidOverride() }
    }

    // MARK: Takt

    private func tick() {
        ticks += 1
        updateLid()
        adoptKeyboardKeys()
        if ticks % 5 == 0, logoOn, !appleMode, let logo {
            logo.ensure(level: logoLevel)
        }
        refreshStatus()
    }

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.afterWake() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLid() }
        })
    }

    private func afterWake() {
        lidOverride = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.applyLogo()
                self.applyKeyboard()
            }
        }
    }

    // MARK: Kontrollzentrum

    private var controlState: ControlLink.State {
        ControlLink.State(logoOn: logoOn, keyboardOn: keyboardOn)
    }

    private func startServer() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        server = ControlLinkServer(appBundleID: id) { [weak self] request in
            guard let self else { return ControlLink.State(logoOn: true, keyboardOn: true) }
            switch request {
            case .state: break
            case .logoOn: self.logoOn = true
            case .logoOff: self.logoOn = false
            case .keyboardOn: self.keyboardOn = true
            case .keyboardOff: self.keyboardOn = false
            }
            return self.controlState
        }
    }

    private func reloadControls() {
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: ControlLink.logoKind)
            ControlCenter.shared.reloadControls(ofKind: ControlLink.keyboardKind)
        }
    }
}
