#!/usr/bin/env swift
// Draws a 1024x1024 app icon for MacCodexApp and saves it as PNG.
//
// Design:
//   - Indigo → teal gradient background, rounded square (macOS Big Sur+ style)
//   - A bold white "C" (Codex) with a small green cursor block in the opening
//     (the cursor is the AI agent doing work)
//
// The script is self-contained: it does NOT depend on any other file in the
// project. Re-run it any time the design changes.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
guard let ctx = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

// ── 1. Rounded-square clip ──────────────────────────────────────────────
let cornerRadius: CGFloat = 225
let bgPath = CGPath(
    roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
    cornerWidth: cornerRadius,
    cornerHeight: cornerRadius,
    transform: nil
)
ctx.addPath(bgPath)
ctx.clip()

// ── 2. Indigo → teal linear gradient ────────────────────────────────────
let bgColors = [
    CGColor(red: 0.118, green: 0.106, blue: 0.294, alpha: 1.0),  // #1E1B4B indigo-950
    CGColor(red: 0.380, green: 0.176, blue: 0.580, alpha: 1.0),  // #612DA0 purple-700
    CGColor(red: 0.055, green: 0.455, blue: 0.565, alpha: 1.0),  // #0E7490 cyan-800
] as CFArray
guard let bgGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: bgColors,
    locations: [0.0, 0.55, 1.0]
) else {
    fputs("Failed to create gradient\n", stderr)
    exit(1)
}
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// ── 3. Subtle top-left highlight (depth) ─────────────────────────────────
ctx.saveGState()
let highlightPath = CGPath(
    ellipseIn: CGRect(x: -200, y: size - 500, width: 700, height: 700),
    transform: nil
)
ctx.addPath(highlightPath)
ctx.clip()
let highlightColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
] as CFArray
if let highlightGradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: highlightColors,
    locations: [0.0, 1.0]
) {
    ctx.drawRadialGradient(
        highlightGradient,
        startCenter: CGPoint(x: 120, y: CGFloat(size) - 120),
        startRadius: 0,
        endCenter: CGPoint(x: 120, y: CGFloat(size) - 120),
        endRadius: 450,
        options: []
    )
}
ctx.restoreGState()

// ── 4. The "C" (a thick ring with an opening on the right) ─────────────
//
// The opening is centered on the positive x-axis (0°), spanning
// `openingDeg` degrees. The C arc is the rest of the ring — the long way
// around through 90°, 180°, 270°.
//
// In CG (y-up), counterclockwise = positive angle direction. To take the
// long way from startRad to endRad, we sweep in the positive direction
// (clockwise=false). To take the long way back on the inner arc, we sweep
// in the negative direction (clockwise=true).
let center = CGPoint(x: CGFloat(size) / 2, y: CGFloat(size) / 2)
let outerR: CGFloat = 340
let innerR: CGFloat = 220
let openingDeg: CGFloat = 80

let startDeg = openingDeg / 2
let endDeg = 360 - openingDeg / 2
let startRad = startDeg * .pi / 180
let endRad = endDeg * .pi / 180

let outerStart = CGPoint(
    x: center.x + outerR * cos(startRad),
    y: center.y + outerR * sin(startRad)
)
let innerStart = CGPoint(
    x: center.x + innerR * cos(startRad),
    y: center.y + innerR * sin(startRad)
)
let innerEnd = CGPoint(
    x: center.x + innerR * cos(endRad),
    y: center.y + innerR * sin(endRad)
)

let cPath = CGMutablePath()
cPath.move(to: outerStart)
// Outer arc: 40° → 320° via 90°/180°/270° (positive sweep, the long way).
cPath.addArc(
    center: center, radius: outerR,
    startAngle: startRad, endAngle: endRad,
    clockwise: false
)
cPath.addLine(to: innerEnd)
// Inner arc: 320° → 40° via 270°/180°/90° (negative sweep, the long way).
cPath.addArc(
    center: center, radius: innerR,
    startAngle: endRad, endAngle: startRad,
    clockwise: true
)
cPath.closeSubpath()

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
ctx.addPath(cPath)
ctx.fillPath()

// ── 5. Play triangle in the C's heart (the AI agent) ───────────────────
//
// A right-pointing triangle in the C's inner hole reads as both a "play /
// run" symbol and a cursor, conveying "the agent is ready to execute".
// Sits well within the inner radius (220) and points in the same direction
// the C opens.
let accentColor = CGColor(red: 0.204, green: 0.827, blue: 0.6, alpha: 1.0)  // #34D399 emerald-400

let triangleSize: CGFloat = 180
let triangleCenter = CGPoint(x: center.x - 10, y: center.y)  // slight left-of-center for visual balance
let triPath = CGMutablePath()
triPath.move(to: CGPoint(
    x: triangleCenter.x - triangleSize * 0.35,
    y: triangleCenter.y - triangleSize * 0.5
))
triPath.addLine(to: CGPoint(
    x: triangleCenter.x - triangleSize * 0.35,
    y: triangleCenter.y + triangleSize * 0.5
))
triPath.addLine(to: CGPoint(
    x: triangleCenter.x + triangleSize * 0.55,
    y: triangleCenter.y
))
triPath.closeSubpath()

ctx.setFillColor(accentColor)
ctx.addPath(triPath)
ctx.fillPath()

// ── 6. Save as PNG ──────────────────────────────────────────────────────
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"
let outputURL = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Failed to create image destination at \(outputPath)\n", stderr)
    exit(1)
}
guard let image = ctx.makeImage() else {
    fputs("Failed to make image\n", stderr)
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else {
    fputs("Failed to finalize image\n", stderr)
    exit(1)
}

print("Wrote \(outputPath) (\(size)x\(size))")
