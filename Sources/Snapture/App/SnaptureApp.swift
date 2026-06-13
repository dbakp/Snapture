import SwiftUI
import AppKit

@main
struct SnaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.preferences)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let preferences = Preferences()
    private(set) var menuBar: MenuBarController!
    private(set) var hotKey: HotKeyManager!
    private(set) var windows: WindowManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        windows = WindowManager()
        menuBar = MenuBarController(
            onCaptureArea: { [weak self] in self?.captureArea() },
            onCaptureWindow: { [weak self] in self?.captureWindow() },
            onCaptureFullScreen: { [weak self] in self?.captureFullScreen() },
            onCaptureAreaDelayed: { [weak self] in self?.captureAreaAfterDelay(seconds: 3) },
            onPreferences: { [weak self] in
                guard let self else { return }
                SettingsWindowController.shared.show(preferences: self.preferences)
            },
            onShowWelcome: { OnboardingWindowController.shared.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        hotKey = HotKeyManager()
        hotKey.register(keyCode: UInt32(kVK_ANSI_2), modifiers: [.command, .shift]) { [weak self] in
            self?.captureArea()
        }
        hotKey.register(keyCode: UInt32(kVK_ANSI_1), modifiers: [.command, .shift]) { [weak self] in
            self?.captureWindow()
        }

        if !OnboardingWindowController.hasCompleted {
            OnboardingWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        captureArea()
        return false
    }

    private func captureArea() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureArea() else { return }
            windows.openEditor(with: image)
        }
    }

    private func captureWindow() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureWindow() else { return }
            windows.openEditor(with: image)
        }
    }

    private func captureFullScreen() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureFullScreen() else { return }
            windows.openEditor(with: image)
        }
    }

    private func captureAreaAfterDelay(seconds: UInt64) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            captureArea()
        }
    }
}

// Carbon virtual key codes, redeclared so we don't pull in Carbon.h symbols implicitly.
private let kVK_ANSI_1: Int = 0x12
private let kVK_ANSI_2: Int = 0x13
