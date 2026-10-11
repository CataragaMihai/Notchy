import AppKit
import CoreGraphics

enum ScreenPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards it only returns the current state.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    @MainActor
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    /// A Screen Recording grant only takes effect in a new process.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
