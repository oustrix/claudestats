import SwiftUI
import Testing
import ViewInspector

@testable import ClaudeStatsAppLib
@testable import ClaudeStatsCore

/// The set of parameter controls `BlockEditor` renders for a given block. Pickers are named by their
/// label; the Rows stepper is folded in under "Rows". This is what proves the editor cannot express,
/// say, a `sessionList` with a `bucket` — the control simply is not there.
@MainActor
private func renderedFields(_ block: BlockConfig) throws -> Set<String> {
    let view = try BlockEditor(block: block, onChange: { _ in }).inspect()
    var fields: Set<String> = []
    for picker in view.findAll(ViewType.Picker.self) {
        if let label = try? picker.labelView().text().string() { fields.insert(label) }
    }
    if !view.findAll(ViewType.Stepper.self).isEmpty { fields.insert("Rows") }
    return fields
}

@MainActor @Test func bigNumberEditorOffersMetricAndTimeframeOnly() throws {
    let fields = try renderedFields(BlockConfig(type: .bigNumber, timeframe: .last7Days))
    #expect(fields == ["Metric", "Timeframe"])
}

@MainActor @Test func timeSeriesEditorAddsABucket() throws {
    let fields = try renderedFields(
        BlockConfig(type: .timeSeries, timeframe: .last30Days, bucket: .day))
    #expect(fields == ["Metric", "Timeframe", "Bucket"])
}

@MainActor @Test func breakdownEditorOffersGroupByAndRowsButNoBucket() throws {
    let fields = try renderedFields(
        BlockConfig(type: .breakdown, timeframe: .last30Days, dimension: .model, limit: 8))
    #expect(fields == ["Metric", "Timeframe", "Group by", "Rows"])
}

@MainActor @Test func sessionListEditorHasNoMetricAndNoBucket() throws {
    let fields = try renderedFields(BlockConfig(type: .sessionList, timeframe: .last7Days, limit: 10))
    #expect(fields == ["Timeframe", "Rows"])
}

/// The heatmap draws its own fixed window, so it offers no Timeframe control — the one type that
/// drops it.
@MainActor @Test func heatmapEditorDropsTheTimeframeAndOffersABucket() throws {
    let fields = try renderedFields(
        BlockConfig(type: .heatmap, timeframe: .last30Days, bucket: .day))
    #expect(fields == ["Metric", "Bucket"])
}

/// A tool breakdown counts invocations, which cannot be attributed to a metric, so the Metric picker
/// is disabled. Guarded: if this ViewInspector build cannot read `.disabled`, the assertion is
/// skipped rather than faked.
@MainActor @Test func metricPickerIsDisabledForAToolBreakdown() throws {
    let view = try BlockEditor(
        block: BlockConfig(
            type: .breakdown, timeframe: .last30Days, dimension: .tool, limit: 10),
        onChange: { _ in }
    ).inspect()
    let metric = try view.find(
        ViewType.Picker.self, where: { try $0.labelView().text().string() == "Metric" })

    #expect(metric.isDisabled())
}

/// The counterpart: a non-tool breakdown leaves the Metric picker enabled.
@MainActor @Test func metricPickerIsEnabledForAModelBreakdown() throws {
    let view = try BlockEditor(
        block: BlockConfig(
            type: .breakdown, timeframe: .last30Days, dimension: .model, limit: 10),
        onChange: { _ in }
    ).inspect()
    let metric = try view.find(
        ViewType.Picker.self, where: { try $0.labelView().text().string() == "Metric" })

    #expect(!metric.isDisabled())
}
