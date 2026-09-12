#!/usr/bin/env swift

import AppKit

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current else {
    fputs("Unable to create graphics context\n", stderr)
    exit(1)
}

context.imageInterpolation = .high

let backgroundRect = NSRect(x: 40, y: 40, width: 944, height: 944)
let background = NSBezierPath(roundedRect: backgroundRect, xRadius: 220, yRadius: 220)
NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
background.fill()

let innerRect = backgroundRect.insetBy(dx: 14, dy: 14)
let inner = NSBezierPath(roundedRect: innerRect, xRadius: 208, yRadius: 208)
NSColor(calibratedWhite: 1, alpha: 0.09).setStroke()
inner.lineWidth = 8
inner.stroke()

let accent = NSColor(calibratedRed: 0.08, green: 0.72, blue: 0.50, alpha: 1)
let info = NSColor(calibratedRed: 0.22, green: 0.55, blue: 0.92, alpha: 1)

let branchPath = NSBezierPath()
branchPath.lineWidth = 34
branchPath.lineCapStyle = .round
branchPath.move(to: NSPoint(x: 280, y: 315))
branchPath.line(to: NSPoint(x: 280, y: 690))
branchPath.move(to: NSPoint(x: 280, y: 540))
branchPath.curve(
    to: NSPoint(x: 690, y: 390),
    controlPoint1: NSPoint(x: 470, y: 540),
    controlPoint2: NSPoint(x: 500, y: 390)
)
accent.setStroke()
branchPath.stroke()

let nodes: [(NSPoint, NSColor)] = [
    (NSPoint(x: 280, y: 750), info),
    (NSPoint(x: 280, y: 640), accent),
    (NSPoint(x: 280, y: 250), accent),
    (NSPoint(x: 700, y: 345), info)
]

for (point, color) in nodes {
    let circle = NSBezierPath(ovalIn: NSRect(x: point.x - 47, y: point.y - 47, width: 94, height: 94))
    NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
    circle.fill()
    color.setStroke()
    circle.lineWidth = 25
    circle.stroke()
}

let prompt = ">_" as NSString
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: 188, weight: .bold),
    .foregroundColor: NSColor.white
]
let promptSize = prompt.size(withAttributes: attributes)
prompt.draw(
    at: NSPoint(x: 360, y: 190 - promptSize.height / 2),
    withAttributes: attributes
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("Unable to encode icon\n", stderr)
    exit(1)
}

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png")
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output)
print(output.path)
