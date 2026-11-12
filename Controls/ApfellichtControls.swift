import AppIntents
import AppKit
import SwiftUI
import WidgetKit

// Kontrollzentrum (macOS 26+): je ein Schalter für Logo und Tastatur. Die Erweiterung ist sandboxed und
// fasst die Lichter nicht selbst an, sie fragt die laufende App über `ControlLink`.

@main
struct ApfellichtControls: WidgetBundle {
    var body: some Widget {
        LogoControlWidget()
        KeyboardControlWidget()
    }
}

struct LogoControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlLink.logoKind, provider: LightValue(light: .logo)) { isOn in
            ControlWidgetToggle(isOn: isOn, action: SetLogoIntent()) {
                Label("Logo Light", image: "apfellicht")
            }
            .tint(.orange)
        }
        .displayName("Logo Light")
        .description("Turns the logo on the lid on or off.")
    }
}

struct KeyboardControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlLink.keyboardKind, provider: LightValue(light: .keyboard)) { isOn in
            ControlWidgetToggle(isOn: isOn, action: SetKeyboardIntent()) {
                Label("Keyboard Light", systemImage: "keyboard")
            }
            .tint(.orange)
        }
        .displayName("Keyboard Light")
        .description("Turns the keyboard backlight on or off.")
    }
}

enum Light { case logo, keyboard }

struct LightValue: ControlValueProvider {
    let light: Light
    var previewValue: Bool { true }

    func currentValue() async throws -> Bool {
        guard let state = await ContainingApp.currentState() else { return true }
        return light == .logo ? state.logoOn : state.keyboardOn
    }
}

struct SetLogoIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Turn Logo Light On or Off"
    @Parameter(title: "Logo Light") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult {
        _ = try await ContainingApp.ask(value ? .logoOn : .logoOff)
        return .result()
    }
}

struct SetKeyboardIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Turn Keyboard Light On or Off"
    @Parameter(title: "Keyboard Light") var value: Bool
    init() {}
    func perform() async throws -> some IntentResult {
        _ = try await ContainingApp.ask(value ? .keyboardOn : .keyboardOff)
        return .result()
    }
}

enum ControlError: Error, CustomLocalizedStringResourceConvertible {
    case notResponding, busy
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notResponding: "Apfellicht isn't responding. Open Apfellicht and try again."
        case .busy: "Apfellicht is busy. Try again in a moment."
        }
    }
}

enum ContainingApp {
    static var bundleID: String {
        let id = Bundle.main.bundleIdentifier ?? ""
        return id.hasSuffix(ControlLink.extensionSuffix) ? String(id.dropLast(ControlLink.extensionSuffix.count)) : id
    }

    /// Apfellicht.app, drei Ebenen über Contents/PlugIns/ApfellichtControls.appex.
    static var url: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func currentState() async -> ControlLink.State? {
        guard case .answered(let state) = ControlLink.send(.state, toApp: bundleID) else { return lastKnown }
        lastKnown = state
        return state
    }

    static func ask(_ request: ControlLink.Request) async throws -> ControlLink.State {
        var outcome = ControlLink.send(request, toApp: bundleID)
        if outcome == .notRunning {
            let deadline = ContinuousClock.now + .seconds(5)
            await open()
            while outcome == .notRunning, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
                outcome = ControlLink.send(request, toApp: bundleID)
            }
        }
        switch outcome {
        case .answered(let state):
            lastKnown = state
            return state
        case .notRunning: throw ControlError.notResponding
        case .noAnswer: throw ControlError.busy
        }
    }

    private static var lastKnown: ControlLink.State? {
        get { UserDefaults.standard.data(forKey: "LastKnownState").flatMap(ControlLink.State.init(data:)) }
        set { UserDefaults.standard.set(newValue?.data, forKey: "LastKnownState") }
    }

    private static func open() async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in c.resume() }
        }
    }
}
