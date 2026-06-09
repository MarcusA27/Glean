import Vision
import CoreGraphics
import ImageIO
import Foundation

/// On-device image classification, used to make pins with junk/empty titles findable by
/// what's *in* them. Returns lowercased label tokens (underscores → spaces) so a query
/// like "tree" matches "oak tree". Drops a few labels too generic to help search.
public enum LabelAnalyzer {
    private static let stop: Set<String> = ["art", "illustrations", "material", "structure"]

    public static func labels(forData data: Data) -> [String]? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return labels(for: cg)
    }

    public static func labels(for cg: CGImage) -> [String] {
        let req = VNClassifyImageRequest()
        try? VNImageRequestHandler(cgImage: cg).perform([req])
        let results = (req.results ?? []).filter { $0.confidence >= 0.2 }.prefix(8)
        var out: [String] = []
        for r in results {
            let token = r.identifier.replacingOccurrences(of: "_", with: " ").lowercased()
            if !stop.contains(token) && !out.contains(token) { out.append(token) }
        }
        return out
    }
}
