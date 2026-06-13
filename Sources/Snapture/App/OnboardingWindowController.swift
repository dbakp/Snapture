import AppKit
import SwiftUI

/// First-run welcome window: explains the hotkeys, pitches the editor, and
/// walks the user through the Screen Recording permission before their first
/// capture fails confusingly.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    private static let completedKey = "hasCompletedOnboarding"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: OnboardingView { [weak self] in
                self?.finish()
            })
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.title = "Welcome to Snapture"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = host
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // Accessory (menu bar) apps: plain orderFront is ignored while the app
        // is still finishing launch — this is the documented escape hatch.
        window?.orderFrontRegardless()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.orderOut(nil)
    }

    // Closing via the traffic light counts as "seen it" — never nag.
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            UserDefaults.standard.set(true, forKey: Self.completedKey)
        }
    }
}

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var permissionGranted = CGPreflightScreenCaptureAccess()
    private let permissionPoll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 88, height: 88)
                Text("Welcome to Snapture")
                    .font(.largeTitle.bold())
                Text("Beautiful screenshots for product people.")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 28)

            // Feature rows
            VStack(alignment: .leading, spacing: 18) {
                featureRow(
                    symbol: "command",
                    title: "Capture from anywhere",
                    detail: "⌘⇧2 selects an area, ⌘⇧1 picks a window. Snapture lives in your menu bar — no dock icon."
                )
                featureRow(
                    symbol: "slider.horizontal.3",
                    title: "Make it presentation-ready",
                    detail: "Backgrounds, shadows, arrows, step badges, blur, window chrome — all in the editor that opens after every capture."
                )
                featureRow(
                    symbol: "doc.on.clipboard",
                    title: "Copy, don't save",
                    detail: "⌘C copies the finished image straight to your clipboard. Or drag it into Slack, Figma, or anywhere else."
                )
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 20)

            // Permission
            Group {
                if permissionGranted {
                    Label("Screen Recording permission granted", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                } else {
                    VStack(spacing: 8) {
                        Button {
                            _ = CGRequestScreenCaptureAccess()
                        } label: {
                            Label("Grant Screen Recording Permission…", systemImage: "lock.shield")
                        }
                        .controlSize(.large)
                        Text("macOS will ask you to enable Snapture in System Settings,\nthen offer to relaunch the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.bottom, 20)

            // CTA
            Button("Get Started") { onFinish() }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Text("Press ⌘⇧2 any time to take your first screenshot")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
                .padding(.bottom, 28)
        }
        .frame(width: 520, height: 620)
        .onReceive(permissionPoll) { _ in
            permissionGranted = CGPreflightScreenCaptureAccess()
        }
    }

    private func featureRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
