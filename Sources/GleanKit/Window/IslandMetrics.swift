import CoreGraphics
import SwiftUI

/// Single source of truth for island geometry and motion. The panel is sized to
/// the expanded island plus shadow padding; the visible island animates inside it.
public enum IslandMetrics {
    public static let collapsed = CGSize(width: 138, height: 36)
    public static let expanded  = CGSize(width: 760, height: 480)

    /// Transparent breathing room around the island so the drop shadow isn't clipped.
    public static let shadowPadding: CGFloat = 36
    /// Vertical offset of the island's top edge relative to the visible-frame top
    /// (just below the menu bar). Positive raises it toward/into the menu bar.
    public static let topOffset: CGFloat = 12
    /// Extra slop around the hot rect so small cursor jitters don't toggle state.
    public static let hoverSlop: CGFloat = 4
    /// Grace period before collapsing, to survive brief exits.
    public static let collapseDelay: Duration = .milliseconds(140)

    public static let collapsedCornerRadius: CGFloat = collapsed.height / 2
    public static let expandedCornerRadius: CGFloat = 28

    public static var panelSize: CGSize {
        CGSize(width: expanded.width + shadowPadding * 2,
               height: expanded.height + shadowPadding * 2)
    }

    /// The spring that drives the pill <-> strip transition. Tune here.
    public static let spring = Animation.spring(response: 0.42, dampingFraction: 0.82)
}
