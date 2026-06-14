import SwiftUI
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    // Capture behavior
    @AppStorage("autoCopyOnCapture") var autoCopyOnCapture: Bool = false
    @AppStorage("playSoundOnCapture") var playSoundOnCapture: Bool = true
    @AppStorage("includeCursor") var includeCursor: Bool = false

    // Default look of a freshly captured screenshot
    @AppStorage("defaultBackground") var defaultBackground: String = "gradient.indigo"
    @AppStorage("defaultFrameStyle") var defaultFrameStyle: String = "none"
    @AppStorage("defaultPadding") var defaultPadding: Double = 48
    @AppStorage("defaultCornerRadius") var defaultCornerRadius: Double = 12
    @AppStorage("defaultShadowEnabled") var defaultShadowEnabled: Bool = true
}

struct SettingsView: View {
    var body: some View {
        TabView {
            CaptureSettingsTab()
                .tabItem { Label("Capture", systemImage: "camera.viewfinder") }
            AppearanceSettingsTab()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 500)
    }
}

private struct CaptureSettingsTab: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Copy screenshot to clipboard automatically", isOn: $prefs.autoCopyOnCapture)
                Text("The editor still opens — the image is just on your clipboard right away.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Play a shutter sound when capturing", isOn: $prefs.playSoundOnCapture)
                Toggle("Include the mouse cursor in captures", isOn: $prefs.includeCursor)
            }
            Section {
                LaunchAtLoginToggle()
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
    }
}

private struct AppearanceSettingsTab: View {
    @EnvironmentObject private var prefs: Preferences

    var body: some View {
        Form {
            Section("Defaults for new screenshots") {
                Picker("Background", selection: $prefs.defaultBackground) {
                    ForEach(BackgroundPresets.all) { preset in
                        Text(preset.name).tag("gradient.\(preset.id)")
                    }
                }
                Picker("Window frame", selection: $prefs.defaultFrameStyle) {
                    ForEach(FrameStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                Toggle("Drop shadow", isOn: $prefs.defaultShadowEnabled)
            }
            Section {
                Slider(value: $prefs.defaultPadding, in: 0...120, step: 4) {
                    Text("Padding: \(Int(prefs.defaultPadding))pt")
                }
                Slider(value: $prefs.defaultCornerRadius, in: 0...40, step: 1) {
                    Text("Corner radius: \(Int(prefs.defaultCornerRadius))pt")
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 320)
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
