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
            onRecordGIF: { [weak self] in self?.recordGIF() },
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
        // ⌃⌘3 for full screen: ⌘⇧3 is reserved by the macOS system screenshot,
        // so a Carbon hotkey there would register but never fire.
        hotKey.register(keyCode: UInt32(kVK_ANSI_3), modifiers: [.control, .command]) { [weak self] in
            self?.captureFullScreen()
        }
        // ⌥⌘G for GIF — ⌃⌘G is commonly claimed by window managers.
        hotKey.register(keyCode: UInt32(kVK_ANSI_G), modifiers: [.option, .command]) { [weak self] in
            self?.recordGIF()
        }

        if !OnboardingWindowController.hasCompleted {
            OnboardingWindowController.shared.show()
        }

        // Spin up ScreenCaptureKit in the background — its first use after
        // launch takes seconds and must not land on the user's first capture.
        CaptureService.shared.warmUp()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If an editor (or other window) is already open, just bring it forward.
        // Only the "no windows" reopen gesture starts a fresh area capture.
        if flag { return true }
        captureArea()
        return false
    }

    private func captureArea() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureArea() else { return }
            didCapture(image)
        }
    }

    private func captureWindow() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureWindow() else { return }
            didCapture(image)
        }
    }

    private func captureFullScreen() {
        Task { @MainActor in
            guard let image = await CaptureService.shared.captureFullScreen() else { return }
            didCapture(image)
        }
    }

    /// Shared post-capture handling: optional shutter sound, then open the editor.
    private func didCapture(_ image: NSImage) {
        if preferences.playSoundOnCapture { CaptureSound.play() }
        windows.openEditor(with: image)
    }

    private func recordGIF() {
        Task { @MainActor in await CaptureService.shared.recordGIF() }
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
private let kVK_ANSI_3: Int = 0x14
private let kVK_ANSI_G: Int = 0x05

/// Plays the system screenshot shutter sound, best-effort. The authentic sound
/// ships inside CoreAudio; if it's ever absent we fall back to a stock alert
/// sound, and worst case stay silent rather than crash.
@MainActor
enum CaptureSound {
    private static let cached: NSSound? = {
        let candidates = [
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
            "/System/Library/Sounds/Grab.aif"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let sound = NSSound(contentsOfFile: path, byReference: true) { return sound }
        }
        return NSSound(named: "Pop")
    }()

    static func play() {
        guard let sound = cached else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
