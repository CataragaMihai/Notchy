// Renders notchy-icon.svg into the app's AppIcon set and copies the menu bar glyph.
// Run from the repo root after generate.py:  swift Design/icon/render.swift
import AppKit

let icon = NSImage(contentsOfFile: "Design/icon/notchy-icon.svg")!
let appIconSet = "Notchy/Assets.xcassets/AppIcon.appiconset"

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(appIconSet)/\(name)"))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(appIconSet)/Contents.json"))

try? FileManager.default.removeItem(atPath: "Notchy/Assets.xcassets/MenuBarIcon.imageset/menubar-glyph.svg")
try! FileManager.default.copyItem(atPath: "Design/icon/menubar-glyph.svg",
                                  toPath: "Notchy/Assets.xcassets/MenuBarIcon.imageset/menubar-glyph.svg")
print("Rendered \(images.count) icon sizes")
