import CoreGraphics
import SwiftUI
import AppKit

/// Geometry and motion for the centered window.
public enum DrawerMetrics {
    public static let windowSize = CGSize(width: 600, height: 430)
    public static let corner: CGFloat = 20
    /// Tile height tuned so five columns show ~four rows in the window.
    public static let tileHeight: CGFloat = 74

    /// Blocked leftward motion (px) the cursor must shove into the left edge to open,
    /// after the arrival momentum is discarded.
    public static let pushThreshold: CGFloat = 110
    public static let momentumWindow: TimeInterval = 0.12
    public static let edgeBand: CGFloat = 2

    public static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

/// A centered floating window: board filters over a 5-column grid of draggable pins.
public struct DrawerView: View {
    @ObservedObject var model: IslandViewModel

    public init(model: IslandViewModel) {
        self.model = model
    }

    @State private var hoveredPin: String?
    @State private var searching = false
    @State private var showColors = false
    @FocusState private var searchFocused: Bool
    @Namespace private var searchNS
    private var searchSpring: Animation { .spring(response: 0.36, dampingFraction: 0.82) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DrawerMetrics.corner, style: .continuous)
    }

    /// Hidden while closed, and while a pin is dragging out (so the drop target shows).
    private var visible: Bool { model.isExpanded && !model.isDragging }

    public var body: some View {
        VStack(spacing: 10) {
            header
            if searching && showColors { colorSwatches }
            grid
        }
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectView()
                Color.black.opacity(0.38)
            }
            .clipShape(shape)
        )
        .overlay(shape.strokeBorder(.white.opacity(0.10), lineWidth: 1))
        .clipShape(shape)
        .scaleEffect(visible ? 1 : (model.isDragging ? 0.94 : 0.97))
        .opacity(visible ? 1 : 0)
        .animation(DrawerMetrics.spring, value: model.isExpanded)
        .animation(.easeOut(duration: 0.2), value: model.isDragging)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var header: some View {
        if model.confirmingLogout {
            LogoutConfirmBar(model: model).padding(.horizontal, 16)
        } else {
            HStack(spacing: 12) {
                Text("Glean")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .italic()
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize()
                if searching {
                    searchField
                } else {
                    BoardChips(model: model)
                        .transition(.opacity)
                    searchPill
                }
                IconButton(systemName: "rectangle.portrait.and.arrow.right") {
                    model.confirmingLogout = true
                }
                RefreshButton(isReloading: model.isReloading) { model.reload() }
            }
            .padding(.horizontal, 16)
            .onChange(of: searching) { _, active in
                model.onSearchModeChange?(active)
                if active {
                    searchFocused = true
                } else {
                    model.searchQuery = ""
                    searchFocused = false
                    showColors = false
                    model.selectedColor = nil
                }
            }
        }
    }

    /// The capsule that morphs from the collapsed search button into the full field.
    private var fieldBackground: some View {
        ZStack {
            Capsule().fill(.white.opacity(0.08))
            Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .matchedGeometryEffect(id: "searchBG", in: searchNS)
    }

    private var searchGlass: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .matchedGeometryEffect(id: "searchGlass", in: searchNS)
    }

    /// Collapsed: a small pill the glass lives in; tapping expands it into the field.
    private var searchPill: some View {
        Button {
            withAnimation(searchSpring) { searching = true }
        } label: {
            searchGlass
                .frame(width: 30, height: 30)
                .background(fieldBackground)
        }
        .buttonStyle(.plain)
        .hoverHighlight()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            searchGlass
            HStack(spacing: 8) {
                TextField("Search your pins", text: $model.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($searchFocused)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showColors.toggle() }
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(showColors || model.selectedColor != nil ? .white : .white.opacity(0.55))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .hoverHighlight()
                Button {
                    withAnimation(searchSpring) { searching = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
            .transition(.opacity)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(fieldBackground)
    }

    private var colorSwatches: some View {
        HStack(spacing: 12) {
            ForEach(ColorBucket.allCases, id: \.self) { bucket in
                Button { toggleColor(bucket) } label: {
                    Circle()
                        .fill(swatchColor(bucket))
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .overlay(Circle().strokeBorder(.white, lineWidth: model.selectedColor == bucket ? 2.5 : 0))
                        .scaleEffect(model.selectedColor == bucket ? 1.14 : 1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .animation(.easeOut(duration: 0.15), value: model.selectedColor)
    }

    private func toggleColor(_ bucket: ColorBucket) {
        model.selectedColor = (model.selectedColor == bucket) ? nil : bucket
    }

    private func swatchColor(_ bucket: ColorBucket) -> Color {
        switch bucket {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .brown: return .brown
        case .neutral: return Color(white: 0.55)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if model.visiblePins.isEmpty {
            Text(model.isLoading ? "Loading your pins…" : "No pins")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollWithBar(vertical: true) {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.visiblePins) { pin in
                        PinThumbnailView(
                            pin: pin,
                            onHoverChange: { hovering in
                                if hovering { hoveredPin = pin.id }
                                else if hoveredPin == pin.id { hoveredPin = nil }
                            }
                        ) { model.isDragging = $0 }
                        .frame(height: DrawerMetrics.tileHeight)
                        .overlay {
                            if hoveredPin == pin.id {
                                SelectorBorder(cornerRadius: 13)
                            }
                        }
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 20) // gutter for the scrollbar
                .padding(.bottom, 8)
            }
        }
    }
}

/// A glowing white outline drawn over the hovered pin: a crisp white edge with a soft,
/// gently pulsing halo. Must not take hits or it breaks the pin drag-out underneath it.
private struct SelectorBorder: View {
    var cornerRadius: CGFloat
    @State private var pulse = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            // Dark outer halo — keeps the glow visible on light/white pins.
            shape.strokeBorder(.black, lineWidth: 4)
                .blur(radius: pulse ? 9 : 6)
                .opacity(pulse ? 0.7 : 0.45)
            // Bright white halo — the glow itself.
            shape.strokeBorder(.white, lineWidth: 3)
                .blur(radius: pulse ? 6 : 4)
                .opacity(pulse ? 0.9 : 0.6)
            // Crisp edge: thin dark backing for contrast, white on top.
            shape.strokeBorder(.black.opacity(0.55), lineWidth: 2.5)
            shape.strokeBorder(.white, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Always-visible custom scrollbar

/// Reads live geometry off the real `NSScrollView` SwiftUI created (content length,
/// viewport, scroll offset), observing clip-bounds changes so the knob tracks trackpad
/// scrolling — and can write the offset back to drive scrolling from a knob drag.
@MainActor
private final class ScrollMetrics: ObservableObject {
    @Published var contentLen: CGFloat = 0
    @Published var viewport: CGFloat = 0
    @Published var offset: CGFloat = 0

    private weak var nsScroll: NSScrollView?
    private var vertical = true
    private var observers: [NSObjectProtocol] = []

    func attach(_ scrollView: NSScrollView, vertical: Bool) {
        guard nsScroll !== scrollView else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        nsScroll = scrollView
        self.vertical = vertical

        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        scrollView.postsFrameChangedNotifications = true
        scrollView.documentView?.postsFrameChangedNotifications = true

        let nc = NotificationCenter.default
        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        observers.append(nc.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main, using: handler))
        observers.append(nc.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView, queue: .main, using: handler))
        if let doc = scrollView.documentView {
            observers.append(nc.addObserver(forName: NSView.frameDidChangeNotification, object: doc, queue: .main, using: handler))
        }
        refresh()
    }

    func refresh() {
        guard let nsScroll, let doc = nsScroll.documentView else { return }
        let visible = nsScroll.documentVisibleRect
        if vertical {
            contentLen = doc.frame.height
            viewport = visible.height
            offset = visible.minY
        } else {
            contentLen = doc.frame.width
            viewport = visible.width
            offset = visible.minX
        }
    }

    func setOffset(_ target: CGFloat) {
        guard let nsScroll else { return }
        let point = vertical ? NSPoint(x: 0, y: target) : NSPoint(x: target, y: 0)
        nsScroll.contentView.scroll(to: point)
        nsScroll.reflectScrolledClipView(nsScroll.contentView)
        refresh()
    }
}

/// Captures the AppKit `NSScrollView` SwiftUI creates for a `ScrollView`. Click-through
/// (hitTest nil) so it never swallows events meant for the pins.
private struct ScrollGrabber: NSViewRepresentable {
    let onResolve: (NSScrollView) -> Void
    func makeNSView(context: Context) -> NSView { GrabberView(onResolve: onResolve) }
    func updateNSView(_ nsView: NSView, context: Context) {
        if let scroll = nsView.enclosingScrollView { onResolve(scroll) }
    }
    final class GrabberView: NSView {
        let onResolve: (NSScrollView) -> Void
        init(onResolve: @escaping (NSScrollView) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let scroll = enclosingScrollView { onResolve(scroll) }
        }
    }
}

/// A SwiftUI `ScrollView` (native layout + trackpad) with a custom always-visible
/// scrollbar whose knob is draggable. All geometry comes from the real `NSScrollView`.
private struct ScrollWithBar<Content: View>: View {
    let vertical: Bool
    let content: Content

    init(vertical: Bool, @ViewBuilder content: () -> Content) {
        self.vertical = vertical
        self.content = content()
    }

    @StateObject private var metrics = ScrollMetrics()
    @State private var dragStartOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let track = vertical ? geo.size.height : geo.size.width
            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                content.background(ScrollGrabber { metrics.attach($0, vertical: vertical) })
            }
            .overlay(alignment: vertical ? .trailing : .bottom) { bar(track: track) }
        }
    }

    private var scrollable: CGFloat { max(0, metrics.contentLen - metrics.viewport) }

    @ViewBuilder
    private func bar(track: CGFloat) -> some View {
        let hasOverflow = metrics.contentLen > metrics.viewport + 1
        let ratio = hasOverflow ? min(1, metrics.viewport / metrics.contentLen) : 1
        let knob = max(28, track * ratio)
        let travel = max(0, track - knob)
        let pos = scrollable > 0 ? min(travel, max(0, metrics.offset / scrollable * travel)) : 0

        ZStack(alignment: vertical ? .top : .leading) {
            Color.clear.allowsHitTesting(false)
            Capsule()
                .fill(.white.opacity(hasOverflow ? 0.34 : 0.16))
                .frame(width: vertical ? 7 : knob, height: vertical ? knob : 7)
                .offset(x: vertical ? 0 : pos, y: vertical ? pos : 0)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in drag(value, travel: travel) }
                )
        }
        .frame(width: vertical ? 14 : track, height: vertical ? track : 14)
        .padding(vertical ? .trailing : .bottom, 3)
    }

    private func drag(_ value: DragGesture.Value, travel: CGFloat) {
        guard travel > 0, scrollable > 0 else { return }
        if value.translation == .zero { dragStartOffset = metrics.offset } // gesture start
        let moved = vertical ? value.translation.height : value.translation.width
        let target = min(scrollable, max(0, dragStartOffset + moved / travel * scrollable))
        metrics.setOffset(target)
    }
}

#Preview("Window") {
    let model = IslandViewModel.sample()
    model.isExpanded = true
    return DrawerView(model: model)
        .frame(width: DrawerMetrics.windowSize.width, height: DrawerMetrics.windowSize.height)
        .background(.black)
}
