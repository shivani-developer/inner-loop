#!/usr/bin/env swift

import AppKit

let outputURL = URL(fileURLWithPath: "JournalingCompanion/Resources/Assets.xcassets/AppIcon.appiconset/innerloop-app-icon.png")
let pixelSize = 1024
let size = CGSize(width: pixelSize, height: pixelSize)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let rect = CGRect(origin: .zero, size: size)
let context = NSGraphicsContext.current!.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let background = NSGradient(colors: [
    NSColor(red: 0.969, green: 0.949, blue: 0.902, alpha: 1),
    NSColor(red: 0.910, green: 0.941, blue: 0.922, alpha: 1)
])!
background.draw(in: NSBezierPath(rect: rect), angle: -35)

let green = NSColor(red: 0.184, green: 0.435, blue: 0.400, alpha: 1)
let ink = NSColor(red: 0.141, green: 0.231, blue: 0.212, alpha: 1)

let logoRect = rect.insetBy(dx: 210, dy: 210)
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: logoRect.minX + logoRect.width * x, y: logoRect.minY + logoRect.height * (1 - y))
}

let path = NSBezierPath()
path.move(to: point(0.31, 0.55))
path.curve(
    to: point(0.69, 0.29),
    controlPoint1: point(0.31, 0.37),
    controlPoint2: point(0.49, 0.23)
)
path.curve(
    to: point(0.88, 0.55),
    controlPoint1: point(0.82, 0.33),
    controlPoint2: point(0.88, 0.43)
)
path.curve(
    to: point(0.51, 0.82),
    controlPoint1: point(0.88, 0.73),
    controlPoint2: point(0.69, 0.86)
)
path.curve(
    to: point(0.18, 0.41),
    controlPoint1: point(0.27, 0.78),
    controlPoint2: point(0.15, 0.61)
)
path.curve(
    to: point(0.46, 0.08),
    controlPoint1: point(0.20, 0.24),
    controlPoint2: point(0.31, 0.12)
)
path.lineWidth = 48
path.lineCapStyle = .round
path.lineJoinStyle = .round
green.setStroke()
path.stroke()

let dotSize = logoRect.width * 0.14
let dotCenter = CGPoint(
    x: logoRect.minX + logoRect.width * 0.54,
    y: logoRect.minY + logoRect.height * (1 - 0.53)
)
let dotRect = CGRect(
    x: dotCenter.x - dotSize / 2,
    y: dotCenter.y - dotSize / 2,
    width: dotSize,
    height: dotSize
)
ink.setFill()
NSBezierPath(ovalIn: dotRect).fill()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not render app icon PNG")
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
print("Wrote \(outputURL.path)")
