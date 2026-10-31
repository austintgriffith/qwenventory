// Draws a plain app icon (SF Symbol brain on a blue square).
// swift tools/make-icon.swift <out.png> <size>
import AppKit

let out = CommandLine.arguments[1]
let size = CGFloat(Double(CommandLine.arguments[2])!)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1),
           ending: NSColor(red: 0.10, green: 0.20, blue: 0.55, alpha: 1))!.draw(in: rect, angle: -90)
let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .regular)
    .applying(.init(paletteColors: [.white]))
let symbol = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let s = symbol.size
symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
