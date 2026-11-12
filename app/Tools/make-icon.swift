// Draws the app icon (1024×1024 PNG). Usage: swiftc make-icon.swift -o x && ./x out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// macOS icon shape: rounded square with a little air around it
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
squircle.fill()
ctx.restoreGState()

// Background: ink, slightly lighter towards the top
ctx.saveGState()
squircle.addClip()
let ink = NSGradient(colors: [NSColor(srgbRed: 0.047, green: 0.063, blue: 0.055, alpha: 1),
                              NSColor(srgbRed: 0.098, green: 0.122, blue: 0.110, alpha: 1)])!
ink.draw(in: body, angle: 90)
ctx.restoreGState()

// The mark: rows of 1, 2 and 3 dots (the blink code for A, B, C). Top dot is the lit LED.
let d: CGFloat = 132, step: CGFloat = 196
let gridW = 2 * step + d
let originX = body.midX - gridW / 2
let topY = body.midY + gridW / 2 - d
let paper = NSColor(srgbRed: 0.949, green: 0.945, blue: 0.925, alpha: 1)
let led = NSColor(srgbRed: 0.208, green: 0.886, blue: 0.478, alpha: 1)

for row in 0..<3 {
    for col in 0...row {
        let rect = CGRect(x: originX + CGFloat(col) * step, y: topY - CGFloat(row) * step, width: d, height: d)
        if row == 0 {
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 70, color: led.withAlphaComponent(0.9).cgColor)
            led.setFill()
            NSBezierPath(ovalIn: rect).fill()
            ctx.restoreGState()
        } else {
            paper.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
