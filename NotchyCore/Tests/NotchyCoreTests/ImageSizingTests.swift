import Testing
@testable import NotchyCore

struct ImageSizingTests {
    @Test("Examples from the vision docs and this Mac's display", arguments: [
        (PixelSize(width: 3840, height: 2160), ImageLimits.highResolution, PixelSize(width: 2576, height: 1449), 4784),
        (PixelSize(width: 1920, height: 1080), ImageLimits.highResolution, PixelSize(width: 1920, height: 1080), 2691),
        (PixelSize(width: 2000, height: 1500), ImageLimits.highResolution, PixelSize(width: 2000, height: 1500), 3888),
        (PixelSize(width: 200, height: 200), ImageLimits.highResolution, PixelSize(width: 200, height: 200), 64),
        (PixelSize(width: 3840, height: 2160), ImageLimits.standard, PixelSize(width: 1456, height: 819), 1560),
        (PixelSize(width: 1920, height: 1080), ImageLimits.standard, PixelSize(width: 1456, height: 819), 1560),
        (PixelSize(width: 2560, height: 1664), ImageLimits.highResolution, PixelSize(width: 2380, height: 1547), 4760),
        (PixelSize(width: 2560, height: 1664), ImageLimits.standard, PixelSize(width: 1372, height: 892), 1568),
    ])
    func targetSize(source: PixelSize, limits: ImageLimits, expected: PixelSize, tokens: Int) {
        let size = ImageSizing.targetSize(for: source, limits: limits)
        #expect(size == expected)
        #expect(ImageSizing.visualTokens(size) == tokens)
    }

    @Test func portraitMirrorsLandscape() {
        let size = ImageSizing.targetSize(for: PixelSize(width: 1664, height: 2560), limits: .highResolution)
        #expect(size == PixelSize(width: 1547, height: 2380))
    }

    @Test func veryWideImageIsLimitedByLongEdge() {
        let size = ImageSizing.targetSize(for: PixelSize(width: 8000, height: 400), limits: .highResolution)
        #expect(size.width <= 2576)
        #expect(ImageSizing.visualTokens(size) <= 4784)
    }
}
