import AppKit
import NotchyCore
import os

/// Offers to move Notchy into Applications when it is opened from anywhere else: the disk image,
/// Downloads, or the hidden copy macOS runs a quarantined app from. Outside Applications, macOS's
/// Quit & Reopen after the Screen Recording grant can lose track of it.
@MainActor
enum MoveToApplications {
    private static let logger = Logger(subsystem: AppInfo.logSubsystem, category: "move")
    private static let declinedKey = "declinedMoveToApplications"
    private static let destination = URL(fileURLWithPath: "/Applications/Notchy.app")

    /// Returns true when Notchy is moving and about to quit; launch should stop there.
    static func offerIfNeeded() -> Bool {
        #if DEBUG
        return false // development builds run from DerivedData
        #else
        let source = Bundle.main.bundleURL
        guard !isInApplications(source), !UserDefaults.standard.bool(forKey: declinedKey) else { return false }

        NSApp.activate()
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Move Notchy to Applications?"
        alert.informativeText = "Notchy is running from \(placeName(source)). Move it to Applications so it can find itself again after you allow Screen Recording, and so it stays put."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: declinedKey)
        }
        guard response == .alertFirstButtonReturn else { return false }

        do {
            try move(from: source)
            relaunch()
            return true
        } catch {
            logger.error("Move failed: \(error.localizedDescription, privacy: .public)")
            let failed = NSAlert()
            failed.messageText = "Notchy could not be moved"
            failed.informativeText = "Drag Notchy into the Applications folder in Finder, then open it from there.\n\n\(error.localizedDescription)"
            failed.runModal()
            return false
        }
        #endif
    }

    private static func isInApplications(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let user = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(user + "/")
    }

    /// The hidden copy macOS runs a quarantined app from ("App Translocation").
    private static func isTranslocated(_ url: URL) -> Bool {
        url.path.contains("/AppTranslocation/")
    }

    private static func placeName(_ url: URL) -> String {
        if isTranslocated(url) || url.path.hasPrefix("/Volumes/") { return "the disk image or a temporary location" }
        return url.deletingLastPathComponent().lastPathComponent
    }

    /// Copies into Applications, replacing an older Notchy (which goes to the Trash). The original
    /// goes to the Trash too, unless it is read-only: on the disk image, or translocated.
    private static func move(from source: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            try files.trashItem(at: destination, resultingItemURL: nil)
        }
        try files.copyItem(at: source, to: destination)
        // The copy keeps the download's quarantine flag; the person has already opened Notchy, so
        // clear it rather than have macOS stop them a second time.
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try xattr.run()
        xattr.waitUntilExit()
        if !isTranslocated(source), !source.path.hasPrefix("/Volumes/") {
            try? files.trashItem(at: source, resultingItemURL: nil)
        }
        logger.info("Moved to Applications")
    }

    private static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", destination.path]
        try? process.run()
        NSApp.terminate(nil)
    }
}
