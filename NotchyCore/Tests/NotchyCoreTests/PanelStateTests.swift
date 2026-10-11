import Testing
@testable import NotchyCore

struct PanelStateTests {
    private func run(_ events: [PanelEvent], from start: PanelState = .idle) -> PanelState {
        events.reduce(start) { $0.handling($1) }
    }

    @Test func happyPath() {
        #expect(run([.activate, .captured, .submit, .firstText, .finished]) == .done)
    }

    @Test func activateStartsANewCapture() {
        #expect(run([.activate, .captured, .activate]) == .capturing)
        #expect(run([.activate, .captured, .submit, .firstText, .finished, .activate]) == .capturing)
        #expect(run([.activate, .captured, .submit, .failed(.timeout), .activate]) == .capturing)
    }

    @Test func activateIsIgnoredWhileCapturing() {
        #expect(run([.activate, .activate]) == .capturing)
    }

    @Test func captureFailureAndPermission() {
        #expect(run([.activate, .captureFailed(.captureFailed("x"))]) == .error(.captureFailed("x")))
        #expect(run([.activate, .permissionMissing]) == .onboarding)
    }

    @Test func streamFailureThenRetry() {
        let failed = run([.activate, .captured, .submit, .failed(.overloaded)])
        #expect(failed == .error(.overloaded))
        #expect(failed.handling(.retry) == .composing)
    }

    @Test func missingKeyFailsFromComposing() {
        #expect(run([.activate, .captured, .failed(.noAPIKey)]) == .error(.noAPIKey))
    }

    @Test func dismissAlwaysReturnsToIdle() {
        for state: PanelState in [.capturing, .composing, .streaming(hasText: true), .done, .error(.timeout), .onboarding] {
            #expect(state.handling(.dismiss) == .idle)
        }
    }

    @Test func unrelatedEventsAreIgnored() {
        #expect(PanelState.idle.handling(.submit) == .idle)
        #expect(PanelState.done.handling(.firstText) == .done)
    }

    @Test func visibility() {
        #expect(!PanelState.idle.isVisible)
        #expect(!PanelState.capturing.isVisible)
        #expect(PanelState.composing.isVisible)
    }
}
