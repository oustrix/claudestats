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
        return VStack(spacing: 0) {
            TitleBar(model: model, showingSettings: $showingSettings)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Run the custom title bar to the very top, under the floating traffic lights, instead of
        // letting the hidden title bar reserve a strip above it.
        .ignoresSafeArea(.container, edges: .top)
        .background(theme.back)
        .environment(\.theme, theme)
        // Both palettes are dark and the app paints its own surfaces, so pin the scheme to dark:
        // native chrome (progress spinners, content-unavailable views, popovers) then renders
        // legibly on the theme even when the system is set to light. Traffic lights stay native.
        .preferredColorScheme(.dark)
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

}

/// The app's own flat title bar, standing in for the native one (hidden via `.hiddenTitleBar`): the
/// small app label, the freshness line, and the gear / accent-plus / refresh cluster, over the toolbar
/// tint with a hairline base — the mockup's window chrome. The leading inset clears the floating
/// traffic lights that now sit over the content.
private struct TitleBar: View {
    let model: DashboardModel
    @Binding var showingSettings: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text("ClaudeStats")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.sub)

            Spacer(minLength: 12)

            // The freshness line, and any data the last scan lost beside it (the latter only on loss).
            if let scan = model.scan {
                DashboardStatus(
                    responses: model.responseCount, updatedAt: model.lastRefreshedAt, theme: theme)
                ScanSummary(scan: scan)
            }

            HStack(spacing: 6) {
                TitleBarButton(system: "gearshape", help: "Settings") { showingSettings = true }
                AddBlockMenu(model: model)
                TitleBarButton(system: "arrow.clockwise", help: "Refresh") {
                    Task { await model.stats.refresh(force: true) }
                }
                .keyboardShortcut("r")
            }
        }
        // The traffic lights float over the content's top-left; this inset keeps the label clear of them.
        .padding(.leading, 78)
        .padding(.trailing, 14)
        .frame(height: 46)
        .frame(maxWidth: .infinity)
        .background(theme.tb)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.bord).frame(height: 1) }
    }
}

/// A quiet title-bar icon button: muted at rest, a pill of `theme.pill` on hover, matching the
/// mockup's gear and refresh.
private struct TitleBarButton: View {
    let system: String
    let help: String
    let action: () -> Void
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14))
                .foregroundStyle(theme.mut)
                .frame(width: 28, height: 28)
                .background(hovering ? theme.pill : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The accent-filled "+" that adds a block. A `Menu` styled as the mockup's solid accent square — the
/// chevron hidden, the bezel dropped — so it reads as one button, not a native pop-up.
private struct AddBlockMenu: View {
    let model: DashboardModel
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            ForEach(BlockType.allCases, id: \.self) { type in
                Button {
                    model.add(type)
                } label: {
                    Label(type.title, systemImage: type.symbol)
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 28, height: 28)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        // `.plain` keeps the custom accent-square label exactly as drawn; `.borderlessButton` would
        // strip its fill back to a bare glyph.
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add block")
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
            HStack(spacing: 8) {
                Text(block.title).font(.headline).foregroundStyle(theme.txt)
                // The timeframe (and, for a chart, its bucket) as a quiet pill, matching the mockup.
                HeaderPill(text: block.headerPillLabel)
                Spacer()
                // A breakdown card can expand its top-N into a full-ranking modal — a viewing
                // affordance, so it stays visible even outside edit mode.
                if block.type == .breakdown {
                    BreakdownExpandButton { model.expandBreakdown(block) }
                }
                // Reorder/configure/remove appear only in edit mode, so the resting dashboard is clean.
                if model.isEditing {
                    controls
                }
            }
            body(for: block)
        }
        .padding(16)
        // Fill the row's height, not just its width: `GridFlowLayout` proposes every block in a row
        // the height of the tallest one, so a card with fewer rows (a short breakdown next to a tall
        // one) stretches to match instead of leaving a ragged bottom edge — `align-items: stretch`.
        // Content stays pinned top-leading; the extra height is empty card, as in the mockup.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

/// The small rounded badge in a block header that scopes the card — its timeframe, or a chart's
/// bucket, or "invocations". Faint text on the pill surface, the header's quiet second line, matching
/// the mockup and the detail modal's own scope pill.
private struct HeaderPill: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.faint)
            .padding(.vertical, 2)
            .padding(.horizontal, 7)
            .background(theme.pill, in: Capsule())
    }
}

/// The toolbar's freshness line: how long ago the numbers were made current, and how many responses
/// they cover. Monospaced and faint, as in the mockup. The theme is passed in rather than read from
/// the environment, which a toolbar item does not reliably inherit.
private struct DashboardStatus: View {
    let responses: Int
    let updatedAt: Date?
    let theme: Theme

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.faint)
            .monospacedDigit()
    }

    private var text: String {
        let responsesText = "\(responses.grouped) responses"
        guard let updatedAt else { return responsesText }
        // `.named` reads "now" the instant after a refresh — where `.numeric` says the awkward "in 0
        // sec." — and falls back to "2 min. ago" once there is a span worth naming.
        let ago = updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return "updated \(ago) · \(responsesText)"
    }
}
