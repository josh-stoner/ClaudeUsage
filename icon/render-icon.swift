#!/usr/bin/env swift
// render-icon.swift — Generate ClaudeUsage app icon master (1024×1024)
// Concept: bold cream "%" glyph + single sweeping purple gauge arc
// Run: swift icon/render-icon.swift
// Output: icon/icon-master-1024.png

import AppKit
import CoreGraphics
import CoreText

let size = 1024
let center = CGFloat(size) / 2

// --- Colors (brand dark-mode palette from Theme.swift) ---
let bgColor       = CGColor(red: 0x11/255.0, green: 0x0A/255.0, blue: 0x0F/255.0, alpha: 1) // #110A0F
let purpleColor   = CGColor(red: 0x8A/255.0, green: 0x75/255.0, blue: 0xD6/255.0, alpha: 1) // #8A75D6
let dimArcColor   = CGColor(red: 1, green: 1, blue: 1, alpha: 0.10)
let glowColor     = CGColor(red: 0x8A/255.0, green: 0x75/255.0, blue: 0xD6/255.0, alpha: 0.18)
let textColor     = CGColor(red: 0xD2/255.0, green: 0xCB/255.0, blue: 0xC7/255.0, alpha: 1)  // #D2CBC7 cream

// --- Canvas setup ---
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: size * 4,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Could not create CGContext") }

// CoreGraphics: (0,0) is bottom-left, Y up
// Flip to top-left origin for text drawing
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// --- Background ---
ctx.setFillColor(bgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// --- Subtle radial purple glow at center ---
let glowRadius = CGFloat(size) * 0.50
if let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [glowColor, CGColor(red: 0x8A/255.0, green: 0x75/255.0, blue: 0xD6/255.0, alpha: 0)] as CFArray,
    locations: [0.0, 1.0]
) {
    ctx.saveGState()
    ctx.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: center, y: center), startRadius: 0,
        endCenter: CGPoint(x: center, y: center), endRadius: glowRadius,
        options: []
    )
    ctx.restoreGState()
}

// --- Gauge arc ---
// Arc layout: 270° total sweep, clockwise from 225° (SW)
// Purple portion: ~75% of sweep = 202.5° → shown as the "active" usage
// Dim portion: remaining 25% = 67.5° → the "available" track
let arcRadius    = CGFloat(size) * 0.370   // ring center radius (37% of canvas)
let arcLineWidth = CGFloat(size) * 0.095   // thick ring (~9.5% of canvas)
let totalSweep   = CGFloat(270).radians    // total arc span
let filledRatio  = CGFloat(0.75)           // 75% filled
let startAngle   = CGFloat(135).radians    // 135° from positive-x axis = SW, going clockwise
let splitAngle   = startAngle + filledRatio * totalSweep
let endAngle     = startAngle + totalSweep

// CoreGraphics angles: 0 = 3-o'clock, positive = counterclockwise
// We want clockwise, so clockwise = true (CW in screen coords after Y-flip = actually CCW in CG)
// After the ctx Y-flip above, "clockwise: false" in CG = visually clockwise on screen.
ctx.setLineCap(.round)
ctx.setLineWidth(arcLineWidth)

// Dim track (full arc, draw first so purple overlays)
ctx.setStrokeColor(dimArcColor)
ctx.addArc(center: CGPoint(x: center, y: center), radius: arcRadius,
           startAngle: startAngle, endAngle: endAngle, clockwise: false)
ctx.strokePath()

// Purple filled portion
ctx.setStrokeColor(purpleColor)
ctx.addArc(center: CGPoint(x: center, y: center), radius: arcRadius,
           startAngle: startAngle, endAngle: splitAngle, clockwise: false)
ctx.strokePath()

// --- "%" glyph ---
// Load Inter ExtraBold from the user's font library
let fontPaths = [
    "\(NSHomeDirectory())/Library/Fonts/Inter-ExtraBold.otf",
    "\(NSHomeDirectory())/Library/Fonts/Inter/Inter-ExtraBold.otf",
    "/Library/Fonts/Inter-ExtraBold.otf",
]
var ctFont: CTFont?
for path in fontPaths {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let cfArray = CTFontManagerCreateFontDescriptorsFromURL(url) else { continue }
    let descs = cfArray as! [CTFontDescriptor]
    if let first = descs.first {
        ctFont = CTFontCreateWithFontDescriptor(first, CGFloat(size) * 0.52, nil)
        break
    }
}
// Fallback to system bold if Inter not found
let font = ctFont ?? CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(size) * 0.52, nil)

let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(cgColor: textColor)!
]
let attrStr = NSAttributedString(string: "%", attributes: attrs)
let line = CTLineCreateWithAttributedString(attrStr)
let textBounds = CTLineGetImageBounds(line, ctx)
let tx = center - textBounds.width / 2 - textBounds.origin.x
let ty = center - textBounds.height / 2 - textBounds.origin.y - CGFloat(size) * 0.028  // optical lift
ctx.textPosition = CGPoint(x: tx, y: ty)
CTLineDraw(line, ctx)

// --- Write PNG ---
guard let cgImage = ctx.makeImage() else { fatalError("Could not create CGImage") }
let rep = NSBitmapImageRep(cgImage: cgImage)
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode PNG")
}
let outputPath = URL(fileURLWithPath: #file)
    .deletingLastPathComponent()
    .appendingPathComponent("icon-master-1024.png")
try! pngData.write(to: outputPath)
print("✓  Wrote \(outputPath.path)")

// --- Degree helper ---
extension CGFloat {
    var radians: CGFloat { self * .pi / 180 }
}
