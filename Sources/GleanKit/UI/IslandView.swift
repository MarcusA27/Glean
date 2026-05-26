import SwiftUI

/// The island itself: a top-anchored, horizontally-centered shape that springs
/// between the collapsed pill and the expanded strip. Lives inside a transparent,
/// panel-sized canvas so the shadow has room and the window never needs to resize.
public struct IslandView: View {
    @ObservedObject var model: IslandViewModel

    public init(model: IslandViewModel) {
        self.model = model
    }

    private var size: CGSize {
        model.isExpanded ? IslandMetrics.expanded : IslandMetrics.collapsed
    }

    private var cornerRadius: CGFloat {
        model.isExpanded ? IslandMetrics.expandedCornerRadius : IslandMetrics.collapsedCornerRadius
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            island
                .frame(width: size.width, height: size.height)
                .background(
                    VisualEffectView()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 12)
                .padding(.top, IslandMetrics.shadowPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandMetrics.spring, value: model.isExpanded)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var island: some View {
        ZStack {
            if model.isExpanded {
                ExpandedContent(model: model)
                    .transition(.opacity)
            } else {
                CollapsedContent()
                    .transition(.opacity)
            }
        }
    }
}

#Preview("Collapsed") {
    IslandView(model: .sample())
        .frame(width: IslandMetrics.panelSize.width, height: IslandMetrics.panelSize.height)
        .background(.black)
}

#Preview("Expanded") {
    let model = IslandViewModel.sample()
    model.isExpanded = true
    return IslandView(model: model)
        .frame(width: IslandMetrics.panelSize.width, height: IslandMetrics.panelSize.height)
        .background(.black)
}
