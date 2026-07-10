import ClaudeStatsCore
import SwiftUI

struct DashboardView: View {
    @State private var model = DashboardModel()
    @State private var editing: BlockConfig?

    /// The refresh cadence lives here rather than in the store: a policy you can see is a policy
    /// you can change, and a store with a timer inside cannot be tested without waiting for it.
    private let refreshInterval = Duration.seconds(30)

    var body: some View {
        content
            .toolbar { toolbar }
            .task {
                await model.stats.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: refreshInterval)
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
            LazyVStack(spacing: 16) {
                LayoutNotices(
                    skipped: model.skipped, wasReset: model.wasReset,
                    persistenceError: model.persistenceError, dismiss: model.dismissNotices)

                if model.blocks.isEmpty {
                    ContentUnavailableView(
                        "An empty dashboard", systemImage: "square.dashed",
                        description: Text("Add a block from the toolbar."))
                        .padding(.top, 60)
                }

                ForEach(model.blocks) { block in
                    BlockCard(block: block, model: model, editing: $editing)
                }
            }
            .padding(20)
        }
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
    }
}

/// One block, framed, with its controls. Reordering is by the up/down buttons rather than by drag:
/// a drag inside a scrolling column of charts fights the scroll, and the list is short.
private struct BlockCard: View {
    let block: BlockConfig
    let model: DashboardModel
    @Binding var editing: BlockConfig?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(block.title).font(.headline)
                Text(block.timeframe.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                controls
            }
            body(for: block)
        }
        .padding(16)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func body(for block: BlockConfig) -> some View {
        switch block.type {
        case .bigNumber:
            BigNumberBlockView(block: block, events: model.events)
        case .timeSeries:
            TimeSeriesBlockView(block: block, events: model.events)
        case .breakdown:
            BreakdownBlockView(block: block, events: model.events, home: model.home)
        case .sessionList:
            SessionListBlockView(block: block, events: model.events, home: model.home)
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
        .foregroundStyle(.secondary)
    }
}
