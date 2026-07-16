import Testing

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

@Test func agentDimensionHasATitleAndIsOffered() {
    #expect(BreakdownDimension.agent.title == "Agent")
    #expect(BreakdownDimension.allCases.contains(.agent))
}

@Test func agentDimensionPluralizes() {
    #expect(BreakdownDimension.agent.countedNoun(1) == "1 agent")
    #expect(BreakdownDimension.agent.countedNoun(3) == "3 agents")
}
