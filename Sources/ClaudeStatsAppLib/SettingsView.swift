import AppKit
import ClaudeStatsCore
import SwiftUI

/// Parses a rate field's text into a finite, non-negative dollars-per-Mtok value, or nil when the
/// text is empty, non-numeric, negative, or not finite. Accepts surrounding whitespace and a leading
/// `$` so a pasted "$5" is understood. Not `private` so the parsing is unit-tested without a view.
func parseRate(_ text: String) -> Double? {
    var trimmed = text.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("$") { trimmed.removeFirst() }
    guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
    return value
}

/// The two Settings tabs. `general` holds the original sections; `pricing` holds the rate editor.
/// Not `private`: a ViewInspector test constructs `SettingsView` on a chosen tab via `initialTab`.
enum SettingsTab: String, CaseIterable, Hashable {
    case general, pricing
    var title: String {
        switch self {
        case .general: "General"
        case .pricing: "Pricing"
        }
    }
}

/// The settings sheet: a themed modal over the dashboard (not a native `Settings` scene), with an
/// Appearance / Data / Layout stack. Every control is a thin wrapper over a `DashboardModel` method
/// — the model owns the persistence and the live effect, so this view only presents and dispatches.
struct SettingsView: View {
    let model: DashboardModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var tab: SettingsTab
    @State private var confirmingReset = false
    @State private var confirmingPricingReset = false

    /// `initialTab` defaults to `.general`, so the app constructs `SettingsView(model:)` unchanged; a
    /// test passes `.pricing` to render and inspect the Pricing tab, which `body`'s `switch` would
    /// otherwise leave out of the tree.
    init(model: DashboardModel, initialTab: SettingsTab = .general) {
        self.model = model
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            SegmentedControl(
                options: SettingsTab.allCases, selection: tab,
                label: \.title, select: { tab = $0 })
            switch tab {
            case .general: general
            case .pricing: pricing
            }
            Divider().overlay(theme.bord)
            footer
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.win)
        // Drives the accent the system draws for controls that ignore `foregroundStyle`: the
        // default-action "Done" button's prominent fill and the segmented picker's selected segment.
        .tint(theme.accent)
        .environment(\.theme, theme)
        .preferredColorScheme(.dark)
    }

    /// The original sections, now the General tab.
    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            appearance
            data
            cost
            layout
        }
    }

    private var header: some View {
        HStack {
            Text("Settings").font(.title2.bold()).foregroundStyle(theme.txt)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .foregroundStyle(theme.accent)
        }
    }

    // MARK: - Appearance

    private var appearance: some View {
        Section(title: "Appearance") {
            HStack(spacing: 12) {
                ForEach(ThemeChoice.allCases, id: \.self) { choice in
                    ThemeCard(
                        choice: choice, isActive: model.preferences.theme == choice,
                        action: { model.setTheme(choice) })
                }
            }
        }
    }

    // MARK: - Data

    private var data: some View {
        Section(title: "Data") {
            SettingsRow(label: "Transcripts folder", detail: transcriptsPath) {
                Button("Change…") { chooseTranscriptsFolder() }
                    .foregroundStyle(theme.accent)
            }
            SettingsRow(label: "Refresh interval") {
                // A theme-painted segmented control rather than `Picker(.segmented)`: on macOS the
                // system segmented control colours its selected segment from the OS accent and
                // ignores the theme, so it would not recolour when the theme changes.
                SegmentedControl(
                    options: RefreshInterval.allCases, selection: model.preferences.refreshInterval,
                    label: \.label, select: model.setRefreshInterval)
            }
        }
    }

    private var transcriptsPath: String {
        model.preferences.transcriptRoot ?? "\(FileEventSource.defaultRoot.path()) (default)"
    }

    /// A directories-only open panel. Legitimate because the app is non-sandboxed and reads arbitrary
    /// folders; its outcome routes through `setTranscriptRoot`, which is where the behaviour is tested.
    private func chooseTranscriptsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = model.preferences.resolvedTranscriptRoot
        if panel.runModal() == .OK, let url = panel.url {
            model.setTranscriptRoot(url.path())
        }
    }

    // MARK: - Cost

    private var cost: some View {
        Section(title: "Cost") {
            SettingsRow(label: "Show cost estimate") {
                // A theme-painted toggle: the macOS native `Toggle` tints its switch from the OS
                // accent and ignores the environment, so — like the refresh segmented control — it
                // would not recolour with the theme.
                ThemedToggle(
                    isOn: model.preferences.showCost, set: model.setShowCost,
                    accessibilityLabel: "Show cost estimate")
            }
            Text(
                "Estimated from average published prices. Not a billing document — the transcripts "
                    + "record tokens, not dollars."
            )
            .font(.caption)
            .foregroundStyle(theme.mut)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Layout

    private var layout: some View {
        Section(title: "Layout") {
            SettingsRow(label: "Edit dashboard") {
                ThemedToggle(
                    isOn: model.isEditing, set: model.setEditing,
                    accessibilityLabel: "Edit dashboard")
            }
            Text(
                "Reveal the controls to reorder, configure, and remove blocks. Turn off for a clean "
                    + "dashboard; it resets on relaunch."
            )
            .font(.caption)
            .foregroundStyle(theme.mut)
            .fixedSize(horizontal: false, vertical: true)

            SettingsRow(label: "Layout file", detail: model.layoutFileURL.path()) {
                Button("Reset…") { confirmingReset = true }
                    .foregroundStyle(theme.accent)
            }
        }
        .confirmationDialog(
            "Reset the dashboard layout to its default?", isPresented: $confirmingReset
        ) {
            Button("Reset layout", role: .destructive) { model.resetLayout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current arrangement of blocks will be replaced by the built-in default.")
        }
    }

    // MARK: - Pricing

    /// The families shown, in the default price list's conventional order (most to least expensive),
    /// not the dictionary's undefined order.
    private static let pricingFamilies = ["opus", "sonnet", "haiku", "fable"]

    private var pricing: some View {
        Section(title: "Pricing") {
            Text(
                "Estimated from average published prices, in US dollars per 1,000,000 tokens. Not a "
                    + "billing document — the transcripts record tokens, not dollars."
            )
            .font(.caption)
            .foregroundStyle(theme.mut)
            .fixedSize(horizontal: false, vertical: true)

            PricingHeaderRow()
            ForEach(Self.pricingFamilies, id: \.self) { family in
                PricingRow(
                    family: family,
                    rate: model.pricing.rates[family] ?? ModelRate(
                        input: 0, output: 0, cacheWrite: 0, cacheRead: 0),
                    setRate: { model.setRate(family: family, rate: $0) })
            }

            SettingsRow(label: "Pricing file", detail: PricingStore.defaultURL.path()) {
                Button("Reset…") { confirmingPricingReset = true }
                    .foregroundStyle(theme.accent)
            }
        }
        .confirmationDialog(
            "Reset prices to the published defaults?", isPresented: $confirmingPricingReset
        ) {
            Button("Reset prices", role: .destructive) { model.resetPricing() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edited token prices will be replaced by the built-in published defaults.")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Text(
            "ClaudeStats · version 1.0 — reads ~/.claude, writes only its layout and settings"
        )
        .font(.caption)
        .foregroundStyle(theme.faint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A titled group with a faint uppercase header, matching the mockup's section style.
private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(theme.mut)
            content
        }
    }
}

/// A label/detail row with a trailing control.
private struct SettingsRow<Trailing: View>: View {
    let label: String
    var detail: String? = nil
    @ViewBuilder let trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(theme.txt)
                if let detail {
                    Text(detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.mut)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

/// A theme-painted segmented control: the selected segment is filled with `theme.accent`, so it
/// recolours with the theme where the native `Picker(.segmented)` would stay the OS accent.
private struct SegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let selection: Option
    let label: (Option) -> String
    let select: (Option) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    select(option)
                } label: {
                    Text(label(option))
                        .font(.callout)
                        .frame(minWidth: 38)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(isSelected ? theme.accent : .clear)
                        .foregroundStyle(isSelected ? theme.onAccent : theme.sub)
                }
                .buttonStyle(.plain)
            }
        }
        .background(theme.pill)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.cardB, lineWidth: 1))
        .fixedSize()
    }
}

/// The column headers over the four rate fields.
private struct PricingHeaderRow: View {
    @Environment(\.theme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            Text("").frame(width: 56, alignment: .leading)
            ForEach(["In", "Out", "Write", "Read"], id: \.self) { title in
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.mut)
                    .frame(width: 56, alignment: .trailing)
            }
        }
    }
}

/// One family's four editable rate fields. Each field commits on submit or focus loss: an invalid
/// or negative value reverts to the current rate, a valid one calls `setRate` with the whole
/// updated `ModelRate`. Editing per-field but writing the whole rate keeps `setRate` atomic.
private struct PricingRow: View {
    let family: String
    let rate: ModelRate
    let setRate: (ModelRate) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Text(family.capitalized)
                .foregroundStyle(theme.txt)
                .frame(width: 56, alignment: .leading)
            RateField(value: rate.input) { setRate(with(\.input, $0)) }
            RateField(value: rate.output) { setRate(with(\.output, $0)) }
            RateField(value: rate.cacheWrite) { setRate(with(\.cacheWrite, $0)) }
            RateField(value: rate.cacheRead) { setRate(with(\.cacheRead, $0)) }
        }
    }

    /// A copy of `rate` with one keypath replaced — so a single field edit produces a whole rate.
    private func with(_ keyPath: WritableKeyPath<ModelRate, Double>, _ newValue: Double) -> ModelRate {
        var updated = rate
        updated[keyPath: keyPath] = newValue
        return updated
    }
}

/// A single numeric rate field. Holds a local text draft so intermediate keystrokes never re-price;
/// commits on submit/blur via `parseRate`, reverting the draft when the text is invalid or negative.
private struct RateField: View {
    let value: Double
    let commit: (Double) -> Void
    @Environment(\.theme) private var theme
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.callout.monospaced())
            .foregroundStyle(theme.txt)
            .frame(width: 56)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(theme.pill, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.cardB, lineWidth: 1))
            .focused($focused)
            .onSubmit(commitDraft)
            .onChange(of: focused) { _, isFocused in if !isFocused { commitDraft() } }
            .onChange(of: value) { _, _ in text = Self.format(value) }
            .onAppear { text = Self.format(value) }
    }

    private func commitDraft() {
        if let parsed = parseRate(text) {
            commit(parsed)
            text = Self.format(parsed)
        } else {
            text = Self.format(value)  // revert: invalid, negative, or empty
        }
    }

    /// Formats a rate the way it is typed back — trimming a trailing `.0` so "3" shows as "3".
    private static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

/// A theme-painted switch. Drawn by hand rather than a native `Toggle` for the same reason as the
/// segmented control: macOS tints a `Toggle`'s switch from the OS accent and ignores the theme, so a
/// native one would not recolour when the theme changes.
private struct ThemedToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void
    let accessibilityLabel: String
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            set(!isOn)
        } label: {
            Capsule()
                .fill(isOn ? theme.accent : theme.track)
                .frame(width: 40, height: 24)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? theme.onAccent : theme.sub)
                        .frame(width: 18, height: 18)
                        .padding(3)
                }
                .overlay(Capsule().strokeBorder(theme.cardB, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOn ? "on" : "off")
    }
}

/// One selectable theme swatch. The active one is ringed with the live accent.
private struct ThemeCard: View {
    let choice: ThemeChoice
    let isActive: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    /// The palette this card previews — its own colours, not the active theme's, so a person sees
    /// what they are choosing.
    private var palette: Theme { Theme(choice) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(palette.accent).frame(width: 14, height: 14)
                    Circle().fill(palette.bar).frame(width: 14, height: 14)
                    Circle().fill(palette.card).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(palette.cardB, lineWidth: 1))
                }
                Text(choice.title).font(.subheadline.weight(.medium)).foregroundStyle(palette.txt)
                Text(choice.subtitle).font(.caption).foregroundStyle(palette.mut)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isActive ? theme.accent : palette.cardB, lineWidth: isActive ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

extension ThemeChoice {
    var title: String {
        switch self {
        case .slate: "Slate"
        case .claude: "Claude"
        }
    }

    var subtitle: String {
        switch self {
        case .slate: "Cool neutral"
        case .claude: "Warm terracotta"
        }
    }
}

extension RefreshInterval {
    var label: String { "\(rawValue)s" }
}
