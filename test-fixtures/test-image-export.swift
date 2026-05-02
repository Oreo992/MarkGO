// Headless long-image export check. Mirrors the production rendering path
// so a regression of the "context creation" error fails this script.
//
// Run: swift test-fixtures/test-image-export.swift

import AppKit
import Foundation

let title = "MarkLens 长图导出验证"
let body = """
长图导出应当能在不弹出 GUI 的情况下生成 PNG。
- 暖纸色背景
- 顶部小色块强调
- 文字按阅读顺序从上到下排列
"""

let backgroundColor = NSColor(red: 0.985, green: 0.970, blue: 0.925, alpha: 1)
let inkColor = NSColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
let accentColor = NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1)

let canvasWidth: CGFloat = 1080
let horizontalPadding = canvasWidth * 0.066
let contentWidth = canvasWidth - horizontalPadding * 2

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 6

let attributed = NSMutableAttributedString(
    string: "\(title)\n\n\(body)",
    attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .regular),
        .foregroundColor: inkColor,
        .paragraphStyle: paragraph
    ]
)
attributed.addAttributes(
    [
        .font: NSFont.systemFont(ofSize: 56, weight: .heavy),
        .foregroundColor: accentColor
    ],
    range: NSRange(location: 0, length: (title as NSString).length)
)

let measured = attributed.boundingRect(
    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
    options: [.usesLineFragmentOrigin, .usesFontLeading],
    context: nil
)
let canvasHeight = max(canvasWidth, measured.height + 220)

let canvasSize = NSSize(width: canvasWidth, height: canvasHeight)
let image = NSImage(size: canvasSize)
image.lockFocusFlipped(true)
guard let graphicsContext = NSGraphicsContext.current else {
    image.unlockFocus()
    print("✘ No current graphics context")
    exit(1)
}
let cg = graphicsContext.cgContext

cg.setFillColor(backgroundColor.cgColor)
cg.fill(CGRect(origin: .zero, size: canvasSize))

cg.setFillColor(accentColor.withAlphaComponent(0.20).cgColor)
cg.fill(CGRect(x: horizontalPadding, y: 64, width: 160, height: 12))

attributed.draw(in: CGRect(
    x: horizontalPadding,
    y: 100,
    width: contentWidth,
    height: measured.height + 40
))

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let data = bitmap.representation(using: .png, properties: [:]) else {
    print("✘ Failed to encode PNG")
    exit(2)
}

let outputURL = URL(fileURLWithPath: "/tmp/marklens-image-check.png")
try? FileManager.default.removeItem(at: outputURL)
try data.write(to: outputURL)
print("✔ Wrote PNG to \(outputURL.path) (\(data.count) bytes)")
print("Open it with: open \(outputURL.path)")
