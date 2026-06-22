#!/usr/bin/env swift
// Builds the ela app icon as an Icon Composer `.icon` document (Liquid Glass).
// The blue έ sits on an adaptive background, so macOS 26 (Tahoe) renders proper
// Default / Dark / Tinted variants — the letter stays blue, the background
// follows the system icon theme. `actool` compiles the .icon in build-app.sh.
//
//   swift scripts/make_icon.swift <out-AppIcon.icon-dir>
import AppKit

// ---- design knobs -----------------------------------------------------------
let blue        = NSColor(srgbRed: 0x0D/255, green: 0x5E/255, blue: 0xAF/255, alpha: 1) // #0D5EAF
let bgColor     = "srgb:0.92,0.95,0.98,1.0"   // light base; Tahoe darkens it for Dark
let fontName    = "Didot-Bold"
let glyph       = "έ"
let glyphHeight = 0.62                          // glyph box height / icon side

/// Render the blue glyph centred on a transparent canvas (the background comes
/// from the .icon fill, so it can adapt to the appearance).
func glyphPNG(side: Int) -> Data {
    let s = CGFloat(side)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ns = glyph as NSString
    let base = NSFont(name: fontName, size: s) ?? NSFont.boldSystemFont(ofSize: s)
    let h0 = ns.size(withAttributes: [.font: base]).height
    let font = NSFont(name: fontName, size: s * CGFloat(glyphHeight) / h0 * base.pointSize)
            ?? NSFont.boldSystemFont(ofSize: s * 0.62)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: blue]
    let gs = ns.size(withAttributes: attrs)
    ns.draw(at: NSPoint(x: (s - gs.width)/2, y: (s - gs.height)/2), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icon"
let assets = out + "/Assets"
try? FileManager.default.createDirectory(atPath: assets, withIntermediateDirectories: true)
try! glyphPNG(side: 1024).write(to: URL(fileURLWithPath: assets + "/glyph.png"))

let iconJSON = """
{
  "fill" : { "automatic-gradient" : "\(bgColor)" },
  "groups" : [ { "layers" : [ { "image-name" : "glyph.png", "name" : "epsilon" } ] } ],
  "supported-platforms" : { "circles" : [], "squares" : ["macOS"] }
}
"""
try! iconJSON.write(toFile: out + "/icon.json", atomically: true, encoding: .utf8)
print("wrote \(out)")
