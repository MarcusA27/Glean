import SwiftUI
import AppKit

/// Frosted-glass backing for the island. `.behindWindow` blends with whatever is
/// under the transparent panel, giving the dynamic-island depth.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension Color {
    /// Hex like "#RRGGBB". Falls back to gray on a malformed string.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value & 0xFF0000) >> 16) / 255,
            green: Double((value & 0x00FF00) >> 8) / 255,
            blue: Double(value & 0x0000FF) / 255
        )
    }
}
