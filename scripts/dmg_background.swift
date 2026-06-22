#!/usr/bin/env swift
// Renders the .dmg window background: title + an arrow from the app icon toward
// the Applications folder. Icons themselves are placed by Finder on top.
//   swift scripts/dmg_background.swift <out.png>
import AppKit

let W = 600.0, H = 400.0
let navy  = NSColor(srgbRed: 0.10, green: 0.18, blue: 0.32, alpha: 1)
let blue  = NSColor(srgbRed: 0x0D/255, green: 0x5E/255, blue: 0xAF/255, alpha: 1)
let gray  = NSColor(srgbRed: 0.42, green: 0.47, blue: 0.55, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// background gradient
NSGradient(starting: NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1),
           ending:   NSColor(srgbRed: 0.89, green: 0.92, blue: 0.96, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)

func centered(_ s: String, _ font: NSFont, _ color: NSColor, y: CGFloat) {
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let sz = (s as NSString).size(withAttributes: a)
    (s as NSString).draw(at: NSPoint(x: (W - sz.width)/2, y: y), withAttributes: a)
}

// title + subtitle (NSImage origin is bottom-left, so larger y = higher up)
centered("ela", NSFont.systemFont(ofSize: 44, weight: .bold), navy, y: H - 86)
centered("Greek accents, typed for you", NSFont.systemFont(ofSize: 15, weight: .regular), gray, y: H - 116)
centered("Drag ela to your Applications folder", NSFont.systemFont(ofSize: 13, weight: .medium), gray, y: 56)

// arrow in the gap between the two icons (icons sit around y≈200 from the top,
// i.e. y≈200 from bottom in a 400-tall canvas)
let ay = H - 200
let path = NSBezierPath()
path.lineWidth = 5
path.lineCapStyle = .round
path.move(to: NSPoint(x: 250, y: ay))
path.line(to: NSPoint(x: 350, y: ay))
blue.setStroke(); path.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 366, y: ay))
head.line(to: NSPoint(x: 346, y: ay + 12))
head.line(to: NSPoint(x: 346, y: ay - 12))
head.close()
blue.setFill(); head.fill()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-bg.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
