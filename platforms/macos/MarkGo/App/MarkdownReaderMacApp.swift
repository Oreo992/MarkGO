import AppKit
import PDFKit
import SwiftUI

@main
struct MarkdownReaderMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MarkGo", id: "library") {
            LibraryWindow()
                .frame(minWidth: 880, minHeight: 580)
                .preferredColorScheme(.light)
                .background(WindowAccessor { window in
                    window.appearance = NSAppearance(named: .aqua)
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.isMovableByWindowBackground = true
                    window.tabbingMode = .disallowed
                })
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            AppCommands()
        }

        DocumentGroup(viewing: MarkdownDocument.self) { file in
            DocumentReaderRoot(document: file.$document, fileURL: file.fileURL)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.light)
                .background(WindowAccessor { window in
                    window.appearance = NSAppearance(named: .aqua)
                    window.titlebarAppearsTransparent = true
                    window.tabbingMode = .preferred
                })
        }
        .commands {
            DocumentCommands()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ExportSmokeRunner.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

private enum ExportSmokeRunner {
    @MainActor
    static func runIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--markgo-export-smoke") else { return false }

        do {
            let outputDirectory: URL
            if arguments.indices.contains(flagIndex + 1) {
                outputDirectory = URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
            } else {
                outputDirectory = FileManager.default
                    .temporaryDirectory
                    .appendingPathComponent("markgo-export-smoke-\(UUID().uuidString)", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let fixtureDirectory = outputDirectory.appendingPathComponent("fixtures", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
            let imageURL = fixtureDirectory.appendingPathComponent("local.png")
            try writeFixtureImage(to: imageURL)

            let markdownURL = outputDirectory.appendingPathComponent("source.md")
            let markdown = makeFixtureMarkdown()
            try markdown.write(to: markdownURL, atomically: true, encoding: .utf8)

            let pdfURL = outputDirectory.appendingPathComponent("markgo-smoke.pdf")
            let pngURL = outputDirectory.appendingPathComponent("markgo-smoke.png")
            let htmlURL = outputDirectory.appendingPathComponent("markgo-smoke.html")

            try ExportRunner.writePDF(
                to: pdfURL,
                title: "MarkGo Export Smoke",
                text: markdown,
                theme: .paper,
                pageSize: .a4,
                sourceURL: markdownURL,
                watermark: true
            )
            try ExportRunner.writeLongImage(
                to: pngURL,
                title: "MarkGo Export Smoke",
                text: markdown,
                theme: .paper,
                width: .standard,
                sourceURL: markdownURL,
                watermark: true
            )
            try ExportRunner.writeHTML(
                to: htmlURL,
                title: "MarkGo Export Smoke",
                text: markdown,
                theme: .paper,
                sourceURL: markdownURL
            )

            let pageCount = PDFDocument(url: pdfURL)?.pageCount ?? 0
            let pngData = try Data(contentsOf: pngURL)
            guard let pngBitmap = NSBitmapImageRep(data: pngData) else {
                throw ExportSmokeError.invalidPNG
            }
            let html = try String(contentsOf: htmlURL, encoding: .utf8)
            guard html.contains("data:image/png;base64") else {
                throw ExportSmokeError.missingEmbeddedImage
            }
            guard pageCount >= 2 else {
                throw ExportSmokeError.tooFewPDFPages(pageCount)
            }
            guard pngBitmap.pixelsWide == Int(ImageWidth.standard.width),
                  pngBitmap.pixelsHigh > pngBitmap.pixelsWide else {
                throw ExportSmokeError.invalidPNGDimensions(pngBitmap.pixelsWide, pngBitmap.pixelsHigh)
            }

            print("MarkGo export smoke OK")
            print("output=\(outputDirectory.path)")
            print("pdf=\(pdfURL.path)")
            print("pdfPages=\(pageCount)")
            print("png=\(pngURL.path)")
            print("pngPixels=\(pngBitmap.pixelsWide)x\(pngBitmap.pixelsHigh)")
            print("html=\(htmlURL.path)")
            print("htmlBytes=\((try? Data(contentsOf: htmlURL).count) ?? 0)")
        } catch {
            fputs("MarkGo export smoke FAILED: \(error)\n", stderr)
            exit(2)
        }

        return true
    }

    private static func makeFixtureMarkdown() -> String {
        let intro = """
        # MarkGo Export Smoke

        这是一份用于真实导出测试的长文档，包含中文、本地图片、表格、代码块、引用和足够多的章节。

        ![Local fixture](fixtures/local.png)

        | 项目 | 结果 | 备注 |
        | --- | --- | --- |
        | PDF | 分页 | 检查是否生成多页 |
        | PNG | 长图 | 检查长图高度 |
        | HTML | 图片 | 检查本地图是否内联 |

        ```swift
        let renderer = "MarkGo"
        print(renderer)
        ```
        """

        let section = """

        ## 深度测试章节

        > 这里模拟用户真实 Markdown 里的说明、引用和长段落。

        - 第一项包含中文文本，用于观察字体和行高。
        - 第二项包含 **加粗**、*斜体* 和 `inline code`。
        - 第三项继续拉长文档，触发多页 PDF 分片。

        这是一段较长的正文。MarkGo 需要在 macOS 上稳定地把 Markdown 渲染为可读、可导出、不会被截断的成品。这里重复足够多的内容，确保 PDF 至少跨越多页，同时长图高度明显超过宽度。
        """

        return intro + Array(repeating: section, count: 42).joined()
    }

    private static func writeFixtureImage(to url: URL) throws {
        let size = NSSize(width: 720, height: 360)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(red: 0.12, green: 0.20, blue: 0.45, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSColor(red: 0.20, green: 0.75, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 62, width: 624, height: 236), xRadius: 32, yRadius: 32).fill()
        let label = "MarkGo local image"
        label.draw(
            at: NSPoint(x: 96, y: 162),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 36, weight: .heavy),
                .foregroundColor: NSColor.white
            ]
        )
        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportSmokeError.invalidPNG
        }
        try pngData.write(to: url, options: .atomic)
    }
}

private enum ExportSmokeError: LocalizedError {
    case invalidPNG
    case missingEmbeddedImage
    case tooFewPDFPages(Int)
    case invalidPNGDimensions(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidPNG:
            "PNG 文件无效"
        case .missingEmbeddedImage:
            "HTML 没有内联本地 PNG"
        case .tooFewPDFPages(let count):
            "PDF 页数过少：\(count)"
        case .invalidPNGDimensions(let width, let height):
            "PNG 尺寸异常：\(width)x\(height)"
        }
    }
}

/// Bridges to the underlying NSWindow so we can refine chrome behavior beyond
/// what SwiftUI exposes directly.
struct WindowAccessor: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            configure(window)
        }
    }
}
