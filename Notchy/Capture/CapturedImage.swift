import Foundation
import NotchyCore

/// The encoded image exactly as it will be sent.
struct CapturedImage: Sendable {
    let jpeg: Data
    let size: PixelSize
    let tokens: Int
}

protocol Capturer: Sendable {
    func capture(limits: ImageLimits, frontmostPID: pid_t?, pointer: CGPoint) async throws -> CapturedImage
}
