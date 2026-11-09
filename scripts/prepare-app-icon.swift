#!/usr/bin/env swift
import AppKit

// Preserve the original artwork inside a macOS-style rounded tile, with
// transparent corners and the same optical inset as other Dock icons.
// Usage: swift scripts/prepare-app-icon.swift source.png output.png output.iconset
let arguments = CommandLine.arguments
guard arguments.count == 4, let source = NSImage(contentsOfFile: arguments[1]) else {
    fatalError("Expected source.png output.png output.iconset")
}
let output = URL(fileURLWithPath: arguments[2])
let iconset = URL(fileURLWithPath: arguments[3], isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let path = NSBezierPath()
    // Match the existing artwork's curved outline, excluding its white canvas.
    let radius = 432.0
    for step in 0...720 {
        let angle = Double(step) / 720 * 2 * Double.pi
        let c = cos(angle), s = sin(angle)
        let point = NSPoint(
            x: 512 + radius * (c < 0 ? -1 : 1) * pow(abs(c), 0.5),
            y: 512 + radius * (s < 0 ? -1 : 1) * pow(abs(s), 0.5)
        )
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    path.addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 64, y: 64, width: 896, height: 896), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

try render(size: 1024).write(to: output)
for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
