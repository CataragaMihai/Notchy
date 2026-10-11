/// A size in pixels.
public struct PixelSize: Sendable, Equatable, CustomStringConvertible {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public var description: String { "\(width)×\(height)" }
}

/// Client-side downscaling so the image fits the model's limits exactly,
/// which keeps uploads small and token cost predictable.
public enum ImageSizing {
    public static let patchSize = 28

    /// `ceil(width / 28) × ceil(height / 28)`, from the vision docs.
    public static func visualTokens(_ size: PixelSize) -> Int {
        ceilDiv(size.width, patchSize) * ceilDiv(size.height, patchSize)
    }

    /// The largest aspect-preserving size within both the long-edge and token limits.
    public static func targetSize(for source: PixelSize, limits: ImageLimits) -> PixelSize {
        guard source.width > 0, source.height > 0 else { return source }
        if fits(source, limits) { return source }

        let landscape = source.width >= source.height
        let long = Double(landscape ? source.width : source.height)
        let short = Double(landscape ? source.height : source.width)

        // Continuous estimate of the token-limited long edge, plus a margin for rounding.
        let tokenScale = (Double(limits.maxVisualTokens * patchSize * patchSize) / (long * short)).squareRoot()
        var candidate = min(Int(long), limits.maxLongEdge, Int(long * tokenScale) + 2)

        // Shrinking the long edge never increases the token count, so the first fit is the largest.
        while candidate > 1 {
            let other = max(1, Int((short * Double(candidate) / long).rounded()))
            let size = landscape
                ? PixelSize(width: candidate, height: other)
                : PixelSize(width: other, height: candidate)
            if fits(size, limits) { return size }
            candidate -= 1
        }
        return PixelSize(width: 1, height: 1)
    }

    private static func fits(_ size: PixelSize, _ limits: ImageLimits) -> Bool {
        max(size.width, size.height) <= limits.maxLongEdge
            && visualTokens(size) <= limits.maxVisualTokens
    }

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
}
