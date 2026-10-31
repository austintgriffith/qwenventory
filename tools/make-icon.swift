// Draws an app icon: an SF Symbol on a two-color gradient.
// swift tools/make-icon.swift <out.png> <size> [symbol] [#top] [#bottom] [#symbol]
import AppKit

let a = CommandLine.arguments
let out = a[1]
let size = CGFloat(Double(a[2])!)
let symbolName = a.count > 3 ? a[3] : "brain.head.profile"

func color(_ hex: String, _ fallback: NSColor) -> NSColor {
    var v: UInt64 = 0
    guard Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&v) else { return fallback }
    return NSColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: 1)
}
let top = a.count > 4 ? color(a[4], .systemBlue) : NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1)
let bottom = a.count > 5 ? color(a[5], .blue) : NSColor(red: 0.10, green: 0.20, blue: 0.55, alpha: 1)

let ink = a.count > 6 ? color(a[6], .white) : NSColor.white

guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    FileHandle.standardError.write("no SF Symbol named \(symbolName)\n".data(using: .utf8)!)
    exit(1)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .regular)
    .applying(.init(paletteColors: [ink]))
let symbol = base.withSymbolConfiguration(config)!
let s = symbol.size
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
