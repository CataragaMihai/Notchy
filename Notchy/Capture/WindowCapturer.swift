import CoreGraphics
import Foundation
import NotchyCore
import os
import ScreenCaptureKit

/// Captures the frontmost window (or the display under the pointer) at the model's target size.
struct WindowCapturer: Capturer {
    private let logger = Logger(subsystem: AppInfo.logSubsystem, category: "capture")

    func capture(limits: ImageLimits, frontmostPID: pid_t?, pointer: CGPoint) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let filter: SCContentFilter
        if let pid = frontmostPID, pid != ownPID,
           let windowID = Self.frontmostWindowID(pid: pid),
           let window = content.windows.first(where: { $0.windowID == windowID }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else if let display = content.displays.first(where: { $0.frame.contains(pointer) }) ?? content.displays.first {
            let ownApps = content.applications.filter { $0.processID == ownPID }
            filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            logger.info("No frontmost window; capturing the display under the pointer")
        } else {
            throw NotchyError.captureFailed("no window or display found")
        }

        let scale = CGFloat(filter.pointPixelScale)
        let source = PixelSize(width: Int(filter.contentRect.width * scale),
                               height: Int(filter.contentRect.height * scale))
        let target = ImageSizing.targetSize(for: source, limits: limits)

        let configuration = SCStreamConfiguration()
        configuration.width = target.width
        configuration.height = target.height
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let jpeg = JPEGEncoder.encode(image) else {
            throw NotchyError.captureFailed("could not encode the image")
        }
        let size = PixelSize(width: image.width, height: image.height)
        logger.info("Captured \(source.description, privacy: .public) → \(size.description, privacy: .public), \(ImageSizing.visualTokens(size)) tokens, \(jpeg.count / 1024) KB")
        return CapturedImage(jpeg: jpeg, size: size, tokens: ImageSizing.visualTokens(size))
    }

    /// The window list is ordered front to back. The app's frontmost normal window is the first one
    /// big enough to hold content: a full-screen app's toolbar is its own thin window in front of the
    /// main one, and capturing it sends a strip. Falls back to the first window if none is that big.
    private static func frontmostWindowID(pid: pid_t) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var fallback: CGWindowID?
        for info in windows {
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let number = info[kCGWindowNumber as String] as? CGWindowID
            else { continue }
            let width = bounds["Width"] ?? 0, height = bounds["Height"] ?? 0
            if min(width, height) >= minContentSide { return number }
            if fallback == nil, width > 50, height > 50 { fallback = number }
        }
        return fallback
    }

    /// Smallest side, in points, of a window worth capturing on its own.
    private static let minContentSide: CGFloat = 200
}
