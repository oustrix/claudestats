import AppKit
import ClaudeStatsCore
import SwiftUI

/// The settings sheet: a themed modal over the dashboard (not a native `Settings` scene), with an
/// Appearance / Data / Layout stack. Every control is a thin wrapper over a `DashboardModel` method
/// — the model owns the persistence and the live effect, so this view only presents and dispatches.
struct SettingsView: View {
    let model: DashboardModel
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            appearance
            data
            cost
            layout
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
                    isOn: model.preferences.showCost, set: model.setShowCost)
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

/// A theme-painted switch. Drawn by hand rather than a native `Toggle` for the same reason as the
/// segmented control: macOS tints a `Toggle`'s switch from the OS accent and ignores the theme, so a
/// native one would not recolour when the theme changes.
private struct ThemedToggle: View {
    let isOn: Bool
    let set: (Bool) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            set(!isOn)
        } label: {
            Capsule()
                .fill(isOn ? theme.accent : theme.track)
                .frame(width: 40, height: 24)
                .overlay(
                    Circle()
                        .fill(isOn ? theme.onAccent : theme.sub)
                        .padding(3)
                        .frame(width: 24, alignment: isOn ? .trailing : .leading))
                .overlay(Capsule().strokeBorder(theme.cardB, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show cost estimate")
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
