import AppKit

/// Finds the `claude` CLI that Claude Code mode runs. An app opened from Finder has no shell PATH,
/// so it looks where the installers put it.
enum ClaudeCLI {
    private static let candidates = ["~/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]

    /// The official installer; it puts `claude` in `~/.local/bin`.
    static let installCommand = "curl -fsSL https://claude.ai/install.sh | bash"
    static let homepage = URL(string: "https://claude.com/code")!

    static var executable: URL? {
        candidates
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var isInstalled: Bool { executable != nil }

    @MainActor
    static func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
    }
}
