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
            layout
            Divider().overlay(theme.bord)
            footer
        }
        .padding(24)
        .frame(width: 460)
        .background(theme.win)
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
                Picker("", selection: refreshBinding) {
                    ForEach(RefreshInterval.allCases, id: \.self) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var transcriptsPath: String {
        model.preferences.transcriptRoot ?? "\(FileEventSource.defaultRoot.path()) (default)"
    }

    private var refreshBinding: Binding<RefreshInterval> {
        Binding(
            get: { model.preferences.refreshInterval },
            set: { model.setRefreshInterval($0) })
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
