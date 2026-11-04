#!/usr/bin/env swift
// ============================================================================
// TalkType Mac App Store Retina Screenshot Generator (2880 × 1800)
// Run from repo root:  swift scripts/generate-mas-screenshots.swift
//
// Strict Fleet Laws:
// - Warm Flexoki Palette: near-white (#FFFEF7 / #FFF6E6), creamy paper cards
//   (#FBF1E4 / #FDF2E0), warm sepia ink (#1E1714). NEVER pure #FFF or #000.
// - Sovereign Voice Law: zero "you/your", zero "AI", zero emoji bullets.
// - 100% MAS-true mechanics: ⌃⌥ Space, click ghost to talk / click again to
//   finish, Copied to clipboard — Press ⌘V to paste!, zero Accessibility refs.
// - Mascot eyes OPEN (composited directly from Assets/ghost.png).
// ============================================================================

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let W = 2880
let H = 1800

// Warm Flexoki Palette (sRGB, zero #FFF, zero #000)
let cCanvasTop   = NSColor(srgbRed: 255/255, green: 254/255, blue: 247/255, alpha: 1.0) // #FFFEF7 warm near-white
let cCanvasMid   = NSColor(srgbRed: 255/255, green: 246/255, blue: 230/255, alpha: 1.0) // #FFF6E6 warm cream
let cCanvasBot   = NSColor(srgbRed: 253/255, green: 238/255, blue: 218/255, alpha: 1.0) // #FDEEDA toasted cream
let cPopoverLit  = NSColor(srgbRed: 255/255, green: 248/255, blue: 237/255, alpha: 1.0) // #FFF8ED
let cPopoverMid  = NSColor(srgbRed: 251/255, green: 241/255, blue: 228/255, alpha: 1.0) // #FBF1E4 creamy card
let cCardInner   = NSColor(srgbRed: 253/255, green: 242/255, blue: 224/255, alpha: 1.0) // #FDF2E0 transcript paper
let cPillCream   = NSColor(srgbRed: 255/255, green: 251/255, blue: 242/255, alpha: 1.0) // #FFFBF2
let cInk         = NSColor(srgbRed: 30/255,  green: 23/255,  blue: 20/255,  alpha: 1.0) // #1E1714 warm sepia near-black
let cInkSoft     = NSColor(srgbRed: 86/255,  green: 74/255,  blue: 66/255,  alpha: 1.0) // #564A42
let cInkMute     = NSColor(srgbRed: 126/255, green: 112/255, blue: 102/255, alpha: 1.0) // #7E7066
let cBorder      = NSColor(srgbRed: 30/255,  green: 23/255,  blue: 20/255,  alpha: 0.18)
let cBorderStrong = NSColor(srgbRed: 30/255, green: 23/255,  blue: 20/255,  alpha: 0.26)
let cPink        = NSColor(srgbRed: 255/255, green: 130/255, blue: 202/255, alpha: 1.0) // #FF82CA
let cPinkDeep    = NSColor(srgbRed: 184/255, green: 68/255,  blue: 136/255, alpha: 1.0) // #B84488 high-contrast berry
let cPeach       = NSColor(srgbRed: 255/255, green: 176/255, blue: 96/255,  alpha: 1.0) // #FFB060
let cSun         = NSColor(srgbRed: 255/255, green: 207/255, blue: 64/255,  alpha: 1.0) // #FFCF40
let cMint        = NSColor(srgbRed: 36/255,  green: 148/255, blue: 124/255, alpha: 1.0) // #24947C

guard let ghostImg = NSImage(contentsOfFile: "Assets/ghost.png"),
      let ghostCG = ghostImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fputs("Error: Missing Assets/ghost.png (run from repo root)\n", stderr)
    exit(1)
}
let menubarGhostImg = NSImage(contentsOfFile: "Assets/ghost-menubar.png")

// Top-left coordinate system helper (y=0 at top, y=1800 at bottom)
func makeCanvas() -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: W,
        height: H,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    return ctx
}

func saveCanvas(_ ctx: CGContext, to path: String) {
    NSGraphicsContext.current = nil
    let cg = ctx.makeImage()!
    // Render into 32-bit RGBX (noneSkipLast) and encode via CGImageDestination so the PNG IHDR
    // is true 24-bit opaque RGB (color_type=2, hasAlpha: no) for App Store Connect Media Manager.
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let rgbCtx = CGContext(
        data: nil,
        width: W,
        height: H,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    rgbCtx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
    let rgbImage = rgbCtx.makeImage()!

    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, rgbImage, nil)
    precondition(CGImageDestinationFinalize(dest), "Failed to write PNG to \(path)")
    print("✨ Wrote \(path) (\(rgbImage.width)×\(rgbImage.height), RGB24 no-alpha)")
}

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let desc = base.fontDescriptor.withDesign(.rounded),
       let rounded = NSFont(descriptor: desc, size: size) {
        return rounded
    }
    return base
}

func monoFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func fillBackground(_ ctx: CGContext, glowCenter: CGPoint) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let grad = CGGradient(
        colorsSpace: cs,
        colors: [cCanvasTop.cgColor, cCanvasMid.cgColor, cCanvasBot.cgColor] as CFArray,
        locations: [0.0, 0.55, 1.0]
    )!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(H)), options: [])

    // Soft warm peach-pink atmospheric aura (never white wash)
    let auraColors = [
        cPink.withAlphaComponent(0.18).cgColor,
        cPeach.withAlphaComponent(0.12).cgColor,
        cCanvasMid.withAlphaComponent(0.0).cgColor
    ] as CFArray
    let aura = CGGradient(colorsSpace: cs, colors: auraColors, locations: [0.0, 0.45, 1.0])!
    ctx.drawRadialGradient(
        aura,
        startCenter: glowCenter, startRadius: 20,
        endCenter: glowCenter, endRadius: 820,
        options: [.drawsAfterEndLocation]
    )
}

func rrectPath(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBox(
    _ ctx: CGContext,
    _ rect: CGRect,
    radius: CGFloat,
    fill: NSColor? = nil,
    gradient: [NSColor]? = nil,
    angle: CGFloat = 90,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 2,
    shadowOpacity: CGFloat = 0,
    shadowBlur: CGFloat = 32,
    shadowY: CGFloat = 18
) {
    let path = rrectPath(rect, radius)
    if shadowOpacity > 0 {
        ctx.saveGState()
        // In flipped CGContext, negative height in setShadow shifts shadow downward on screen
        ctx.setShadow(
            offset: CGSize(width: 0, height: -shadowY),
            blur: shadowBlur,
            color: cInk.withAlphaComponent(shadowOpacity).cgColor
        )
        (fill ?? gradient?.first ?? cPopoverMid).setFill()
        path.fill()
        ctx.restoreGState()
    }
    if let gradient = gradient, gradient.count >= 2 {
        let nsGrad = NSGradient(colors: gradient)!
        nsGrad.draw(in: path, angle: angle)
    } else if let fill = fill {
        fill.setFill()
        path.fill()
    }
    if let stroke = stroke, lineWidth > 0 {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

@discardableResult
func drawString(
    _ text: String,
    font: NSFont,
    color: NSColor,
    at pt: CGPoint,
    align: NSTextAlignment = .left,
    kern: CGFloat = 0,
    maxWidth: CGFloat? = nil,
    lineSpacing: CGFloat = 4
) -> CGSize {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineSpacing = lineSpacing
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: kern,
        .paragraphStyle: style
    ]
    let attr = NSAttributedString(string: text, attributes: attrs)
    if let maxWidth = maxWidth {
        let bounds = attr.boundingRect(
            with: NSSize(width: maxWidth, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let rect = NSRect(x: pt.x, y: pt.y, width: maxWidth, height: ceil(bounds.height) + 8)
        attr.draw(in: rect)
        return NSSize(width: maxWidth, height: ceil(bounds.height))
    } else {
        let sz = attr.size()
        var drawPt = pt
        if align == .center { drawPt.x -= sz.width / 2 }
        else if align == .right { drawPt.x -= sz.width }
        attr.draw(at: drawPt)
        return sz
    }
}

func drawGhost(_ ctx: CGContext, center: CGPoint, size: CGFloat, glow: Bool = false) {
    ctx.saveGState()
    if glow {
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: cPink.withAlphaComponent(0.45).cgColor)
    } else {
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: cInk.withAlphaComponent(0.20).cgColor)
    }
    // Draw upright in flipped context
    let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(ghostCG, in: CGRect(x: 0, y: 0, width: size, height: size))
    ctx.restoreGState()
}

func drawSymbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor, center: CGPoint) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    let s = img.size
    img.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

func drawWordmark(at pt: CGPoint, size: CGFloat) {
    let f = roundedFont(size, .heavy)
    let talkSz = drawString("Talk", font: f, color: cInk, at: pt, kern: -size * 0.03)
    // Gradient "Type"
    let typeAttr = NSAttributedString(string: "Type", attributes: [
        .font: f,
        .foregroundColor: cPinkDeep,
        .kern: -size * 0.03
    ])
    let typeRect = NSRect(x: pt.x + talkSz.width - 2, y: pt.y, width: typeAttr.size().width + 8, height: typeAttr.size().height + 4)
    // Render gradient masked by glyph alpha
    let w = Int(ceil(typeRect.width))
    let h = Int(ceil(typeRect.height))
    let maskCtx = CGContext(
        data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    maskCtx.translateBy(x: 0, y: CGFloat(h))
    maskCtx.scaleBy(x: 1, y: -1)
    let prev = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: maskCtx, flipped: true)
    NSAttributedString(string: "Type", attributes: [
        .font: f, .foregroundColor: cInk, .kern: -size * 0.03
    ]).draw(at: .zero)
    NSGraphicsContext.current = prev

    if let alphaMask = maskCtx.makeImage(), let mainCtx = NSGraphicsContext.current?.cgContext {
        mainCtx.saveGState()
        // Clip in unflipped image space for the subrect
        mainCtx.translateBy(x: typeRect.minX, y: typeRect.maxY)
        mainCtx.scaleBy(x: 1, y: -1)
        mainCtx.clip(to: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)), mask: alphaMask)
        let grad = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            colors: [cPink.cgColor, cPeach.cgColor] as CFArray,
            locations: [0.0, 1.0]
        )!
        mainCtx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: CGFloat(w), y: CGFloat(h)), options: [])
        mainCtx.restoreGState()
    }
}

func drawKicker(_ ctx: CGContext, text: String, at pt: CGPoint) {
    let pillFont = roundedFont(22, .bold)
    let label = text.uppercased()
    let attr = NSAttributedString(string: label, attributes: [.font: pillFont, .kern: 3.2])
    let w = attr.size().width + 58
    let rect = CGRect(x: pt.x, y: pt.y, width: w, height: 48)
    drawBox(ctx, rect, radius: 24, fill: cPillCream, stroke: cBorder, lineWidth: 2, shadowOpacity: 0.05, shadowBlur: 12, shadowY: 4)
    let dotRect = CGRect(x: pt.x + 20, y: pt.y + 17, width: 14, height: 14)
    drawBox(ctx, dotRect, radius: 7, gradient: [cPink, cPeach], angle: 0, stroke: nil, lineWidth: 0)
    drawString(label, font: pillFont, color: cInkSoft, at: CGPoint(x: pt.x + 44, y: pt.y + 10), kern: 3.2)
}

func drawKeycap(_ ctx: CGContext, _ label: String, at pt: CGPoint, height: CGFloat = 54) -> CGFloat {
    let f = monoFont(height * 0.44, .bold)
    let sz = NSAttributedString(string: label, attributes: [.font: f]).size()
    let w = max(height, sz.width + 34)
    let shadowRect = CGRect(x: pt.x, y: pt.y + 4, width: w, height: height)
    drawBox(ctx, shadowRect, radius: 14, fill: cInk.withAlphaComponent(0.16), stroke: nil, lineWidth: 0)
    let rect = CGRect(x: pt.x, y: pt.y, width: w, height: height)
    drawBox(ctx, rect, radius: 14, fill: cPillCream, stroke: cBorderStrong, lineWidth: 2.5)
    drawString(label, font: f, color: cInk, at: CGPoint(x: rect.midX, y: pt.y + (height - sz.height) / 2 - 1), align: .center)
    return w
}

func drawPopoverChrome(
    _ ctx: CGContext,
    origin: CGPoint,
    scale: CGFloat = 2.15,
    selectedTab: Int = 0
) -> CGRect {
    let pw = 346 * scale
    let ph = 440 * scale
    let rect = CGRect(x: origin.x, y: origin.y, width: pw, height: ph)

    // Popover top pointer caret
    let caretSize = 26 * (scale / 2.0)
    let caret = NSBezierPath()
    caret.move(to: NSPoint(x: rect.midX - caretSize, y: rect.minY + 2))
    caret.line(to: NSPoint(x: rect.midX, y: rect.minY - caretSize * 0.85))
    caret.line(to: NSPoint(x: rect.midX + caretSize, y: rect.minY + 2))
    caret.close()

    drawBox(
        ctx, rect, radius: 26 * scale,
        gradient: [cPopoverLit, cCanvasMid, cPopoverMid], angle: 90,
        stroke: cBorderStrong, lineWidth: 3,
        shadowOpacity: 0.18, shadowBlur: 64, shadowY: 28
    )
    cPopoverLit.setFill()
    caret.fill()
    cBorderStrong.setStroke()
    caret.lineWidth = 2.5
    caret.stroke()

    // Header: Wordmark + Tabs (Live | History | About)
    let pad = 18 * scale
    drawWordmark(at: CGPoint(x: rect.minX + pad, y: rect.minY + pad - 2), size: 25 * scale)

    let tabTrackW = 166 * scale
    let tabTrackH = 26 * scale
    let tabTrack = CGRect(x: rect.maxX - pad - tabTrackW, y: rect.minY + pad + 4 * scale, width: tabTrackW, height: tabTrackH)
    drawBox(ctx, tabTrack, radius: tabTrackH / 2, fill: cInk.withAlphaComponent(0.06), stroke: nil, lineWidth: 0)

    let titles = ["Live", "History", "About"]
    let segW = (tabTrackW - 8) / 3
    for i in 0..<3 {
        let segRect = CGRect(x: tabTrack.minX + 4 + CGFloat(i) * segW, y: tabTrack.minY + 4, width: segW, height: tabTrackH - 8)
        if i == selectedTab {
            drawBox(ctx, segRect, radius: (tabTrackH - 8) / 2, fill: cCardInner, stroke: cBorder, lineWidth: 1.5, shadowOpacity: 0.08, shadowBlur: 8, shadowY: 2)
        }
        let tf = roundedFont(10.5 * scale, .bold)
        let tc = (i == selectedTab) ? cInk : cInkMute
        drawString(titles[i], font: tf, color: tc, at: CGPoint(x: segRect.midX, y: segRect.minY + 3.5 * scale), align: .center)
    }

    return rect
}

// ============================================================================
// SLIDE 1: Hold ⌃⌥ Space. Speak. Paste Anywhere.
// ============================================================================
func renderSlide1() {
    let ctx = makeCanvas()
    fillBackground(ctx, glowCenter: CGPoint(x: 1960, y: 780))

    // Left Story Column
    let leftX: CGFloat = 180
    drawKicker(ctx, text: "Menu Bar Voice to Text", at: CGPoint(x: leftX, y: 210))

    drawString(
        "Say it messy.\nGet it clean.",
        font: roundedFont(118, .heavy),
        color: cInk,
        at: CGPoint(x: leftX, y: 300),
        kern: -4.2,
        maxWidth: 1120,
        lineSpacing: 2
    )

    drawString(
        "Hold ⌃⌥ Space in any Mac app, speak naturally, and release. Clean, punctuated text lands on the clipboard — ready for ⌘V in Notes, Mail, Slack, or Terminal.",
        font: roundedFont(36, .medium),
        color: cInkSoft,
        at: CGPoint(x: leftX, y: 615),
        maxWidth: 1040,
        lineSpacing: 12
    )

    // Tactile Shortcut Row
    var kx = leftX
    let ky: CGFloat = 880
    kx += drawKeycap(ctx, "⌃ Control", at: CGPoint(x: kx, y: ky), height: 64) + 14
    kx += drawKeycap(ctx, "⌥ Option", at: CGPoint(x: kx, y: ky), height: 64) + 14
    kx += drawKeycap(ctx, "Space", at: CGPoint(x: kx, y: ky), height: 64) + 26
    drawString("or click the ghost in the menu bar", font: roundedFont(28, .semibold), color: cInkMute, at: CGPoint(x: kx, y: ky + 14))

    // 3 Crisp Feature Pills
    let bullets = [
        ("lock.shield.fill", "On-device Apple Neural Engine by default"),
        ("doc.on.clipboard.fill", "Instant clipboard copy + 50-take local history"),
        ("globe", "Native English & Español · Escape cancels mid-take")
    ]
    for (idx, item) in bullets.enumerated() {
        let by = 1020 + CGFloat(idx) * 92
        let rowRect = CGRect(x: leftX, y: by, width: 960, height: 74)
        drawBox(ctx, rowRect, radius: 22, fill: cPopoverMid.withAlphaComponent(0.92), stroke: cBorder, lineWidth: 2, shadowOpacity: 0.05, shadowBlur: 16, shadowY: 6)
        drawSymbol(item.0, size: 26, weight: .bold, color: cPinkDeep, center: CGPoint(x: leftX + 42, y: by + 37))
        drawString(item.1, font: roundedFont(27, .semibold), color: cInk, at: CGPoint(x: leftX + 80, y: by + 20))
    }

    // Right Stage: macOS Menu Bar Strip + Crisp Popover + Floating Live HUD
    let scale: CGFloat = 2.08
    let popOrigin = CGPoint(x: 1620, y: 255)
    let menuStrip = CGRect(x: 1480, y: 145, width: 1000, height: 66)
    drawBox(ctx, menuStrip, radius: 20, fill: cPopoverLit.withAlphaComponent(0.95), stroke: cBorder, lineWidth: 2, shadowOpacity: 0.08, shadowBlur: 20, shadowY: 6)
    drawString("Notes    File    Edit    Format    View", font: roundedFont(23, .semibold), color: cInkSoft, at: CGPoint(x: menuStrip.minX + 32, y: menuStrip.minY + 18))

    // Highlighted menu bar ghost icon right above popover pointer
    let mbHighlight = CGRect(x: popOrigin.x + (346 * scale)/2 - 34, y: menuStrip.minY + 9, width: 68, height: 48)
    drawBox(ctx, mbHighlight, radius: 12, fill: cPink.withAlphaComponent(0.22), stroke: cPink.withAlphaComponent(0.45), lineWidth: 2)
    if let mb = menubarGhostImg, let mbCG = mb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.saveGState()
        ctx.translateBy(x: mbHighlight.midX - 18, y: mbHighlight.midY + 18)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(mbCG, in: CGRect(x: 0, y: 0, width: 36, height: 36))
        ctx.restoreGState()
    }
    drawString("Tue 9:41 AM", font: roundedFont(23, .semibold), color: cInk, at: CGPoint(x: menuStrip.maxX - 32, y: menuStrip.minY + 18), align: .right)

    let pop = drawPopoverChrome(ctx, origin: popOrigin, scale: scale, selectedTab: 0)
    let pad = 18 * scale

    // Transcript Card inside Popover
    let tCard = CGRect(x: pop.minX + pad, y: pop.minY + 62 * scale, width: pop.width - pad * 2, height: 146 * scale)
    drawBox(ctx, tCard, radius: 20 * scale, fill: cCardInner, stroke: cBorderStrong, lineWidth: 3.5, shadowOpacity: 0.06, shadowBlur: 18, shadowY: 6)

    let sampleTake = "Morning team, ship the macOS release notes before noon, keep the onboarding calm, and bring the good espresso beans."
    drawString(
        sampleTake,
        font: monoFont(13.2 * scale, .medium),
        color: cInk,
        at: CGPoint(x: tCard.minX + 14 * scale, y: tCard.minY + 14 * scale),
        maxWidth: tCard.width - 28 * scale,
        lineSpacing: 6
    )

    drawString("19 words", font: monoFont(10 * scale, .semibold), color: cInkMute, at: CGPoint(x: tCard.minX + 14 * scale, y: tCard.maxY - 22 * scale))
    let copyBtn = CGRect(x: tCard.maxX - 84 * scale, y: tCard.maxY - 27 * scale, width: 72 * scale, height: 20 * scale)
    drawBox(ctx, copyBtn, radius: 10 * scale, fill: cPink.withAlphaComponent(0.24), stroke: cPink.withAlphaComponent(0.45), lineWidth: 1.5)
    drawString("Copied!", font: roundedFont(10 * scale, .bold), color: cPinkDeep, at: CGPoint(x: copyBtn.midX, y: copyBtn.minY + 3.5 * scale), align: .center)

    // Open-eyed Ghost Mascot
    drawGhost(ctx, center: CGPoint(x: pop.midX, y: tCard.maxY + 76 * scale), size: 118 * scale, glow: true)

    // MAS-true Status Line
    drawString(
        "Click ghost or hold ⌃⌥ Space",
        font: roundedFont(12.2 * scale, .semibold),
        color: cInkSoft,
        at: CGPoint(x: pop.midX, y: tCard.maxY + 145 * scale),
        align: .center
    )

    // Footer Language + Offline Engine Bar
    let footY = pop.maxY - 38 * scale
    let langTrack = CGRect(x: pop.minX + pad, y: footY, width: 78 * scale, height: 22 * scale)
    drawBox(ctx, langTrack, radius: 11 * scale, fill: cInk.withAlphaComponent(0.07), stroke: nil, lineWidth: 0)
    let enPill = CGRect(x: langTrack.minX + 3, y: langTrack.minY + 3, width: 36 * scale, height: 22 * scale - 6)
    drawBox(ctx, enPill, radius: (22 * scale - 6)/2, fill: cCardInner, stroke: cBorder, lineWidth: 1)
    drawString("EN", font: roundedFont(9.8 * scale, .bold), color: cInk, at: CGPoint(x: enPill.midX, y: enPill.minY + 2.5 * scale), align: .center)
    drawString("ES", font: roundedFont(9.8 * scale, .bold), color: cInkMute, at: CGPoint(x: langTrack.maxX - 19 * scale, y: enPill.minY + 2.5 * scale), align: .center)

    let engPill = CGRect(x: pop.maxX - pad - 96 * scale, y: footY, width: 96 * scale, height: 22 * scale)
    drawBox(ctx, engPill, radius: 11 * scale, fill: cCardInner, stroke: cBorder, lineWidth: 1.5)
    drawString("Offline · EN", font: roundedFont(9.8 * scale, .bold), color: cInkSoft, at: CGPoint(x: engPill.midX, y: engPill.minY + 4 * scale), align: .center)

    // Floating Live HUD Capsule overlapping bottom-left of stage (MAS clipboard confirmation!)
    let hudRect = CGRect(x: 1380, y: 1275, width: 1160, height: 146)
    drawBox(
        ctx, hudRect, radius: 46,
        fill: cPopoverLit.withAlphaComponent(0.97),
        stroke: cPink, lineWidth: 8,
        shadowOpacity: 0.20, shadowBlur: 48, shadowY: 20
    )
    let hudOrb = CGRect(x: hudRect.minX + 28, y: hudRect.midY - 44, width: 88, height: 88)
    drawBox(ctx, hudOrb, radius: 44, fill: cPink.withAlphaComponent(0.20), stroke: nil, lineWidth: 0)
    drawGhost(ctx, center: CGPoint(x: hudOrb.midX, y: hudOrb.midY), size: 68, glow: false)

    drawString(
        "Copied to clipboard — Press ⌘V to paste!",
        font: roundedFont(33, .bold),
        color: cInk,
        at: CGPoint(x: hudOrb.maxX + 28, y: hudRect.midY - 21)
    )
    drawSymbol("checkmark.circle.fill", size: 42, weight: .bold, color: cPinkDeep, center: CGPoint(x: hudRect.maxX - 66, y: hudRect.midY))

    saveCanvas(ctx, to: "screenshots/appstore/01-dictate-anywhere-2880x1800.png")
    saveCanvas(ctx, to: "screenshots/appstore-2880x1800.png")
}

// ============================================================================
// SLIDE 2: 50-Take Local History & Custom Vocabulary
// ============================================================================
func renderSlide2() {
    let ctx = makeCanvas()
    fillBackground(ctx, glowCenter: CGPoint(x: 920, y: 860))

    // Left Stage: Popover open to History Tab
    let scale: CGFloat = 2.12
    let pop = drawPopoverChrome(ctx, origin: CGPoint(x: 220, y: 210), scale: scale, selectedTab: 1)
    let pad = 18 * scale

    let subY = pop.minY + 60 * scale
    drawString("14 takes", font: roundedFont(11 * scale, .semibold), color: cInkMute, at: CGPoint(x: pop.minX + pad + 4, y: subY))
    let sortPill = CGRect(x: pop.maxX - pad - 68 * scale, y: subY - 3, width: 68 * scale, height: 19 * scale)
    drawBox(ctx, sortPill, radius: 9.5 * scale, fill: cCardInner, stroke: cBorder, lineWidth: 1.5)
    drawString("↓ Newest", font: roundedFont(9.5 * scale, .bold), color: cInkSoft, at: CGPoint(x: sortPill.midX, y: sortPill.minY + 3 * scale), align: .center)

    let records: [(String, String, Bool)] = [
        ("Today, 9:41 AM", "Ship the macOS release notes before noon and keep the onboarding calm.", true),
        ("Today, 9:18 AM", "El resumen del taller ya está listo para enviar al equipo de diseño.", false),
        ("Yesterday, 6:05 PM", "TalkType keeps the last fifty takes right in the menu bar — zero cloud sync.", false)
    ]

    var cardY = subY + 26 * scale
    for rec in records {
        let h: CGFloat = 96 * scale
        let rCard = CGRect(x: pop.minX + pad, y: cardY, width: pop.width - pad * 2, height: h)
        drawBox(ctx, rCard, radius: 14 * scale, fill: cCardInner, stroke: cBorder, lineWidth: 2, shadowOpacity: 0.04, shadowBlur: 12, shadowY: 4)
        drawString(rec.0, font: roundedFont(10.5 * scale, .medium), color: cInkMute, at: CGPoint(x: rCard.minX + 12 * scale, y: rCard.minY + 11 * scale))

        let cBtn = CGRect(x: rCard.maxX - 70 * scale, y: rCard.minY + 9 * scale, width: 58 * scale, height: 18 * scale)
        drawBox(ctx, cBtn, radius: 9 * scale, fill: cPink.withAlphaComponent(rec.2 ? 0.28 : 0.16), stroke: nil, lineWidth: 0)
        drawString(rec.2 ? "Copied!" : "Copy", font: roundedFont(9.5 * scale, .bold), color: cPinkDeep, at: CGPoint(x: cBtn.midX, y: cBtn.minY + 3 * scale), align: .center)

        drawString(
            rec.1,
            font: monoFont(11.6 * scale, .medium),
            color: cInk,
            at: CGPoint(x: rCard.minX + 12 * scale, y: rCard.minY + 34 * scale),
            maxWidth: rCard.width - 24 * scale,
            lineSpacing: 5
        )
        cardY += h + 10 * scale
    }

    drawString("Clear History…", font: roundedFont(10.5 * scale, .semibold), color: cInkMute, at: CGPoint(x: pop.minX + pad + 6, y: pop.maxY - 30 * scale))

    // Right Column: Copy + Custom Vocabulary Showcase Card
    let rightX: CGFloat = 1140
    drawKicker(ctx, text: "Local Memory & Custom Words", at: CGPoint(x: rightX, y: 215))

    drawString(
        "Every take saved.\nEvery name spelled right.",
        font: roundedFont(102, .heavy),
        color: cInk,
        at: CGPoint(x: rightX, y: 305),
        kern: -3.5,
        maxWidth: 1540,
        lineSpacing: 4
    )

    drawString(
        "Recent transcripts live locally in the menu bar for instant recall or plain-text export. Add custom vocabulary and phonetic rules so tricky names, brands, and jargon land cleanly every time.",
        font: roundedFont(35, .medium),
        color: cInkSoft,
        at: CGPoint(x: rightX, y: 590),
        maxWidth: 1460,
        lineSpacing: 12
    )

    // Custom Vocabulary Visual Card
    let vocabCard = CGRect(x: rightX, y: 830, width: 1480, height: 420)
    drawBox(ctx, vocabCard, radius: 34, gradient: [cPopoverLit, cPopoverMid], angle: 90, stroke: cBorderStrong, lineWidth: 3, shadowOpacity: 0.12, shadowBlur: 44, shadowY: 18)
    drawSymbol("character.book.closed.fill", size: 34, weight: .bold, color: cPinkDeep, center: CGPoint(x: vocabCard.minX + 58, y: vocabCard.minY + 58))
    drawString("Custom Vocabulary & Phonetic Rules", font: roundedFont(32, .heavy), color: cInk, at: CGPoint(x: vocabCard.minX + 94, y: vocabCard.minY + 38))

    let rules = [
        ("doctype  →  TalkType", "Automatic phonetic replacement"),
        ("pibulus, Melbourne, SwiftUI", "Priority speech recognition hints"),
        ("English  ·  Español", "Instant bilingual switching, zero drift")
    ]
    for (idx, r) in rules.enumerated() {
        let ry = vocabCard.minY + 112 + CGFloat(idx) * 94
        let pill = CGRect(x: vocabCard.minX + 42, y: ry, width: vocabCard.width - 84, height: 76)
        drawBox(ctx, pill, radius: 20, fill: cCardInner, stroke: cBorder, lineWidth: 2)
        drawString(r.0, font: monoFont(26, .bold), color: cInk, at: CGPoint(x: pill.minX + 26, y: pill.minY + 20))
        drawString(r.1, font: roundedFont(24, .semibold), color: cInkMute, at: CGPoint(x: pill.maxX - 26, y: pill.minY + 22), align: .right)
    }

    // Export & Zero-Cloud Footer Badges
    let badges = ["Up to 50 local takes", "Export All to .txt", "One-click Clear History"]
    var bx = rightX
    for b in badges {
        let f = roundedFont(25, .bold)
        let w = NSAttributedString(string: b, attributes: [.font: f]).size().width + 52
        let br = CGRect(x: bx, y: 1300, width: w, height: 60)
        drawBox(ctx, br, radius: 30, fill: cPillCream, stroke: cBorderStrong, lineWidth: 2)
        drawString(b, font: f, color: cInkSoft, at: CGPoint(x: br.midX, y: br.minY + 14), align: .center)
        bx += w + 20
    }

    saveCanvas(ctx, to: "screenshots/appstore/02-history-and-vocabulary-2880x1800.png")
}

// ============================================================================
// SLIDE 3: Private On-Device by Default · Three Engines, One Ghost
// ============================================================================
func renderSlide3() {
    let ctx = makeCanvas()
    fillBackground(ctx, glowCenter: CGPoint(x: 1440, y: 520))

    // Centered Hero Header
    drawGhost(ctx, center: CGPoint(x: 1440, y: 225), size: 176, glow: true)

    drawString(
        "Audio stays on the Mac.",
        font: roundedFont(108, .heavy),
        color: cInk,
        at: CGPoint(x: 1440, y: 345),
        align: .center,
        kern: -3.8
    )

    drawString(
        "Runs offline on the Apple Neural Engine out of the box — no account, no server, no telemetry.\nAdd personal Keychain keys any time for cloud streaming or prose polish.",
        font: roundedFont(35, .medium),
        color: cInkSoft,
        at: CGPoint(x: 240, y: 495),
        align: .center,
        maxWidth: 2400,
        lineSpacing: 10
    )

    // 3 Engine Architecture Cards
    struct EngineSpec {
        let badge: String
        let badgeColor: NSColor
        let symbol: String
        let title: String
        let subtitle: String
        let detail: String
        let footer: String
        let featured: Bool
    }

    let cards: [EngineSpec] = [
        EngineSpec(
            badge: "DEFAULT · OFFLINE",
            badgeColor: cMint,
            symbol: "cpu.fill",
            title: "Apple On-Device",
            subtitle: "100% local Neural Engine",
            detail: "Transcribes directly on the Mac with zero network traffic. Works on a flight, in a studio, or completely offline.",
            footer: "No key required · Zero uploads",
            featured: true
        ),
        EngineSpec(
            badge: "OPTIONAL · OWN KEY",
            badgeColor: cPinkDeep,
            symbol: "bolt.fill",
            title: "Deepgram Nova-3",
            subtitle: "Real-time cloud streaming",
            detail: "Connect a personal Deepgram API key for ultra-long takes, noisy rooms, and multi-speaker conversation labels.",
            footer: "macOS Keychain · Model training opted out",
            featured: false
        ),
        EngineSpec(
            badge: "OPTIONAL · OWN KEY",
            badgeColor: cInkSoft,
            symbol: "wand.and.stars",
            title: "Gemini Polish",
            subtitle: "Clean prose pass",
            detail: "Connect a personal Gemini API key to turn rough spoken thoughts and mid-sentence restarts into crisp paragraphs.",
            footer: "macOS Keychain · Direct HTTPS",
            featured: false
        )
    ]

    let cardW: CGFloat = 780
    let cardH: CGFloat = 760
    let gap: CGFloat = 60
    let startX = (CGFloat(W) - (cardW * 3 + gap * 2)) / 2
    let cardY: CGFloat = 695

    for (idx, c) in cards.enumerated() {
        let cx = startX + CGFloat(idx) * (cardW + gap)
        let rect = CGRect(x: cx, y: cardY, width: cardW, height: cardH)
        drawBox(
            ctx, rect, radius: 38,
            gradient: c.featured ? [cPopoverLit, cCardInner] : [cPopoverLit, cPopoverMid],
            angle: 90,
            stroke: c.featured ? cPink : cBorderStrong,
            lineWidth: c.featured ? 4.5 : 3,
            shadowOpacity: c.featured ? 0.16 : 0.10,
            shadowBlur: 48, shadowY: 22
        )

        // Badge pill
        let bf = roundedFont(20, .heavy)
        let bw = NSAttributedString(string: c.badge, attributes: [.font: bf, .kern: 2.2]).size().width + 44
        let bRect = CGRect(x: rect.minX + 46, y: rect.minY + 46, width: bw, height: 44)
        drawBox(ctx, bRect, radius: 22, fill: c.badgeColor.withAlphaComponent(0.14), stroke: c.badgeColor.withAlphaComponent(0.38), lineWidth: 2)
        drawString(c.badge, font: bf, color: c.badgeColor, at: CGPoint(x: bRect.midX, y: bRect.minY + 9), align: .center, kern: 2.2)

        // Icon tile
        let iconTile = CGRect(x: rect.minX + 46, y: rect.minY + 126, width: 92, height: 92)
        drawBox(ctx, iconTile, radius: 26, fill: cPink.withAlphaComponent(0.16), stroke: cPink.withAlphaComponent(0.35), lineWidth: 2)
        drawSymbol(c.symbol, size: 40, weight: .bold, color: cPinkDeep, center: CGPoint(x: iconTile.midX, y: iconTile.midY))

        drawString(c.title, font: roundedFont(46, .heavy), color: cInk, at: CGPoint(x: rect.minX + 46, y: rect.minY + 252), kern: -1.2)
        drawString(c.subtitle, font: roundedFont(28, .bold), color: cPinkDeep, at: CGPoint(x: rect.minX + 46, y: rect.minY + 316))

        drawString(
            c.detail,
            font: roundedFont(28, .medium),
            color: cInkSoft,
            at: CGPoint(x: rect.minX + 46, y: rect.minY + 382),
            maxWidth: cardW - 92,
            lineSpacing: 10
        )

        // Footer divider + Keychain/offline guarantee
        let div = CGRect(x: rect.minX + 46, y: rect.maxY - 110, width: cardW - 92, height: 2)
        cBorder.setFill()
        NSBezierPath(rect: div).fill()

        drawSymbol(c.featured ? "checkmark.shield.fill" : "key.fill", size: 22, weight: .bold, color: c.featured ? cMint : cInkMute, center: CGPoint(x: rect.minX + 62, y: rect.maxY - 60))
        drawString(c.footer, font: roundedFont(24, .bold), color: cInkSoft, at: CGPoint(x: rect.minX + 92, y: rect.maxY - 76))
    }

    // Bottom Trust Strip
    drawString(
        "App Sandbox  ·  macOS Keychain Security  ·  Zero Analytics  ·  Universal Apple Silicon & Intel",
        font: roundedFont(27, .bold),
        color: cInkMute,
        at: CGPoint(x: 1440, y: 1555),
        align: .center,
        kern: 0.5
    )

    saveCanvas(ctx, to: "screenshots/appstore/03-private-on-device-2880x1800.png")
}

renderSlide1()
renderSlide2()
renderSlide3()
