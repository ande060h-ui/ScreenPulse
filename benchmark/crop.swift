// Crops a PNG precisely: crop in.png out.png x y width height (in pixels)
import AppKit
let a = CommandLine.arguments
guard a.count == 7, let src = NSImage(contentsOfFile: a[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let x = Int(a[3]), let y = Int(a[4]), let w = Int(a[5]), let h = Int(a[6]),
      let cut = src.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else { print("error"); exit(1) }
let rep = NSBitmapImageRep(cgImage: cut)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
