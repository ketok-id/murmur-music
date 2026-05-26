// Generates icon.png — a 1024×1024 coral squircle with a dark serif "M".
// Matches the brand mark on https://murmur.ketok.id.
// Run from the project root:  swift make-icon.swift
// Then ./build-app.sh will pick up the new icon when assembling the .app.

import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Foundation

let outputPath = "icon.png"
let size: CGFloat = 1024

// Sampled from the site's app icon.
let coralColor = CGColor(red: 0.906, green: 0.459, blue: 0.337, alpha: 1) // #E77556
let markColor  = CGColor(red: 0.094, green: 0.039, blue: 0.020, alpha: 1) // #180A05

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

// MARK: Background squircle (≈ macOS app icon mask)
let cornerRadius = size * 0.225
let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
                    cornerWidth: cornerRadius,
                    cornerHeight: cornerRadius,
                    transform: nil)
ctx.setFillColor(coralColor)
ctx.addPath(bgPath)
ctx.fillPath()

// MARK: Serif "M"
// Prefer a high-contrast serif (Times) to match the brand mark; fall back to
// the system serif design, then plain bold system font.
func boldSerifFont(_ pointSize: CGFloat) -> CTFont {
    for name in ["TimesNewRomanPS-BoldMT", "Times New Roman Bold", "Georgia-Bold"] {
        if let f = NSFont(name: name, size: pointSize) { return f as CTFont }
    }
    if #available(macOS 10.15, *),
       let d = NSFont.boldSystemFont(ofSize: pointSize).fontDescriptor.withDesign(.serif),
       let f = NSFont(descriptor: d, size: pointSize) {
        return f as CTFont
    }
    return NSFont.boldSystemFont(ofSize: pointSize) as CTFont
}

let font = boldSerifFont(size * 0.64)
let attrs = [
    kCTFontAttributeName: font,
    kCTForegroundColorAttributeName: markColor,
] as CFDictionary
let astr = CFAttributedStringCreate(nil, "M" as CFString, attrs)!
let line = CTLineCreateWithAttributedString(astr)

// Center on the glyph's ink bounds so optical weight sits dead-center.
let inkBounds = CTLineGetImageBounds(line, ctx)
let tx = (size - inkBounds.width)  / 2 - inkBounds.minX
let ty = (size - inkBounds.height) / 2 - inkBounds.minY
ctx.textPosition = CGPoint(x: tx, y: ty)
CTLineDraw(line, ctx)

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
