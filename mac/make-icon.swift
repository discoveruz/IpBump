// Draws IpBump's icon (orange tile, white "IP" over a "next" arrow), the design tools/make-icon.ps1 draws for
// Windows, on the macOS icon grid, and writes it as Assets/IpBump.icns.
// Run it again after changing the design:   swift mac/make-icon.swift
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Assets/IpBump.icns").path)

func icon(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)

    // The macOS grid: an 824-point tile in the middle of a 1024-point canvas
    let tile = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let t = tile.width
    let shape = NSBezierPath(roundedRect: tile, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    // The same orange as the Windows icon, slightly lighter at the top
    NSGradient(starting: NSColor(srgbRed: 240 / 255, green: 140 / 255, blue: 96 / 255, alpha: 1),
               ending: NSColor(srgbRed: 222 / 255, green: 104 / 255, blue: 62 / 255, alpha: 1))!.draw(in: shape, angle: -90)

    // Small sizes carry only the letters; from 64 px up there is room for the arrow underneath
    let withArrow = pixels >= 64
    let font = NSFont.systemFont(ofSize: t * (withArrow ? 0.50 : 0.66), weight: .bold)
    let letters = NSAttributedString(string: "IP", attributes: [.font: font, .foregroundColor: NSColor.white])
    let center = tile.maxY - t * (withArrow ? 0.40 : 0.50)
    letters.draw(at: NSPoint(x: tile.midX - letters.size().width / 2, y: center - font.capHeight / 2 + font.descender))

    if withArrow {
        let y = tile.maxY - t * 0.76, from = tile.minX + t * 0.27, to = tile.minX + t * 0.73, head = t * 0.11
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: from, y: y))
        arrow.line(to: NSPoint(x: to, y: y))
        arrow.move(to: NSPoint(x: to - head, y: y + head))
        arrow.line(to: NSPoint(x: to, y: y))
        arrow.line(to: NSPoint(x: to - head, y: y - head))
        arrow.lineWidth = max(2, t * 0.075)
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor.white.setStroke()
        arrow.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("IpBump-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try icon(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(out.path)")
