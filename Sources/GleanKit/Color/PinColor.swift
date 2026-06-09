import CoreGraphics
import ImageIO
import Foundation

/// A coarse, memory-friendly color range for filtering. Teal/cyan fold into blue; all
/// of white/gray/black collapse to `neutral` (genuinely monochrome pins).
public enum ColorBucket: String, Codable, CaseIterable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, brown, neutral
}

/// Extracts a pin's dominant color range. Ignores near-white / near-black / desaturated
/// (background) pixels and takes the dominant HUE among what's actually colorful — only
/// falling back to `neutral` when too little of the image is chromatic.
public enum ColorAnalyzer {
    /// Minimum fraction of clearly-chromatic pixels for a pin to get a color (else neutral).
    public static let chromaThreshold = 0.13

    public static func bucket(forData data: Data) -> ColorBucket? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return bucket(for: cg)
    }

    public static func bucket(for cg: CGImage) -> ColorBucket {
        let n = 32
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &buf, width: n, height: n, bitsPerComponent: 8,
                                  bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .neutral }
        ctx.setFillColor(gray: 1, alpha: 1) // transparent → white card, then ignored below
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var bins = [Double](repeating: 0, count: 36) // 10° per bin, saturation-weighted
        var chroma = 0, total = 0
        var cSat = 0.0, cBri = 0.0
        for i in stride(from: 0, to: buf.count, by: 4) {
            let r = Double(buf[i]) / 255, g = Double(buf[i + 1]) / 255, b = Double(buf[i + 2]) / 255
            let (h, s, br) = hsb(r, g, b)
            total += 1
            if s > 0.18 && br > 0.12 && br < 0.97 {
                chroma += 1
                bins[Int(h * 36) % 36] += s
                cSat += s; cBri += br
            }
        }
        let frac = total > 0 ? Double(chroma) / Double(total) : 0
        guard frac >= chromaThreshold, chroma > 0 else { return .neutral }

        var best = 0, bestV = -1.0
        for k in 0..<36 {
            let v = bins[(k + 35) % 36] * 0.5 + bins[k] + bins[(k + 1) % 36] * 0.5 // smoothed
            if v > bestV { bestV = v; best = k }
        }
        return hueBucket(Double(best) * 10 + 5, sat: cSat / Double(chroma), bri: cBri / Double(chroma))
    }

    private static func hueBucket(_ deg: Double, sat: Double, bri: Double) -> ColorBucket {
        if deg < 45 && bri < 0.5 && sat > 0.3 { return .brown }
        switch deg {
        case ..<15, 345...: return .red
        case 15..<45: return .orange
        case 45..<70: return .yellow
        case 70..<170: return .green
        case 170..<255: return .blue // includes teal/cyan
        case 255..<290: return .purple
        default: return .pink
        }
    }

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, b: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        let s = mx == 0 ? 0 : d / mx
        var h = 0.0
        if d != 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h / 360, s, mx)
    }
}
