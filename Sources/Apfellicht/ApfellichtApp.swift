import AppKit
import SwiftUI

@main
struct ApfellichtApp: App {
    @NSApplicationDelegateAdaptor(RenderDelegate.self) private var renderDelegate
    @State private var model = AppModel(renderOnly: CommandLine.arguments.contains("--render-menu"))

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image("apfellicht")
                .imageScale(.large)
                .opacity(model.logoOn ? 1 : 0.5)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.isAvailable {
                Text("This Mac has no controllable logo.")
                    .foregroundStyle(.secondary)
            }

            LightRow(title: "Logo", image: Image("apfellicht"), isOn: $model.logoOn, level: $model.logoLevel)
            if model.appleMode {
                hint("Apple automatic is active. Move the slider to use a fixed brightness again.")
            } else if model.waitsForLightChange {
                hint("Fully applied at the next change in ambient light.")
            }

            LightRow(title: "Keyboard", image: Image(systemName: "keyboard"), isOn: $model.keyboardOn, level: $model.keyboardLevel)

            Divider()

            SettingRow(title: "Keep logo lit with the lid closed", isOn: $model.lidGlow)
            SettingRow(title: "Open at login", isOn: $model.launchAtLogin)

            Divider()

            HStack {
                Button("Restore Apple default") { model.restoreApple() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(16)
        .frame(width: 320)
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center) {
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

struct LightRow: View {
    let title: LocalizedStringKey
    let image: Image
    @Binding var isOn: Bool
    @Binding var level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label { Text(title) } icon: { image }.font(.headline)
                Spacer()
                Text("\(Int((level * 100).rounded())) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Toggle("", isOn: $isOn).labelsHidden()
            }
            Slider(value: $level, in: 0...1)
                .disabled(!isOn)
        }
    }
}

/// Für README-Bilder: `Apfellicht --render-menu <datei.png> [light|dark]` zeichnet das Menü und beendet sich.
/// Die Sprache kommt wie immer aus `-AppleLanguages`.
final class RenderDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-menu"), i + 1 < args.count else { return }
        let url = URL(fileURLWithPath: args[i + 1])
        let dark = args.dropFirst(i + 2).first == "dark"
        MainActor.assumeIsolated {
            let host = NSHostingView(rootView: MenuView(model: AppModel(renderOnly: true))
                .background(Color(nsColor: .windowBackgroundColor)))
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            window.appearance = host.appearance
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                exit(0)
            }
        }
    }
}
