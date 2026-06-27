import AppKit

// Renders the DMG installer-window background: brand, instructions, and an arrow
// from the app icon to the Applications folder. Usage: swift dmgbg.swift out.png
let W: CGFloat = 660, H: CGFloat = 440
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// Background gradient (blue-tinted dark, matching the app's Ocean theme).
NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.10, blue: 0.16, alpha: 1),
                    NSColor(srgbRed: 0.03, green: 0.045, blue: 0.07, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
// Soft accent glow up top.
NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.52, blue: 0.78, alpha: 0.22), .clear])!
    .draw(in: NSRect(x: W/2 - 300, y: H - 300, width: 600, height: 340),
          relativeCenterPosition: NSPoint(x: 0, y: 0.2))

let accent = NSColor(srgbRed: 0.13, green: 0.52, blue: 0.78, alpha: 1)

func text(_ s: String, _ font: NSFont, _ color: NSColor, centerY: CGFloat, kern: CGFloat = 0) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p, .kern: kern]
    let sz = (s as NSString).size(withAttributes: attr)
    (s as NSString).draw(in: NSRect(x: 0, y: centerY - sz.height/2, width: W, height: sz.height + 4), withAttributes: attr)
}

let serif = NSFont(name: "Georgia-Bold", size: 38) ?? NSFont.boldSystemFont(ofSize: 38)
let body  = NSFont.systemFont(ofSize: 15, weight: .regular)
let small = NSFont.systemFont(ofSize: 12, weight: .regular)
let caps  = NSFont.systemFont(ofSize: 11, weight: .semibold)

// Title + subtitle.
text("Penwick", serif, .white, centerY: H - 62)
text("Drag Penwick onto the Applications folder to install", body,
     NSColor(white: 0.78, alpha: 1), centerY: H - 100)

// Arrow between the two icons (icons are centered by Finder near top-y 215 → here y ≈ 225).
let ay: CGFloat = 225
accent.setStroke(); accent.setFill()
let shaft = NSBezierPath(); shaft.lineWidth = 6; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 264, y: ay)); shaft.line(to: NSPoint(x: 396, y: ay)); shaft.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 410, y: ay))
head.line(to: NSPoint(x: 391, y: ay + 12))
head.line(to: NSPoint(x: 391, y: ay - 12))
head.close(); head.fill()
text("DRAG TO INSTALL", caps, accent, centerY: ay + 34, kern: 2)

// Footnote about the unsigned first-launch step.
text("First launch: right-click Penwick → Open  ·  it's unsigned, not unsafe", small,
     NSColor(white: 0.55, alpha: 1), centerY: 40)

img.unlockFocus()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmgbg.png"
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
