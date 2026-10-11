// Renders the disk image window's background: the notch at the top, the instruction, an arrow
// from where Notchy's icon sits to where Applications sits, and a note about Open Anyway.
// Writes background.png (640×420) and background@2x.png into the folder given as the argument.
// The icon positions here must match scripts/release.sh.
//
//   swift Design/dmg/background.swift <output folder>
import AppKit

let size = CGSize(width: 640, height: 420)
let appIcon = CGPoint(x: 170, y: 220)
let applicationsIcon = CGPoint(x: 470, y: 220)

// Finder draws the icon labels black in light mode and white in dark mode, and the background
// cannot change with the appearance. Every colour here is a mid tone (relative luminance about
// 0.15–0.21), so both label colours stay above 4:1 contrast wherever the labels land.
func srgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let indigo = srgb(0x4E4AD6)
let violet = srgb(0x6C43CC)
let blue = srgb(0x346AE8)
let magenta = srgb(0xB045CC)
let rose = srgb(0xE0559A)
let glow = srgb(0xA79BFF)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

/// Draws text centred on `centerX` with its top at `y` (top-left coordinates).
func text(_ string: String, font: NSFont, color: NSColor, y: CGFloat, centerX: CGFloat = size.width / 2,
          width: CGFloat = 520) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = 2
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = attributed.boundingRect(with: CGSize(width: width, height: 200), options: [.usesLineFragmentOrigin])
    attributed.draw(with: CGRect(x: centerX - width / 2, y: y, width: width, height: bounds.height),
                     options: [.usesLineFragmentOrigin])
}

func measure(_ string: String, font: NSFont) -> CGSize {
    NSAttributedString(string: string, attributes: [.font: font]).size()
}

/// The notch as Notchy draws it, grown into the dropdown: flat along the top edge, small flares
/// where it meets the edge, rounded bottom corners.
func notch(width: CGFloat, height: CGFloat, radius: CGFloat) -> NSBezierPath {
    let flare: CGFloat = 10
    let left = (size.width - width) / 2, right = left + width
    let path = NSBezierPath()
    path.move(to: CGPoint(x: left - flare, y: 0))
    path.line(to: CGPoint(x: right + flare, y: 0))
    path.curve(to: CGPoint(x: right, y: flare), controlPoint1: CGPoint(x: right, y: 0), controlPoint2: CGPoint(x: right, y: 0))
    path.line(to: CGPoint(x: right, y: height - radius))
    path.appendArc(withCenter: CGPoint(x: right - radius, y: height - radius), radius: radius, startAngle: 0, endAngle: 90)
    path.line(to: CGPoint(x: left + radius, y: height))
    path.appendArc(withCenter: CGPoint(x: left + radius, y: height - radius), radius: radius, startAngle: 90, endAngle: 180)
    path.line(to: CGPoint(x: left, y: flare))
    path.curve(to: CGPoint(x: left - flare, y: 0), controlPoint1: CGPoint(x: left, y: 0), controlPoint2: CGPoint(x: left, y: 0))
    path.close()
    return path
}

func withShadow(blur: CGFloat, y: CGFloat, alpha: CGFloat, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = CGSize(width: 0, height: -y) // flipped context: negative is down
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

/// A soft round light of `color`, fading to nothing at `radius`.
func blob(_ color: NSColor, at center: CGPoint, radius: CGFloat, alpha: CGFloat) {
    NSGradient(colors: [color.withAlphaComponent(alpha), color.withAlphaComponent(alpha * 0.45), color.withAlphaComponent(0)],
               atLocations: [0, 0.5, 1], colorSpace: .sRGB)!
        .draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

/// Fine film grain, so the gradient does not band and looks less flat. Seeded, so every build matches.
func grain() {
    var seed: UInt64 = 0x4E6F74636879
    func next() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(1 << 31)
    }
    for _ in 0..<9000 {
        let point = CGPoint(x: next() * size.width, y: next() * size.height)
        (next() > 0.5 ? NSColor.white : NSColor.black).withAlphaComponent(0.035).setFill()
        CGRect(x: point.x, y: point.y, width: 0.75, height: 0.75).fill()
    }
}

func draw() {
    // A mesh-like wash: indigo to violet across the window, blue rising from the bottom left,
    // magenta from the top right, a touch of rose in the far corner, and a soft light between the icons.
    NSGradient(starting: indigo, ending: violet)!.draw(in: CGRect(origin: .zero, size: size), angle: -35)
    blob(blue, at: CGPoint(x: 40, y: 430), radius: 380, alpha: 0.85)
    blob(magenta, at: CGPoint(x: 620, y: 10), radius: 360, alpha: 0.8)
    blob(rose, at: CGPoint(x: 660, y: 440), radius: 230, alpha: 0.45)
    blob(glow, at: CGPoint(x: size.width / 2, y: 205), radius: 130, alpha: 0.22)
    grain()

    // The notch, grown into a dropdown that holds the instruction, as the app greets you.
    let dropdown = notch(width: 380, height: 96, radius: 26)
    withShadow(blur: 24, y: 10, alpha: 0.35) {
        NSColor.black.setFill()
        dropdown.fill()
    }
    text("Drag Notchy into Applications", font: rounded(21, .bold), color: .white, y: 28)
    text("Then open it from your Applications folder.", font: rounded(12.5, .medium),
         color: NSColor.white.withAlphaComponent(0.6), y: 59)

    // A dotted arc from Notchy to Applications that brightens towards the arrowhead.
    let start = CGPoint(x: appIcon.x + 76, y: appIcon.y - 6)
    let end = CGPoint(x: applicationsIcon.x - 76, y: applicationsIcon.y - 6)
    let c1 = CGPoint(x: start.x + 40, y: start.y - 38), c2 = CGPoint(x: end.x - 40, y: end.y - 38)
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * u * start.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                       y: u * u * u * start.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y)
    }
    let dots = 13
    for index in 0..<dots {
        let t = CGFloat(index) / CGFloat(dots - 1) * 0.94
        let p = point(t)
        let radius = 1.6 + 1.2 * t
        NSColor.white.withAlphaComponent(0.25 + 0.7 * t).setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    // Along the curve's direction at its end, opened 32° each way.
    let direction = atan2(end.y - c2.y, end.x - c2.x)
    func barb(_ turn: CGFloat) -> CGPoint {
        CGPoint(x: end.x - 13 * cos(direction + turn), y: end.y - 13 * sin(direction + turn))
    }
    let head = NSBezierPath()
    head.move(to: barb(0.56))
    head.line(to: end)
    head.line(to: barb(-0.56))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    NSColor.white.setStroke()
    head.stroke()

    // The Open Anyway note, on a dark pill along the bottom.
    let note = "First launch: System Settings › Privacy & Security › Open Anyway"
    let noteFont = rounded(12, .semibold)
    let noteSize = measure(note, font: noteFont)
    let symbol = NSImage(systemSymbolName: "checkmark.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))!
    let pillWidth = noteSize.width + 18 + 8 + 36
    let pill = CGRect(x: (size.width - pillWidth) / 2, y: 356, width: pillWidth, height: 32)
    NSColor.black.withAlphaComponent(0.32).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 16, yRadius: 16).fill()
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.withAlphaComponent(0.9).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: CGRect(x: pill.minX + 18, y: pill.midY - symbol.size.height / 2,
                           width: symbol.size.width, height: symbol.size.height),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    let label = NSAttributedString(string: note, attributes: [.font: noteFont,
                                                              .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
    label.draw(at: CGPoint(x: pill.minX + 18 + symbol.size.width + 8, y: pill.midY - noteSize.height / 2))
}

func render(scale: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    // Top-left origin, like Finder's icon positions.
    context.cgContext.translateBy(x: 0, y: size.height)
    context.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
render(scale: 1, to: folder.appending(path: "background.png"))
render(scale: 2, to: folder.appending(path: "background@2x.png"))
