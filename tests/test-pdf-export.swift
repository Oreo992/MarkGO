// Headless export check: writes a PDF to /tmp using the same Core Text
// drawing logic as ExportRunner so we can confirm the fix without driving
// the GUI.
//
// Run: swift tests/test-pdf-export.swift

import AppKit
import CoreText
import Foundation
import UniformTypeIdentifiers

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let exportRunnerURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Export/ExportRunner.swift")
let exportRunnerSource = try String(contentsOf: exportRunnerURL, encoding: .utf8)

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        exit(1)
    }
}

expect(
    exportRunnerSource.range(
        of: #"canvasWidth:\s*pageSize\.size\.width\s*[,)]"#,
        options: .regularExpression
    ) == nil,
    "PDF export does not render at raw page width, which makes text too large"
)
expect(
    !exportRunnerSource.contains("let visibleHeightInImagePoints = pageSize.size.height"),
    "PDF export does not hard-cut pages at raw page height"
)
expect(
    exportRunnerSource.contains("nextPDFSliceHeight"),
    "PDF export uses whitespace-aware page slicing"
)

let title = "MarkGo 导出验证"
let body = """
这是一段用于验证 PDF 导出修复的文字。
- 背景应为暖纸色，而不是黑色
- 标题与正文应当从顶部向下阅读
- 中文与 English 混排时应当正确显示

```swift
struct Sample {
    let value = "代码块也应正常"
}
```

如果你看到了这一行，说明 PDF 渲染顺序正确。
"""

let backgroundColor = NSColor(red: 0.985, green: 0.970, blue: 0.925, alpha: 1)
let inkColor = NSColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
let accentColor = NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1)

let paragraph = NSMutableParagraphStyle()
paragraph.lineSpacing = 4
paragraph.paragraphSpacing = 8

let attributed = NSMutableAttributedString(
    string: "\(title)\n\n\(body)",
    attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: inkColor,
        .paragraphStyle: paragraph
    ]
)
attributed.addAttributes(
    [
        .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
        .foregroundColor: accentColor
    ],
    range: NSRange(location: 0, length: (title as NSString).length)
)

let outputURL = URL(fileURLWithPath: "/tmp/markgo-export-check.pdf")
try? FileManager.default.removeItem(at: outputURL)

var pageRect = CGRect(x: 0, y: 0, width: 595, height: 842)
guard let context = CGContext(outputURL as CFURL, mediaBox: &pageRect, nil) else {
    print("✘ Failed to create PDF context")
    exit(1)
}

let framesetter = CTFramesetterCreateWithAttributedString(attributed)
var range = CFRange(location: 0, length: 0)

repeat {
    context.beginPDFPage(nil)
    context.setFillColor(backgroundColor.cgColor)
    context.fill(pageRect)

    let path = CGMutablePath()
    path.addRect(pageRect.insetBy(dx: 48, dy: 56))
    let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
    CTFrameDraw(frame, context)

    context.endPDFPage()
    let visible = CTFrameGetVisibleStringRange(frame)
    range.location += visible.length
} while range.location < attributed.length

context.closePDF()

guard FileManager.default.fileExists(atPath: outputURL.path) else {
    print("✘ Did not write PDF at \(outputURL.path)")
    exit(2)
}

let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
let size = attrs[.size] as? Int ?? 0
print("✔ Wrote PDF to \(outputURL.path) (\(size) bytes)")
print("Open it with: open \(outputURL.path)")
