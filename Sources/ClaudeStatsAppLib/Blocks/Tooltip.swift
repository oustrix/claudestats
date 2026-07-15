import SwiftUI

/// A floating value bubble: one line, self-sizing, over a material so it reads above the content it
/// annotates. Shared by the heatmap grid and the time-series bars — both hover a lattice and float the
/// same bubble over the target under the cursor.
struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
    }
}

/// Where to place a `TooltipBubble` of `bubbleSize` pointing at `target`, within `container`: centred
/// above the target when there is room, otherwise flipped below it; the x is clamped so the bubble
/// never spills past the container's edges. Pure geometry, so it is unit-tested rather than eyeballed.
func tooltipPosition(target: CGRect, bubbleSize: CGSize, in container: CGSize) -> CGPoint {
    let above = target.minY > bubbleSize.height + 10
    let y =
        above
        ? target.minY - 6 - bubbleSize.height / 2
        : target.maxY + 6 + bubbleSize.height / 2
    let halfWidth = bubbleSize.width / 2
    let x = min(max(target.midX, halfWidth), container.width - halfWidth)
    return CGPoint(x: x, y: y)
}

/// The measured size of a floating bubble, so an overlay can centre and clamp it before it is placed.
struct BubbleSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

extension View {
    /// Publishes this view's measured size into `size` via a transparent background probe — used to
    /// size a tooltip bubble before `tooltipPosition` places it.
    func measuredSize(into size: Binding<CGSize>) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(key: BubbleSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(BubbleSizeKey.self) { size.wrappedValue = $0 }
    }
}
