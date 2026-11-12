// Screen capture using the system `screencapture` tool (requires the Screen Recording permission).

import AppKit

enum Screenshot {
    /// Captures the whole screen the mouse pointer is on. Returns a PNG as base64.
    static func aroundCursor() async -> String? {
        let mouse = NSEvent.mouseLocation // AppKit: origin bottom-left
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let primary = NSScreen.screens.first else { return nil }

        // The entire screen under the pointer. The pointer is drawn into the image (-C)
        // so the AI can see what you are pointing at.
        // (Benchmark with the original prompt: 97 % correct vs. 68 % with a crop around the pointer.)
        let r = screen.frame

        // screencapture uses a top-left origin on the primary screen
        let top = primary.frame.height - r.maxY
        let region = "\(Int(r.minX)),\(Int(top)),\(Int(r.width)),\(Int(r.height))"
        let file = NSTemporaryDirectory() + "screenpulse-\(UUID().uuidString).png"

        return await Task.detached { () -> String? in
            defer { try? FileManager.default.removeItem(atPath: file) }
            guard runTool("/usr/sbin/screencapture", ["-x", "-C", "-R", region, file]),
                  FileManager.default.fileExists(atPath: file) else { return nil }
            _ = runTool("/usr/bin/sips", ["-Z", "2000", file]) // downscale to keep the upload small
            guard let data = FileManager.default.contents(atPath: file), !data.isEmpty else { return nil }
            return data.base64EncodedString()
        }.value
    }

    private static func runTool(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
