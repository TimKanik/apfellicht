// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Apfellicht",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Apfellicht", targets: ["Apfellicht"])],
    targets: [
        // Zugriff auf corebrightnessd, Tastatur und Deckel. Keine UI.
        .target(name: "ApfellichtCore", linkerSettings: [.linkedFramework("IOKit")]),
        // Die Menüleisten-App.
        .executableTarget(name: "Apfellicht", dependencies: ["ApfellichtCore"]),
        // Kommandozeilen-Werkzeug zum Prüfen und Zurücksetzen (`swift run apfellicht-cli status`).
        .executableTarget(name: "apfellicht-cli", dependencies: ["ApfellichtCore"], path: "tools/cli"),
    ]
)
