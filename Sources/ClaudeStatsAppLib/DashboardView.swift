import ClaudeStatsCore
import SwiftUI

public struct DashboardView: View {
    @State private var model: DashboardModel
    @State private var editing: BlockConfig?
    @State private var showingSettings = false

    /// The live theme, mapped from the stored preference. This is the seam phase 1 left behind: the
    /// fixed `Theme.default` constant is gone, and selecting a theme in settings recolors the app
    /// because the view re-reads `model.preferences.theme`.
    private var theme: Theme { Theme(model.preferences.theme) }

    /// The executable constructs this with no argument. Tests reach the same view with a seeded model
    /// through the internal initializer, so the empty/failure state screens can be asserted without a
    /// live filesystem.
    public init() {
        self.init(model: DashboardModel())
    }

    init(model: DashboardModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        let theme = self.theme
        return content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.back)
            .environment(\.theme, theme)
            // Both palettes are dark and the app paints its own surfaces, so pin the scheme to dark:
            // native chrome (progress spinners, content-unavailable views, popovers) then renders
            // legibly on the theme even when the system is set to light. Traffic lights stay native.
            .preferredColorScheme(.dark)
            .toolbar { toolbar }
            .toolbarBackground(theme.tb, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
            .sheet(isPresented: $showingSettings) {
                SettingsView(model: model).environment(\.theme, theme)
            }
            // The breakdown detail modal. `item:` binds to the transient `expandedBreakdown`; a
            // dismissal (the ✕, Esc, or a click-away) sets it nil, which routes through `collapse`.
            .sheet(
                item: Binding(
                    get: { model.expandedBreakdown },
                    set: { if $0 == nil { model.collapseBreakdown() } })
            ) { block in
                BreakdownDetailView(block: block, events: model.events, home: model.home)
                    .environment(\.theme, theme)
            }
            .task {
                await model.stats.refresh()
                while !Task.isCancelled {
                    // Read each tick: changing the interval in settings takes effect on the next
                    // cycle without a relaunch. The refresh cadence lives here rather than in the
                    // store — a policy you can see is a policy you can change.
                    try? await Task.sleep(for: .seconds(model.preferences.refreshInterval.rawValue))
                    // Consults the scan state first: an untouched transcript tree costs no parsing.
                    await model.stats.refresh()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.stats.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)

        case .noTranscripts(let root):
            NoTranscriptsView(root: root)

        case .failed:
            LoadFailedView(error: model.stats.lastError.map(String.init(describing:)) ?? "unknown") {
                Task { await model.stats.refresh(force: true) }
            }

        case .loaded:
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 16) {
                LayoutNotices(
                    skipped: model.skipped, wasReset: model.wasReset,
                    persistenceError: model.persistenceError, dismiss: model.dismissNotices)

                if model.blocks.isEmpty {
                    EmptyDashboardView().padding(.top, 60)
                } else {
                    grid
                }
            }
            .padding(20)
            // The grid fills the width on its own (its Layout claims the proposed width); this frame
            // is for the *other* branches — the empty-state and the notices banner are narrow and
            // would otherwise hug the left edge of the scroll content.
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    /// The blocks packed onto the twelve-column grid. `GridFlowLayout` reads each block's span, sizes
    /// it to its columns, and stacks the packed rows — taking the width straight from its layout
    /// proposal, so there is no width measurement to plumb back in.
    private var grid: some View {
        GridFlowLayout {
            ForEach(visibleBlocks) { block in
                BlockCard(block: block, model: model, editing: $editing)
                    .gridSpan(block.span)
            }
        }
    }

    /// The blocks actually drawn. When cost is off, `.cost` blocks are filtered out — leaving a
    /// trailing gap in the KPI row rather than rebalancing spans. Filtering hides cost blocks already
    /// present; it never injects one into a layout that has none.
    private var visibleBlocks: [BlockConfig] {
        model.preferences.showCost ? model.blocks : model.blocks.filter { $0.type != .cost }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            if let scan = model.scan { ScanSummary(scan: scan) }
        }
        ToolbarItem {
            Menu {
                ForEach(BlockType.allCases, id: \.self) { type in
                    Button {
                        model.add(type)
                    } label: {
                        Label(type.title, systemImage: type.symbol)
                    }
                }
            } label: {
                Label("Add block", systemImage: "plus")
            }
        }
        ToolbarItem {
            Button {
                Task { await model.stats.refresh(force: true) }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
        }
        ToolbarItem {
            Button {
                showingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

/// One block, framed, with its controls. Reordering is by the up/down buttons rather than by drag:
/// a drag inside a scrolling column of charts fights the scroll, and the list is short.
private struct BlockCard: View {
    let block: BlockConfig
    let model: DashboardModel
    @Binding var editing: BlockConfig?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(block.title).font(.headline).foregroundStyle(theme.txt)
                // A fixed-window block (the heatmap) labels its window; the rest label their timeframe.
                Text(block.type.fixedWindowLabel ?? block.timeframe.title)
                    .font(.caption).foregroundStyle(theme.mut)
                Spacer()
                // A breakdown card can expand its top-N into a full-ranking modal.
                if block.type == .breakdown {
                    BreakdownExpandButton { model.expandBreakdown(block) }
                }
                controls
            }
            body(for: block)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.cardB, lineWidth: 1))
    }

    @ViewBuilder
    private func body(for block: BlockConfig) -> some View {
        switch block.type {
        case .bigNumber:
            BigNumberBlockView(block: block, events: model.events)
        case .cost:
            CostBlockView(block: block, events: model.events, pricing: model.pricing)
        case .timeSeries:
            TimeSeriesBlockView(block: block, events: model.events)
        case .breakdown:
            BreakdownBlockView(block: block, events: model.events, home: model.home)
        case .sessionList:
            SessionListBlockView(
                block: block, events: model.events, home: model.home,
                pricing: model.preferences.showCost ? model.pricing : nil)
        case .heatmap:
            HeatmapBlockView(block: block, events: model.events)
        }
    }

    private var index: Int? { model.blocks.firstIndex { $0.id == block.id } }

    private var controls: some View {
        HStack(spacing: 2) {
            Button {
                if let index, index > 0 { model.move(from: [index], to: index - 1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)

            Button {
                if let index, index + 1 < model.blocks.count {
                    model.move(from: [index], to: index + 2)
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index == model.blocks.count - 1)

            Button {
                editing = block
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .popover(isPresented: .init(get: { editing?.id == block.id }, set: { if !$0 { editing = nil } })) {
                BlockEditor(block: block, onChange: model.update)
            }

            Button(role: .destructive) {
                model.remove(block)
            } label: {
                Image(systemName: "trash")
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .foregroundStyle(theme.mut)
    }
}
