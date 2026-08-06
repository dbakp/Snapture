import Foundation

/// App identity read from the bundle, so the UI always shows the version the
/// user is actually running (never a hardcoded string).
enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    /// e.g. "Version 1.1.3 (6)"
    static var display: String { "Version \(version) (\(build))" }
}
