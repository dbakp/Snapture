import SwiftUI
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    @AppStorage("autoCopyOnCapture") var autoCopyOnCapture: Bool = false
    @AppStorage("defaultBackground") var defaultBackground: String = "gradient.indigo"
    @AppStorage("defaultPadding") var defaultPadding: Double = 48
    @AppStorage("defaultCornerRadius") var defaultCornerRadius: Double = 12
    @AppStorage("defaultShadowEnabled") var defaultShadowEnabled: Bool = true
}

struct SettingsView: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        TabView {
            Form {
                Toggle("Auto-copy screenshot to clipboard immediately after capture",
                       isOn: $prefs.autoCopyOnCapture)
                Toggle("Drop shadow by default", isOn: $prefs.defaultShadowEnabled)
                Slider(value: $prefs.defaultPadding, in: 0...120, step: 4) {
                    Text("Default padding: \(Int(prefs.defaultPadding))pt")
                }
                Slider(value: $prefs.defaultCornerRadius, in: 0...40, step: 1) {
                    Text("Default corner radius: \(Int(prefs.defaultCornerRadius))pt")
                }
                Divider()
                LaunchAtLoginToggle()
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gear") }
            .frame(width: 480, height: 360)
        }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Launch Snapture at login", isOn: $enabled)
                .onChange(of: enabled) { _, newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Revert the toggle if the system rejected the change.
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            Text("Works best when Snapture.app is installed in /Applications.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
