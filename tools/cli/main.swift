import ApfellichtCore
import Foundation

// Prüfen und Notfall-Reset ohne App:
//   apfellicht-cli status     zeigt, was corebrightnessd gerade rechnet
//   apfellicht-cli reset      Apples Werkstabellen zurück, Logo an
//   apfellicht-cli set 0.4    feste Helligkeit (0–1)
MainActor.assumeIsolated {
    guard let service = BrightnessService() else { print("CoreBrightness nicht verfügbar"); exit(1) }
    let logo = LogoControl(service: service, store: UserDefaults(suiteName: "de.timkanik.apfellicht") ?? .standard)
    let args = Array(CommandLine.arguments.dropFirst())
    switch args.first {
    case "reset":
        logo.restoreApple()
        print("Apple-Standard wiederhergestellt")
    case "set":
        guard let v = args.dropFirst().first.flatMap(Double.init) else { print("Wert 0–1 fehlt"); exit(1) }
        logo.apply(level: v)
        print("Ziel \(LogoControl.nits(forLevel: v)) Nits")
    default:
        break
    }
    Thread.sleep(forTimeInterval: args.isEmpty || args.first == "status" ? 0 : 1)
    let s = service.logoState
    for k in ["DisplayNits", "Lux", "PWMNitsPreRestriction", "MinNitsRestriction", "MaxNitsRestriction", "AppliedNits", "Factor", "FinalNits"] {
        print(k.padding(toLength: 22, withPad: " ", startingAt: 0), (s[k] as? NSNumber)?.doubleValue ?? .nan)
    }
    print("LogoAn".padding(toLength: 22, withPad: " ", startingAt: 0), logo.isOn)
    print("Tastatur".padding(toLength: 22, withPad: " ", startingAt: 0), service.keyboardBrightness ?? .nan, service.keyboardIDs)
    print("DeckelZu".padding(toLength: 22, withPad: " ", startingAt: 0), Lid.isClosed as Any)
}
