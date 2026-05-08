// Generates social-preview.png — a 1280×640 banner using Murmur's palette,
// with the cassette centered above a "Murmur" wordmark and tagline.
// Used as GitHub's repository "Social preview" image.
//
//   swift make-social-card.swift

import AppKit
import Foundation

let outputPath = "social-preview.png"
let W: CGFloat = 1280
let H: CGFloat = 640

let bgColor    = NSColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
let mainColor  = NSColor(red: 0.96, green: 0.65, blue: 0.45, alpha: 1)
let dimColor   = NSColor(red: 0.96, green: 0.65, blue: 0.45, alpha: 0.45)
let creamColor = NSColor(red: 0.91, green: 0.87, blue: 0.78, alpha: 1)
let creamDim   = NSColor(red: 0.91, green: 0.87, blue: 0.78, alpha: 0.55)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W), pixelsHigh: Int(H),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
), let gc = NSGraphicsContext(bitmapImageRep: rep) else {
    fatalError("Bitmap context init failed")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gc

// MARK: Background
bgColor.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// MARK: Cassette (centered, sits in upper half)
// NSGraphicsContext uses a bottom-left origin, so y grows upward.
let bodyW: CGFloat = 720
let bodyH: CGFloat = bodyW / 2.4
let body = NSRect(
    x: (W - bodyW) / 2,
    y: H * 0.56 - bodyH / 2,
    width:  bodyW,
    height: bodyH
)

let bodyPath = NSBezierPath(roundedRect: body,
                            xRadius: bodyH * 0.13,
                            yRadius: bodyH * 0.13)
bodyPath.lineWidth = 6
mainColor.setStroke()
bodyPath.stroke()

// Label area + ruling lines (in upper portion of cassette body)
let labelRect = NSRect(
    x: body.minX + body.width * 0.06,
    y: body.maxY - body.height * 0.09 - body.height * 0.30,
    width:  body.width * 0.88,
    height: body.height * 0.30
)
let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 8, yRadius: 8)
labelPath.lineWidth = 4
dimColor.setStroke()
labelPath.stroke()

func drawLine(from p1: NSPoint, to p2: NSPoint, color: NSColor, width: CGFloat) {
    let p = NSBezierPath()
    p.move(to: p1)
    p.line(to: p2)
    p.lineWidth = width
    color.setStroke()
    p.stroke()
}

let line1Y = labelRect.maxY - labelRect.height * 0.42
let line2Y = labelRect.maxY - labelRect.height * 0.74
drawLine(from: NSPoint(x: labelRect.minX + 18, y: line1Y),
         to:   NSPoint(x: labelRect.maxX - 18, y: line1Y),
         color: dimColor, width: 2.5)
drawLine(from: NSPoint(x: labelRect.minX + 18, y: line2Y),
         to:   NSPoint(x: labelRect.maxX - 90, y: line2Y),
         color: dimColor, width: 2.5)

// MARK: Reels
let reelRadius = body.height * 0.22
let reelY      = body.maxY - body.height * 0.66
let reelXLeft  = body.minX + body.width * 0.24
let reelXRight = body.minX + body.width * 0.76

drawLine(from: NSPoint(x: reelXLeft,  y: reelY + reelRadius + 9),
         to:   NSPoint(x: reelXRight, y: reelY + reelRadius + 9),
         color: dimColor, width: 3)

func drawReel(at center: NSPoint, radius: CGFloat) {
    let outer = NSBezierPath(ovalIn: NSRect(x: center.x - radius,
                                            y: center.y - radius,
                                            width: radius * 2,
                                            height: radius * 2))
    outer.lineWidth = 5
    mainColor.setStroke()
    outer.stroke()

    let hubR = radius * 0.34
    let hub = NSBezierPath(ovalIn: NSRect(x: center.x - hubR,
                                          y: center.y - hubR,
                                          width: hubR * 2,
                                          height: hubR * 2))
    hub.lineWidth = 4
    hub.stroke()

    for i in 0..<6 {
        let theta = Double(i) * (2 * .pi / 6)
        let cosT = CGFloat(cos(theta))
        let sinT = CGFloat(sin(theta))
        drawLine(from: NSPoint(x: center.x + cosT * hubR,
                               y: center.y + sinT * hubR),
                 to:   NSPoint(x: center.x + cosT * (radius - 4),
                               y: center.y + sinT * (radius - 4)),
                 color: mainColor, width: 4)
    }
}

drawReel(at: NSPoint(x: reelXLeft,  y: reelY), radius: reelRadius)
drawReel(at: NSPoint(x: reelXRight, y: reelY), radius: reelRadius)

// MARK: Wordmark + tagline
let title = NSAttributedString(string: "Murmur", attributes: [
    .font: NSFont.monospacedSystemFont(ofSize: 88, weight: .medium),
    .foregroundColor: creamColor
])
let titleSize = title.size()
title.draw(at: NSPoint(x: (W - titleSize.width) / 2, y: H * 0.13))

let tagline = NSAttributedString(
    string: "macOS menu-bar YouTube audio with floating chromeless video",
    attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .regular),
        .foregroundColor: creamDim
    ]
)
let taglineSize = tagline.size()
tagline.draw(at: NSPoint(x: (W - taglineSize.width) / 2, y: H * 0.06))

NSGraphicsContext.restoreGraphicsState()

// MARK: Save
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encoding failed")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath) (\(Int(W))×\(Int(H)))")
