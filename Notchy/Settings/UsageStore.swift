import NotchyCore
import Observation

/// Usage for this session only; the Claude Console has the real bill.
@MainActor
@Observable
final class UsageStore {
    private(set) var totals = UsageTotals()

    func addInput(_ tokens: Int, model: ClaudeModel) { totals.addInput(tokens, model: model) }
    func addOutput(_ tokens: Int, model: ClaudeModel) { totals.addOutput(tokens, model: model) }
    func reset() { totals = UsageTotals() }
}
