import AppKit
import Foundation

let size = 1024
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
context.setFillColor(CGColor(red: 0.066, green: 0.078, blue: 0.078, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setLineCap(.round)
context.setLineWidth(11)
for tick in 0 ..< 76 {
    let angle = Double.pi * 7 / 6 - Double(tick) / 75 * Double.pi * 5 / 3
    let progress = Double(tick) / 75
    let color = tick < 58
        ? CGColor(red: 0.72 - progress * 0.40, green: 0.90, blue: 0.33 + progress * 0.35, alpha: 1)
        : CGColor(red: 0.22, green: 0.28, blue: 0.26, alpha: 1)
    context.setStrokeColor(color)
    context.move(to: CGPoint(x: 512 + cos(angle) * 310, y: 530 + sin(angle) * 310))
    context.addLine(to: CGPoint(x: 512 + cos(angle) * 357, y: 530 + sin(angle) * 357))
    context.strokePath()
}

/// Original current-trace artwork, drawn directly from these coordinates.
/// Do not embed SF Symbols or other third-party glyphs in the app icon.
let trace = CGMutablePath()
trace.move(to: CGPoint(x: 334, y: 490))
trace.addLine(to: CGPoint(x: 402, y: 490))
trace.addLine(to: CGPoint(x: 456, y: 650))
trace.addLine(to: CGPoint(x: 532, y: 402))
trace.addLine(to: CGPoint(x: 585, y: 554))
trace.addLine(to: CGPoint(x: 666, y: 554))
context.setStrokeColor(CGColor(red: 0.86, green: 0.98, blue: 0.91, alpha: 1))
context.setLineWidth(32)
context.setLineJoin(.round)
context.addPath(trace)
context.strokePath()
context.setFillColor(CGColor(red: 0.64, green: 0.94, blue: 0.39, alpha: 1))
context.fillEllipse(in: CGRect(x: 647, y: 535, width: 38, height: 38))
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Current/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output)
print("Generated \(output.lastPathComponent)")
