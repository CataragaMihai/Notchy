import Foundation
import NotchyCore
import Observation

@MainActor
@Observable
final class SettingsStore {
    var model: ClaudeModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: "model") }
    }

    var mode: AnswerMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "mode")
            onModeChange()
        }
    }

    /// Where Claude Code mode starts its session. `~/Notchy` by default, not Home: Claude Code
    /// never remembers trusting the home folder, so it would ask on every start.
    var claudeCodeFolder: URL {
        didSet { UserDefaults.standard.set(claudeCodeFolder.path, forKey: "claudeCodeFolder") }
    }

    /// First-run setup is finished. Until then the app window shows the setup guide.
    var onboardingDone: Bool {
        didSet { UserDefaults.standard.set(onboardingDone, forKey: "onboardingDone") }
    }

    /// The guide's current page, kept so it picks up again after the Screen Recording relaunch.
    var onboardingStep: Int {
        didSet { UserDefaults.standard.set(onboardingStep, forKey: "onboardingStep") }
    }

    @ObservationIgnored var onModeChange: () -> Void = {}

    /// Created when Claude Code first starts there, not at launch.
    static var defaultClaudeCodeFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Notchy", directoryHint: .isDirectory)
    }

    init() {
        model = UserDefaults.standard.string(forKey: "model").flatMap(ClaudeModel.init(rawValue:)) ?? .default
        mode = UserDefaults.standard.string(forKey: "mode").flatMap(AnswerMode.init(rawValue:)) ?? .default
        claudeCodeFolder = UserDefaults.standard.string(forKey: "claudeCodeFolder").map { URL(fileURLWithPath: $0) }
            ?? Self.defaultClaudeCodeFolder
        onboardingDone = UserDefaults.standard.bool(forKey: "onboardingDone")
        onboardingStep = UserDefaults.standard.integer(forKey: "onboardingStep")
    }
}
