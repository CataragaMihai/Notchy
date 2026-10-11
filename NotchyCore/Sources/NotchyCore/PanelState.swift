/// What the dropdown holds. Whether it is open is separate: content survives a collapse and
/// returns on hover. `idle` means nothing is held. Transitions are pure so they can be tested.
public enum PanelState: Equatable, Sendable {
    case idle
    case capturing
    case composing
    case streaming(hasText: Bool)
    case done
    case error(NotchyError)
    case onboarding

    /// True when there is content to show.
    public var isVisible: Bool {
        switch self {
        case .idle, .capturing: false
        default: true
        }
    }
}

public enum PanelEvent: Equatable, Sendable {
    /// Shortcut, click on the empty notch, or New screenshot: a new capture replaces what is held.
    case activate
    case captured
    case captureFailed(NotchyError)
    case permissionMissing
    case submit
    case firstText
    case finished
    case failed(NotchyError)
    /// Back to composing with the same capture, ready to send again.
    case retry
    case dismiss
}

extension PanelState {
    public func handling(_ event: PanelEvent) -> PanelState {
        switch (self, event) {
        case (_, .dismiss): .idle
        case (.capturing, .activate): self
        case (_, .activate): .capturing

        case (.capturing, .captured): .composing
        case let (.capturing, .captureFailed(error)): .error(error)
        case (.capturing, .permissionMissing): .onboarding

        case (.composing, .submit): .streaming(hasText: false)
        case let (.composing, .failed(error)): .error(error)

        case (.streaming, .firstText): .streaming(hasText: true)
        case (.streaming, .finished): .done
        case let (.streaming, .failed(error)): .error(error)

        case (.error, .retry): .composing

        default: self
        }
    }
}
