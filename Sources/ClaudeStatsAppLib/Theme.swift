import ClaudeStatsCore
import SwiftUI

/// The dashboard's colour system: one value type holding every semantic surface, text and accent
/// role the views draw from, so a view names *what* a colour is for (`theme.card`, `theme.accent`)
/// rather than a raw hex or the system `.tint`. Both shipped palettes are dark, and the app paints
/// all of its own surfaces — it does not follow the system light/dark appearance.
///
/// A code-defined value type, not an asset catalog: this project is text-only (no `.xcassets` for
/// Xcode's binary editor), the mockup needs a dozen roles rather than one accent, and a fixed-dark
/// palette must not flip with the system setting. Being a plain value also makes it trivial to test
/// and to swap.
///
/// The full mockup palette is defined here even though phase 1 does not draw every role yet: `win`,
/// `bord`, `faint`, `onAccent` and `overlay` are staged for later phases (settings chrome, accent
/// buttons, and the modal scrim breakdowns will open into) and kept so the palette stays a complete,
/// hand-tuned pair rather than something reassembled from a mockup a phase at a time.
struct Theme: Equatable, Sendable {
    /// The app/window backdrop behind the cards.
    let back: Color
    /// The window body fill (a touch lighter than `back`).
    let win: Color
    /// The toolbar / titlebar tint.
    let tb: Color
    /// A hairline border on chrome.
    let bord: Color
    /// A card fill.
    let card: Color
    /// A card's 1px border.
    let cardB: Color
    /// Primary text.
    let txt: Color
    /// Secondary text.
    let sub: Color
    /// Muted text (axis labels, captions).
    let mut: Color
    /// The faintest text/lines.
    let faint: Color
    /// A pill / chip background (also an empty heatmap cell).
    let pill: Color
    /// A progress/bar track behind a filled bar.
    let track: Color
    /// The primary accent.
    let accent: Color
    /// The fill for chart bars.
    let bar: Color
    /// A positive delta / gain.
    let pos: Color
    /// Text drawn on top of an accent fill.
    let onAccent: Color
    /// Chart grid lines.
    let grid: Color
    /// The heatmap intensity ramp, darkest first: index 0 is an empty cell, 1…4 the lit levels — so
    /// a `HeatmapCell.level` indexes straight into it.
    let heat: [Color]
    /// A scrim drawn over content behind a modal or popover.
    let overlay: Color
}

extension Theme {
    /// The palette rendered in isolation (a preview, a test) before a preference is injected. The
    /// live app no longer reads this constant — it maps `Preferences.theme` through `init(_:)` — but
    /// the `EnvironmentKey` still needs a standalone default, and `slate` is it.
    static let `default` = Theme.slate

    /// Maps a stored `ThemeChoice` to its palette. This is the seam that replaced phase 1's fixed
    /// `Theme.default` constant: the live theme now follows `Preferences.theme`.
    init(_ choice: ThemeChoice) {
        switch choice {
        case .slate: self = .slate
        case .claude: self = .claude
        }
    }

    /// Cool blue-grey. The default.
    static let slate = Theme(
        back: Color(hex: 0x0b0c0e),
        win: Color(hex: 0x0f1114),
        tb: Color(hex: 0x181b21),
        bord: Color(hex: 0x262b34),
        card: Color(hex: 0x171b22),
        cardB: Color(hex: 0x252a33),
        txt: Color(hex: 0xe7e9ee),
        sub: Color(hex: 0xc3c8d2),
        mut: Color(hex: 0x878e9b),
        faint: Color(hex: 0x565c68),
        pill: Color(hex: 0x20252f),
        track: Color(hex: 0x20252f),
        accent: Color(hex: 0x6ea8ff),
        bar: Color(hex: 0x5b9dff),
        pos: Color(hex: 0x54d197),
        onAccent: Color(hex: 0x0b0c0e),
        grid: Color(hex: 0x222732),
        heat: [0x232833, 0x1e3a5f, 0x2c5aa0, 0x4785e0, 0x7cb0ff].map { Color(hex: $0) },
        overlay: Color(red: 6 / 255, green: 7 / 255, blue: 9 / 255, opacity: 0.62))

    /// Warm terracotta, matching Claude's own palette.
    static let claude = Theme(
        back: Color(hex: 0x0b0a08),
        win: Color(hex: 0x141210),
        tb: Color(hex: 0x1e1915),
        bord: Color(hex: 0x322a22),
        card: Color(hex: 0x1b1712),
        cardB: Color(hex: 0x312a21),
        txt: Color(hex: 0xf0e9e1),
        sub: Color(hex: 0xd8cdc0),
        mut: Color(hex: 0xa3968a),
        faint: Color(hex: 0x6c6156),
        pill: Color(hex: 0x241d16),
        track: Color(hex: 0x241d16),
        accent: Color(hex: 0xe08a63),
        bar: Color(hex: 0xd97757),
        pos: Color(hex: 0x8ab87e),
        onAccent: Color(hex: 0x191512),
        grid: Color(hex: 0x2a2219),
        heat: [0x241d16, 0x4a2f22, 0x7a4632, 0xb25f43, 0xe08a63].map { Color(hex: $0) },
        overlay: Color(red: 5 / 255, green: 4 / 255, blue: 3 / 255, opacity: 0.64))
}

extension Color {
    /// A colour from a `0xRRGGBB` literal — how the mockup states its values. Alpha is separate
    /// (`opacity:`), because only the two overlay scrims carry one and they are written as rgba.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: opacity)
    }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

extension EnvironmentValues {
    /// The active theme. Injected once at the dashboard root; every block reads it with
    /// `@Environment(\.theme)`. Defaults to `Theme.default` so a view rendered in isolation (a test,
    /// a preview) still has colours.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
