import AppKit
import Foundation

// Rasterises an SVG with AppKit's built-in SVG support (CoreSVG, macOS 11+).
//   render-icon <in.svg> <out.png> <pixel-size>
// No third-party tools, nothing downloaded.
let a = CommandLine.arguments
guard a.count == 4, let px = Int(a[3]) else {
    FileHandle.standardError.write("usage: render-icon <in.svg> <out.png> <pixels>\n".data(using: .utf8)!)
    exit(2)
}
guard let svg = NSImage(contentsOfFile: a[1]) else {
    FileHandle.standardError.write("cannot load \(a[1])\n".data(using: .utf8)!)
    exit(1)
}
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
    exit(1)
}
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.cgContext.clear(CGRect(x: 0, y: 0, width: px, height: px))
ctx.imageInterpolation = .high
svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1.0)
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: a[2]))
print("wrote \(a[2]) \(px)x\(px)")
