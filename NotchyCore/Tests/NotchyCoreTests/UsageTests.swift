import Testing
@testable import NotchyCore

struct UsageTests {
    @Test func sonnetQuestionCost() {
        var totals = UsageTotals()
        totals.addInput(4815, model: .sonnet55)
        totals.addOutput(402, model: .sonnet55)
        #expect(totals.questions == 1)
        #expect(totals.inputTokens == 4815)
        #expect(totals.outputTokens == 402)
        #expect(abs(totals.cost - (4815 * 2 + 402 * 10) / 1_000_000.0) < 1e-12) // about 1.4 cents
    }

    @Test func mixedModelsAddUp() {
        var totals = UsageTotals()
        totals.addInput(1_000_000, model: .haiku45)
        totals.addOutput(1_000_000, model: .opus55)
        #expect(totals.questions == 1)
        #expect(abs(totals.cost - 21) < 1e-9)
    }
}
