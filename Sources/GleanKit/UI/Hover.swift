import SwiftUI
import AppKit

/// Click-through AppKit overlay that reports hover via an `.activeAlways` tracking area.
/// Needed because the panel is a non-active accessory app, where SwiftUI's own `.onHover`
/// tracking doesn't fire.
struct HoverTracker: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHover = onHover
    }

    final class TrackingView: NSView {
        var onHover: ((Bool) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // never intercept clicks

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }
    }
}

private struct HoverHighlight: ViewModifier {
    var opacity: Double
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(.white.opacity(hovering ? opacity : 0))
            )
            .overlay(HoverTracker { inside in
                withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            })
    }
}

extension View {
    /// A subtle white highlight behind the view while hovered. Capsule/circle for short
    /// rects (big corner radius), works on the non-key panel.
    func hoverHighlight(opacity: Double = 0.10) -> some View {
        modifier(HoverHighlight(opacity: opacity))
    }
}
