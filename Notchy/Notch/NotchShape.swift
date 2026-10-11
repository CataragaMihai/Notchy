import SwiftUI

/// The notch's outline: flat along the top edge of the screen, with small outward flares where it
/// meets the edge (like the physical notch) and rounded bottom corners. Collapsed it matches the
/// physical notch; the dropdown is the same shape grown wider and taller.
struct NotchShape: Shape {
    static let flare: CGFloat = 8
    /// Black drawn above the top of the screen, so no seam can show where the shape meets the edge.
    static let topBleed: CGFloat = 4

    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    /// `rect` includes the bleed: the screen's top edge is `topBleed` below `rect.minY`.
    func path(in rect: CGRect) -> Path {
        let edge = rect.minY + Self.topBleed
        let flare = min(Self.flare, rect.width / 4, (rect.maxY - edge) / 2)
        let bottom = max(0, min(bottomRadius, (rect.width - 2 * flare) / 2, rect.maxY - edge - flare))
        let left = rect.minX + flare
        let right = rect.maxX - flare

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: edge))
        path.addQuadCurve(to: CGPoint(x: right, y: edge + flare), control: CGPoint(x: right, y: edge))
        path.addArc(tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.maxY), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: left, y: rect.minY), radius: bottom)
        path.addLine(to: CGPoint(x: left, y: edge + flare))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: edge), control: CGPoint(x: left, y: edge))
        path.closeSubpath()
        return path
    }
}
