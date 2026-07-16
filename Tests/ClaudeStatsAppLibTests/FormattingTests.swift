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

/// A breakdown block names the metric it draws, so two agent breakdowns on different metrics read
/// apart at a glance — matching how `timeSeries`/`heatmap` already lead with the metric.
@Test func breakdownTitleNamesTheMetric() {
    func title(_ dimension: BreakdownDimension, _ metric: Metric) -> String {
        BlockConfig(type: .breakdown, metric: metric, timeframe: .last30Days, dimension: dimension)
            .title
    }
    #expect(title(.agent, .allTokens) == "All tokens by agent")
    #expect(title(.agent, .inputOutput) == "Input + output by agent")
    #expect(title(.model, .inputOutput) == "Input + output by model")
    #expect(title(.project, .cacheRead) == "Cache read by project")
}

/// A tool breakdown ignores the metric (it counts invocations), so its title must not name one.
@Test func toolBreakdownTitleOmitsTheMetric() {
    let block = BlockConfig(
        type: .breakdown, metric: .requests, timeframe: .last30Days, dimension: .tool)
    #expect(block.title == "By tool")
}
