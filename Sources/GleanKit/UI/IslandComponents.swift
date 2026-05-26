import SwiftUI

/// The resting pill: just the word "boards" in an italic serif.
struct CollapsedContent: View {
    var body: some View {
        Text("Glean")
            .font(.system(size: 13, weight: .regular, design: .serif))
            .italic()
            .foregroundStyle(.white.opacity(0.9))
    }
}

/// The expanded strip: board filter chips above a horizontally scrolling pin row.
struct ExpandedContent: View {
    @ObservedObject var model: IslandViewModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 9)

    var body: some View {
        VStack(spacing: 12) {
            BoardChips(model: model)
                .overlay(alignment: .trailing) {
                    RefreshButton(isReloading: model.isReloading) { model.reload() }
                        .padding(.trailing, 12)
                }
            if model.visiblePins.isEmpty {
                Text(model.isLoading ? "Loading your pins…" : "No pins")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(model.visiblePins) { pin in
                            PinThumbnailView(pin: pin) { dragging in
                                model.isDragging = dragging
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 96)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct BoardChips: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    Chip(title: "All", selected: model.selectedBoardID == nil) {
                        select(nil)
                    }
                    ForEach(model.boards) { board in
                        Chip(title: board.name, selected: model.selectedBoardID == board.id) {
                            select(board.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                // Center the chips; only scrolls once they exceed the island width.
                .frame(minWidth: geo.size.width, alignment: .center)
            }
        }
        .frame(height: 28)
    }

    private func select(_ id: String?) {
        withAnimation(.easeOut(duration: 0.2)) { model.selectedBoardID = id }
    }
}

struct RefreshButton: View {
    let isReloading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.10)))
                .rotationEffect(.degrees(isReloading ? 360 : 0))
                .animation(isReloading
                           ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                           : .default,
                           value: isReloading)
        }
        .buttonStyle(.plain)
        .disabled(isReloading)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.82))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.white : Color.white.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}
