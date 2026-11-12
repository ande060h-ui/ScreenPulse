// Renders the questions as screenshots (PNG).
// Usage: render questions.json out-folder
import AppKit

let args = CommandLine.arguments
let items = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
let outDir = args[2]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ item: [String: Any], selected: String?) -> Data {
    let width: CGFloat = 900
    let n = item["n"] as! Int, q = item["q"] as! String, opts = item["opts"] as! [String]
    let qFont = NSFont.systemFont(ofSize: 30, weight: .medium)
    let oFont = NSFont.systemFont(ofSize: 28)
    let pad: CGFloat = 36

    var blocks: [(NSAttributedString, CGFloat)] = []
    func add(_ s: String, font: NSFont, color: NSColor, gap: CGFloat) {
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        let h = a.boundingRect(with: NSSize(width: width - 2 * pad, height: 1000), options: [.usesLineFragmentOrigin]).height
        blocks.append((a, ceil(h) + gap))
    }
    add("\(n). \(q)", font: qFont, color: .black, gap: 26)
    for (i, o) in opts.enumerated() {
        let letter = String(UnicodeScalar(65 + i)!)
        add("\(selected == letter ? "◉" : "○")  \(letter). \(o)", font: oFont, color: NSColor(white: 0.2, alpha: 1), gap: 16)
    }
    let height = blocks.reduce(2 * pad) { $0 + $1.1 }

    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    var y = height - pad
    for (a, h) in blocks {
        let bh = h - (h == blocks.first!.1 ? 26 : 16)
        a.draw(in: NSRect(x: pad, y: y - bh, width: width - 2 * pad, height: bh))
        y -= h
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for item in items {
    let n = String(format: "%02d", item["n"] as! Int)
    try! render(item, selected: nil).write(to: URL(fileURLWithPath: "\(outDir)/\(n).png"))
    try! render(item, selected: item["wrong"] as? String).write(to: URL(fileURLWithPath: "\(outDir)/\(n)_wrong.png"))
}
print("Tegnede \(items.count * 2) billeder i \(outDir)")
