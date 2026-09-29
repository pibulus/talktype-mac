// ===================================================================
// TalkType art generator — AppIcon.icns + DMG window background
// Run from repo root:  swift Assets/make-art.swift
// ===================================================================
// Icon: warm-cream squircle on Apple's macOS grid (824pt body, 100pt margin,
// continuous 185.4 corners). Drawing ON the squircle is what keeps macOS 26
// from jailing the icon inside a gray plate. Ghost sits as big as it breathes.
import AppKit
import QuartzCore

let sepia = NSColor(srgbRed: 0.118, green: 0.090, blue: 0.078, alpha: 1)   // #1e1714
let softSepia = NSColor(srgbRed: 0.43, green: 0.36, blue: 0.31, alpha: 1)
let pink = NSColor(srgbRed: 1.0, green: 0.478, blue: 0.851, alpha: 1)      // ghost gradient ends
let peach = NSColor(srgbRed: 1.0, green: 0.643, blue: 0.424, alpha: 1)

func bitmap(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func writePNG(_ ctx: CGContext, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

func run(_ args: String...) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    try! p.run(); p.waitUntilExit()
    precondition(p.terminationStatus == 0, "failed: \(args.joined(separator: " "))")
}

func inter(_ size: CGFloat, _ weight: Int) -> NSFont {
    NSFontManager.shared.font(withFamily: "Inter", traits: [], weight: weight, size: size)
        ?? .systemFont(ofSize: size, weight: weight >= 9 ? .bold : .regular)
}

// ===================================================================
// App icon
// ===================================================================
func drawIcon(_ ghost: CGImage, _ size: Int) -> CGContext {
    let ctx = bitmap(size, size)
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let layer = CAGradientLayer()
    layer.frame = CGRect(origin: .zero, size: plate.size)
    layer.colors = [CGColor(srgbRed: 1.0, green: 0.984, blue: 0.957, alpha: 1),
                    CGColor(srgbRed: 0.984, green: 0.945, blue: 0.894, alpha: 1)]
    layer.startPoint = CGPoint(x: 0.5, y: 1); layer.endPoint = CGPoint(x: 0.5, y: 0)
    layer.cornerRadius = 185.4; layer.cornerCurve = .continuous; layer.masksToBounds = true
    // Soft drop shadow for pre-Tahoe Finder; macOS 26 draws its own and ignores this.
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: sepia.withAlphaComponent(0.3).cgColor)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.translateBy(x: plate.minX, y: plate.minY); layer.render(in: ctx); ctx.translateBy(x: -plate.minX, y: -plate.minY)
    ctx.endTransparencyLayer()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    // ghost.png content bbox is 962x966 at +31+29 inside its 1024 canvas
    let crop = ghost.cropping(to: CGRect(x: 31, y: 29, width: 962, height: 966))!
    let w = plate.width * 0.84, h = w * 966 / 962
    ctx.interpolationQuality = .high
    ctx.draw(crop, in: CGRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h))
    return ctx
}

func makeIcon() {
    let ghost = NSImage(contentsOfFile: "Assets/ghost.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let set = NSTemporaryDirectory() + "AppIcon.iconset"
    try? FileManager.default.removeItem(atPath: set)
    try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
    for pt in [16, 32, 128, 256, 512] {
        writePNG(drawIcon(ghost, pt), "\(set)/icon_\(pt)x\(pt).png")
        writePNG(drawIcon(ghost, pt * 2), "\(set)/icon_\(pt)x\(pt)@2x.png")
    }
    run("iconutil", "-c", "icns", set, "-o", "Assets/AppIcon.icns")
    print("✨ Assets/AppIcon.icns")
}

// ===================================================================
// DMG background — 660x400 content; build.sh places icons at y=190
// ===================================================================
let dmgW: CGFloat = 660, dmgH: CGFloat = 400
let appX: CGFloat = 165, dropX: CGFloat = 495, iconY: CGFloat = 190

func drawBackground(_ scale: Int) -> CGContext {
    let ctx = bitmap(Int(dmgW) * scale, Int(dmgH) * scale)
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    ctx.translateBy(x: 0, y: dmgH); ctx.scaleBy(x: 1, y: -1)   // top-left origin, like Finder
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

    // Creamy paper, faint warm fall-off toward the bottom
    let paper = NSGradient(starting: NSColor(srgbRed: 0.992, green: 0.965, blue: 0.925, alpha: 1),
                           ending: NSColor(srgbRed: 0.984, green: 0.937, blue: 0.878, alpha: 1))!
    paper.draw(in: NSRect(x: 0, y: 0, width: dmgW, height: dmgH), angle: 90)

    func text(_ s: String, _ font: NSFont, _ color: NSColor, _ y: CGFloat, kern: CGFloat = 0) {
        let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: kern])
        str.draw(at: NSPoint(x: (dmgW - str.size().width) / 2, y: y))
    }
    text("TalkType", inter(30, 10), sepia, 30, kern: -0.6)
    text("Menu-bar dictation with the ghost", inter(13, 5), softSepia, 72)

    // Chunky toybrut arrow: ghost gradient, sepia outline, hard offset shadow
    let x0 = appX + 82, x1 = dropX - 82, shaft: CGFloat = 16, headW: CGFloat = 34, headH: CGFloat = 44
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: x0, y: iconY - shaft / 2))
    arrow.line(to: NSPoint(x: x1 - headW, y: iconY - shaft / 2))
    arrow.line(to: NSPoint(x: x1 - headW, y: iconY - headH / 2))
    arrow.line(to: NSPoint(x: x1, y: iconY))
    arrow.line(to: NSPoint(x: x1 - headW, y: iconY + headH / 2))
    arrow.line(to: NSPoint(x: x1 - headW, y: iconY + shaft / 2))
    arrow.line(to: NSPoint(x: x0, y: iconY + shaft / 2))
    arrow.close()
    arrow.lineJoinStyle = .round; arrow.lineWidth = 3
    let shadow = arrow.copy() as! NSBezierPath
    shadow.transform(using: AffineTransform(translationByX: 4, byY: 4))
    sepia.withAlphaComponent(0.85).setFill(); shadow.fill()
    NSGradient(starting: pink, ending: peach)!.draw(in: arrow, angle: 0)
    sepia.setStroke(); arrow.stroke()

    text("DRAG TO INSTALL", inter(10, 7), softSepia, iconY + 36, kern: 1.6)
    text("Hold Right ⌥ Option  ·  talk  ·  release to paste", inter(12, 6), softSepia, dmgH - 52)
    NSGraphicsContext.current = nil
    return ctx
}

func makeBackground() {
    let tmp = NSTemporaryDirectory()
    writePNG(drawBackground(1), tmp + "dmg-bg.png")
    writePNG(drawBackground(2), tmp + "dmg-bg@2x.png")
    run("tiffutil", "-cathidpicheck", tmp + "dmg-bg.png", tmp + "dmg-bg@2x.png", "-out", "Assets/dmg-background.tiff")
    print("✨ Assets/dmg-background.tiff (1x + 2x)")
}

makeIcon()
makeBackground()
