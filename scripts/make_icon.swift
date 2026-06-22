#!/usr/bin/env swift
// Renders the ela app icon: a blue (Greek-flag) έ on a soft cool-light glass
// background, and writes an AppIcon.appiconset (mac idiom) ready for `actool`.
// macOS Tahoe auto-derives the Dark / Tinted / Clear icon-theme versions from
// this single base icon, so only one variant is authored here.
//
//   swift scripts/make_icon.swift <out-xcassets-dir>
import AppKit

// ---- design knobs -----------------------------------------------------------
let blue       = NSColor(srgbRed: 0x0D/255, green: 0x5E/255, blue: 0xAF/255, alpha: 1) // #0D5EAF
let bgTop      = NSColor(srgbRed: 0xEC/255, green: 0xF1/255, blue: 0xF8/255, alpha: 1) // soft cool light
let bgBot      = NSColor(srgbRed: 0xC9/255, green: 0xD5/255, blue: 0xE6/255, alpha: 1) // light blue-grey
let glyph       = "έ"
let fontName    = "Didot-Bold"
let insetRatio  = 0.06     // transparent margin around the squircle
let radiusRatio = 0.2237   // corner radius / side (Apple-ish)
let glyphHeight = 0.60     // target glyph box height / side

func render(side: Int) -> Data {
    let s = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * insetRatio
    let rect = NSRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
    let r = s * radiusRatio
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

    // base gradient
    NSGradient(starting: bgTop, ending: bgBot)!.draw(in: path, angle: -90)

    // depth: top highlight + bottom shade, clipped to the squircle
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(colors: [NSColor(white: 1, alpha: 0.55), NSColor(white: 1, alpha: 0)])!
        .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2), angle: -90)
    NSGradient(colors: [NSColor(white: 0, alpha: 0), NSColor(srgbRed: 0.1, green: 0.18, blue: 0.32, alpha: 0.12)])!
        .draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height*0.42), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // crisp edge
    path.lineWidth = max(1, s * 0.004)
    NSColor(white: 1, alpha: 0.6).setStroke()
    path.stroke()

    // glyph: size so its box height ≈ glyphHeight·side, then centre
    let ns = glyph as NSString
    let base = NSFont(name: fontName, size: s) ?? NSFont.boldSystemFont(ofSize: s)
    let h0 = ns.size(withAttributes: [.font: base]).height
    let probe = s * CGFloat(glyphHeight) / h0 * base.pointSize
    let font = NSFont(name: fontName, size: probe) ?? NSFont.boldSystemFont(ofSize: probe)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(srgbRed: 0.05, green: 0.12, blue: 0.25, alpha: 0.22)
    shadow.shadowBlurRadius = s * 0.022
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)

    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: blue, .shadow: shadow]
    let gs = ns.size(withAttributes: attrs)
    ns.draw(at: NSPoint(x: (s - gs.width)/2, y: (s - gs.height)/2), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// ---- write appiconset --------------------------------------------------------
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.xcassets"
let dir = "\(out)/AppIcon.appiconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

let ladder: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
var cache: [Int: Data] = [:]
func png(_ side: Int) -> Data { cache[side] ?? { let d = render(side: side); cache[side] = d; return d }() }

var images: [[String: Any]] = []
for (pt, scale) in ladder {
    let f = "icon_\(pt)x\(pt)@\(scale)x.png"
    try! png(pt * scale).write(to: URL(fileURLWithPath: "\(dir)/\(f)"))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": f])
}

let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "ela"]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: "\(dir)/Contents.json"))
print("wrote \(dir) (\(images.count) sizes)")
