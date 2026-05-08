// Generates icon.png — a 1024×1024 cassette tape on Murmur's palette.
// Run from the project root:  swift make-icon.swift
// Then ./build-app.sh will pick up the new icon when assembling the .app.

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outputPath = "icon.png"
let size: CGFloat = 1024

// Match ContentView / CassetteTape colors
let bgColor   = CGColor(red: 0.05, green: 0.05, blue: 0.06, alpha: 1)
let mainColor = CGColor(red: 0.96, green: 0.65, blue: 0.45, alpha: 1)
let dimColor  = CGColor(red: 0.96, green: 0.65, blue: 0.45, alpha: 0.45)

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width:  Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("CGContext init failed") }

// Use a top-left origin so calculations match SwiftUI Canvas.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// MARK: Background squircle (≈ macOS app icon mask)
let cornerRadius = size * 0.225
let bgRect  = CGRect(x: 0, y: 0, width: size, height: size)
let bgPath  = CGPath(roundedRect: bgRect,
                     cornerWidth: cornerRadius,
                     cornerHeight: cornerRadius,
                     transform: nil)
ctx.setFillColor(bgColor)
ctx.addPath(bgPath)
ctx.fillPath()

// MARK: Cassette body
let pad = size * 0.10
let bodyW = size - 2 * pad
let bodyH = bodyW / 2.2
let body = CGRect(
    x: pad,
    y: (size - bodyH) / 2,
    width:  bodyW,
    height: bodyH
)
ctx.setStrokeColor(mainColor)
ctx.setLineWidth(size * 0.013)
let bodyPath = CGPath(roundedRect: body,
                      cornerWidth:  body.height * 0.13,
                      cornerHeight: body.height * 0.13,
                      transform: nil)
ctx.addPath(bodyPath)
ctx.strokePath()

// MARK: Label area + ruling lines
let labelRect = CGRect(
    x: body.minX + body.width * 0.06,
    y: body.minY + body.height * 0.09,
    width:  body.width * 0.88,
    height: body.height * 0.30
)
ctx.setStrokeColor(dimColor)
ctx.setLineWidth(size * 0.008)
ctx.addPath(CGPath(roundedRect: labelRect,
                   cornerWidth: 12, cornerHeight: 12,
                   transform: nil))
ctx.strokePath()

ctx.setLineWidth(size * 0.005)
let line1Y = labelRect.minY + labelRect.height * 0.42
let line2Y = labelRect.minY + labelRect.height * 0.74
ctx.move(to: CGPoint(x: labelRect.minX + 24, y: line1Y))
ctx.addLine(to: CGPoint(x: labelRect.maxX - 24, y: line1Y))
ctx.strokePath()
ctx.move(to: CGPoint(x: labelRect.minX + 24, y: line2Y))
ctx.addLine(to: CGPoint(x: labelRect.maxX - 120, y: line2Y))
ctx.strokePath()

// MARK: Reels
let reelRadius = body.height * 0.22
let reelY      = body.minY + body.height * 0.66
let reelXLeft  = body.minX + body.width * 0.24
let reelXRight = body.minX + body.width * 0.76

// Tape strand
ctx.setLineWidth(size * 0.006)
ctx.setStrokeColor(dimColor)
ctx.move(to: CGPoint(x: reelXLeft,  y: reelY - reelRadius - 12))
ctx.addLine(to: CGPoint(x: reelXRight, y: reelY - reelRadius - 12))
ctx.strokePath()

ctx.setStrokeColor(mainColor)
for cx in [reelXLeft, reelXRight] {
    let center = CGPoint(x: cx, y: reelY)

    // Outer ring
    ctx.setLineWidth(size * 0.011)
    ctx.strokeEllipse(in: CGRect(x: center.x - reelRadius,
                                 y: center.y - reelRadius,
                                 width:  reelRadius * 2,
                                 height: reelRadius * 2))

    // Hub
    let hubR = reelRadius * 0.34
    ctx.setLineWidth(size * 0.009)
    ctx.strokeEllipse(in: CGRect(x: center.x - hubR,
                                 y: center.y - hubR,
                                 width:  hubR * 2,
                                 height: hubR * 2))

    // Six spokes
    ctx.setLineWidth(size * 0.009)
    for i in 0..<6 {
        let theta = Double(i) * (2 * .pi / 6)
        let cosT = CGFloat(cos(theta))
        let sinT = CGFloat(sin(theta))
        ctx.move(to: CGPoint(
            x: center.x + cosT * hubR,
            y: center.y + sinT * hubR
        ))
        ctx.addLine(to: CGPoint(
            x: center.x + cosT * (reelRadius - 6),
            y: center.y + sinT * (reelRadius - 6)
        ))
        ctx.strokePath()
    }
}

// MARK: Spindle holes (cassette bottom)
let holeY: CGFloat = body.maxY - body.height * 0.10
let holeR: CGFloat = body.height * 0.025
ctx.setFillColor(dimColor)
for cx in [body.minX + body.width * 0.16, body.maxX - body.width * 0.16] {
    ctx.fillEllipse(in: CGRect(x: cx - holeR, y: holeY - holeR,
                               width: holeR * 2, height: holeR * 2))
}

// MARK: Write PNG
guard let cgImg = ctx.makeImage() else { fatalError("makeImage failed") }
let url = URL(fileURLWithPath: outputPath)
guard let dst = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1, nil
) else { fatalError("CGImageDestination init failed") }
CGImageDestinationAddImage(dst, cgImg, nil)
guard CGImageDestinationFinalize(dst) else { fatalError("PNG finalize failed") }

print("Wrote \(outputPath) (\(Int(size))×\(Int(size)))")
