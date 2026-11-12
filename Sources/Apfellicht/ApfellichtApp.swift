import AppKit
import SwiftUI

@main
struct ApfellichtApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: "apple.logo")
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
                Text("Dieser Mac hat kein ansteuerbares Logo.")
                    .foregroundStyle(.secondary)
            }

            LightRow(title: "Logo", systemImage: "apple.logo", isOn: $model.logoOn, level: $model.logoLevel)
            if model.appleMode {
                hint("Apple-Automatik aktiv. Regler bewegen, um wieder feste Helligkeit zu nutzen.")
            } else if model.waitsForLightChange {
                hint("Wird beim nächsten Lichtwechsel am Sensor ganz übernommen.")
            }

            LightRow(title: "Tastatur", systemImage: "keyboard", isOn: $model.keyboardOn, level: $model.keyboardLevel)

            Divider()

            Toggle("Logo bei zugeklapptem Deckel leuchten lassen", isOn: $model.lidGlow)
            Toggle("Beim Anmelden starten", isOn: $model.launchAtLogin)

            Divider()

            HStack {
                Button("Apple-Standard wiederherstellen") { model.restoreApple() }
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .padding(16)
        .frame(width: 320)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct LightRow: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool
    @Binding var level: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
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
