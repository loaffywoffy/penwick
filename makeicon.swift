import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = rect.width * 0.2237
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// --- Vibrant, alive gradient (violet → indigo) with warm glow ---
cg.saveGState()
squircle.addClip()
let c1 = NSColor(calibratedRed: 0.56, green: 0.40, blue: 1.00, alpha: 1)   // bright violet
let c2 = NSColor(calibratedRed: 0.40, green: 0.31, blue: 0.95, alpha: 1)
let c3 = NSColor(calibratedRed: 0.24, green: 0.17, blue: 0.74, alpha: 1)   // deep indigo
NSGradient(colors: [c1, c2, c3])!.draw(in: rect, angle: -78)

// warm pink glow upper-left — gives it life, not corporate
NSGradient(colors: [NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.92, alpha: 0.30), NSColor(white: 1, alpha: 0.0)])!
    .draw(in: rect, relativeCenterPosition: NSPoint(x: -0.45, y: 0.55))
// glossy top sheen
NSGradient(colors: [NSColor(white: 1, alpha: 0.18), NSColor(white: 1, alpha: 0.0)])!
    .draw(in: rect, relativeCenterPosition: NSPoint(x: 0.2, y: 0.75))
// bottom depth
NSGradient(colors: [NSColor(white: 0, alpha: 0.0), NSColor(white: 0, alpha: 0.22)])!
    .draw(in: rect, angle: -90)
cg.restoreGState()

// --- Serif ampersand with depth ---
let serifDesc = NSFont.systemFont(ofSize: 660, weight: .bold)
    .fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: 660).fontDescriptor
let glyphFont = NSFont(descriptor: serifDesc, size: 660) ?? NSFont(name: "Times New Roman", size: 660)!

let para = NSMutableParagraphStyle(); para.alignment = .center
let amp = NSAttributedString(string: "&", attributes: [
    .font: glyphFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.98),
    .paragraphStyle: para,
])
let b = amp.boundingRect(with: NSSize(width: S, height: S), options: [.usesLineFragmentOrigin])
let pt = NSPoint(x: (S - b.width) / 2, y: (S - b.height) / 2 - 18)

// soft drop shadow for dimensionality
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: NSColor(white: 0.10, alpha: 0.35).cgColor)
amp.draw(at: pt)
cg.restoreGState()

// subtle top highlight pass on the glyph (clip to its silhouette via a re-draw with lighter tint)
cg.saveGState()
let glow = NSAttributedString(string: "&", attributes: [
    .font: glyphFont,
    .foregroundColor: NSColor(white: 1.0, alpha: 0.10),
    .paragraphStyle: para,
])
glow.draw(at: NSPoint(x: pt.x, y: pt.y + 6))
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
try! png.write(to: out)
print("wrote \(out.path)")
