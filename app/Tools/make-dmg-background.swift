// Draws the background of the installer window: a soft chevron between the app and the
// Applications folder, and a short instruction. Writes two PNGs: 660×400 and 1320×800 (Retina).
// Usage: make-dmg-background <out-1x.png> <out-2x.png>
import AppKit

let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2 else { FileHandle.standardError.write("usage: make-dmg-background 1x.png 2x.png\n".data(using: .utf8)!); exit(1) }

func render(scale: Int, to path: String) {
    let w = 660 * scale, h = 400 * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 660, height: 400)   // points; the 2x file is 144 dpi
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // Background
    NSColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 660, height: 400).fill()

    // Chevron between the two icons (icons sit at y = 190 from the top → 210 from the bottom)
    let chevron = NSBezierPath()
    chevron.lineWidth = 7
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.move(to: NSPoint(x: 318, y: 232))
    chevron.line(to: NSPoint(x: 340, y: 210))
    chevron.line(to: NSPoint(x: 318, y: 188))
    NSColor(srgbRed: 0.35, green: 0.36, blue: 0.38, alpha: 1).setStroke()
    chevron.stroke()

    // Instruction
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let text = NSAttributedString(string: "Drag ScreenPulse to Applications", attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .medium),
        .foregroundColor: NSColor(srgbRed: 0.35, green: 0.36, blue: 0.38, alpha: 1),
        .paragraphStyle: para,
    ])
    text.draw(in: NSRect(x: 0, y: 48, width: 660, height: 24))

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
render(scale: 1, to: args[0])
render(scale: 2, to: args[1])
