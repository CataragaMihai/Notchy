import CoreGraphics

/// Where the notch is, and where the dropdown goes. AppKit coordinates (origin bottom left).
public enum NotchGeometry {
    /// The notch is the gap between the two auxiliary top areas, as tall as the top safe-area inset.
    /// Returns nil for a screen without a notch.
    public static func notchRect(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?
    ) -> CGRect? {
        guard safeAreaTop > 0, let left = leftAreaWidth, let right = rightAreaWidth else { return nil }
        let width = screenFrame.width - left - right
        guard width > 0 else { return nil }
        return CGRect(x: screenFrame.minX + left,
                      y: screenFrame.maxY - safeAreaTop,
                      width: width,
                      height: safeAreaTop)
    }

    /// The dropdown hangs from the top edge of the screen, centred on the notch
    /// (or on the screen when there is no notch).
    public static func dropdownFrame(notch: CGRect?, screenFrame: CGRect, size: CGSize) -> CGRect {
        let centerX = notch?.midX ?? screenFrame.midX
        var x = (centerX - size.width / 2).rounded()
        x = min(max(x, screenFrame.minX), screenFrame.maxX - size.width)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }
}
