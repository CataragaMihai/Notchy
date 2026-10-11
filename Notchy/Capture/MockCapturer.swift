import CoreGraphics
import Foundation
import NotchyCore

/// A flat grey image, for UI work without Screen Recording permission.
struct MockCapturer: Capturer {
    func capture(limits: ImageLimits, frontmostPID: pid_t?, pointer: CGPoint) async throws -> CapturedImage {
        try await Task.sleep(for: .milliseconds(80))
        let size = ImageSizing.targetSize(for: PixelSize(width: 2560, height: 1664), limits: limits)
        guard let context = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { throw NotchyError.captureFailed("mock context") }
        context.setFillColor(CGColor(gray: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.setFillColor(CGColor(gray: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: size.height - 120, width: size.width, height: 120))
        guard let image = context.makeImage(), let jpeg = JPEGEncoder.encode(image)
        else { throw NotchyError.captureFailed("mock image") }
        return CapturedImage(jpeg: jpeg, size: size, tokens: ImageSizing.visualTokens(size))
    }
}
