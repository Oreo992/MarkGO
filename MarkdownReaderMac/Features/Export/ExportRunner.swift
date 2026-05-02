import AppKit
import CoreText
import UniformTypeIdentifiers

/// Runs the actual export by drawing into PDF, PNG, or HTML targets and
/// presenting the system save panel. Mirrors the iOS rendering rules so
/// exports look like the same brand artifact regardless of platform.
@MainActor
enum ExportRunner {
    static func savePDF(
        title: String,
        text: String,
        theme: ExportTheme,
        pageSize: ExportPageSize,
        watermark: Bool
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "pdf",
            contentType: .pdf
        )

        var pageRect = CGRect(origin: .zero, size: pageSize.size)
        let body = makeAttributedBody(
            title: title,
            text: text,
            theme: theme,
            bodySize: 11,
            titleSize: 24
        )

        guard let context = CGContext(
            url as CFURL,
            mediaBox: &pageRect,
            nil
        ) else {
            throw ExportError.contextCreation
        }

        var range = CFRange(location: 0, length: 0)
        let framesetter = CTFramesetterCreateWithAttributedString(body)

        repeat {
            context.beginPDFPage(nil)

            // CGContext PDF coordinate system has the origin in the bottom-left.
            // Set the fill via the CGContext directly so it does not depend on
            // an active NSGraphicsContext (which is what NSColor.setFill needs).
            context.setFillColor(theme.backgroundColor.cgColor)
            context.fill(pageRect)

            // Build the layout path in PDF coordinates. CTFrame begins drawing
            // from the path's top edge by default, so the text reads top-down
            // without any axis flipping.
            let path = CGMutablePath()
            path.addRect(pageRect.insetBy(dx: 48, dy: 56))
            let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
            CTFrameDraw(frame, context)

            if watermark {
                drawWatermark(in: context, pageRect: pageRect, theme: theme)
            }

            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            range.location += visible.length
        } while range.location < body.length

        context.closePDF()
        return url
    }

    static func saveLongImage(
        title: String,
        text: String,
        theme: ExportTheme,
        width: ImageWidth,
        watermark: Bool
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "png",
            contentType: .png
        )
        let canvasWidth: CGFloat = width.width
        let horizontalPadding: CGFloat = canvasWidth * 0.066
        let contentWidth = canvasWidth - horizontalPadding * 2
        let bodyFontSize: CGFloat = canvasWidth >= 1080 ? 30 : 22
        let titleFontSize: CGFloat = canvasWidth >= 1080 ? 56 : 42

        let body = makeAttributedBody(
            title: title,
            text: text,
            theme: theme,
            bodySize: bodyFontSize,
            titleSize: titleFontSize
        )
        let measured = body.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let canvasHeight = max(canvasWidth * 1.0, measured.height + 220)
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        // Render through NSImage with a flipped lock focus. lockFocusFlipped
        // installs a graphics context whose origin sits at the top-left, so
        // both NSAttributedString.draw and NSColor fills cooperate without
        // any manual coordinate gymnastics.
        let image = NSImage(size: canvasSize)
        image.lockFocusFlipped(true)

        // The current graphics context is the one lockFocus just installed.
        guard let graphicsContext = NSGraphicsContext.current else {
            image.unlockFocus()
            throw ExportError.contextCreation
        }
        let flippedCG = graphicsContext.cgContext

        flippedCG.setFillColor(theme.backgroundColor.cgColor)
        flippedCG.fill(CGRect(origin: .zero, size: canvasSize))

        flippedCG.setFillColor(theme.accentColor.withAlphaComponent(0.20).cgColor)
        flippedCG.fill(CGRect(x: horizontalPadding, y: 64, width: 160, height: 12))

        let drawRect = CGRect(
            x: horizontalPadding,
            y: 100,
            width: contentWidth,
            height: measured.height + 40
        )
        body.draw(in: drawRect)

        if watermark {
            let watermarkAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
                .foregroundColor: theme.inkColor.withAlphaComponent(0.45)
            ]
            let watermarkText = NSAttributedString(
                string: "Made with MarkLens",
                attributes: watermarkAttributes
            )
            let watermarkSize = watermarkText.size()
            watermarkText.draw(at: CGPoint(
                x: canvasWidth - watermarkSize.width - horizontalPadding,
                y: canvasHeight - watermarkSize.height - 32
            ))
        }

        image.unlockFocus()

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.contextCreation
        }
        try pngData.write(to: url, options: .atomic)
        return url
    }

    static func saveHTML(
        title: String,
        text: String,
        theme: ExportTheme
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "html",
            contentType: .html
        )
        let html = makeHTMLDocument(title: title, text: text, theme: theme)
        try html.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func saveMarkdown(title: String, text: String) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "md",
            contentType: UTType("net.daringfireball.markdown") ?? .plainText
        )
        try text.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    static func copyRichText(title: String, text: String, style: ReadingMode) {
        let attributed = makeAttributedBody(
            title: title,
            text: text,
            theme: .paper,
            bodySize: 14,
            titleSize: 24
        )
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([attributed])
        flashStatus("已复制富文本")
    }

    static func copyPlainText(title: String, text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("\(title)\n\n\(text)", forType: .string)
        flashStatus("已复制纯文本")
    }

    private static func askSaveURL(
        title: String,
        extension ext: String,
        contentType: UTType
    ) throws -> URL {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(title).\(ext)"
        panel.title = "导出 \(ext.uppercased())"
        panel.prompt = "保存"

        if panel.runModal() == .OK, let url = panel.url {
            return url
        }
        throw ExportError.userCancelled
    }

    private static func sanitize(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Markdown" : cleaned
    }

    private static func makeAttributedBody(
        title: String,
        text: String,
        theme: ExportTheme,
        bodySize: CGFloat,
        titleSize: CGFloat
    ) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * 0.34
        paragraph.paragraphSpacing = bodySize * 0.55

        let attributed = NSMutableAttributedString(
            string: "\(title)\n\n\(text)",
            attributes: [
                .font: NSFont.systemFont(ofSize: bodySize, weight: .regular),
                .foregroundColor: theme.inkColor,
                .paragraphStyle: paragraph
            ]
        )
        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: titleSize, weight: .heavy),
                .foregroundColor: theme.accentColor
            ],
            range: NSRange(location: 0, length: (title as NSString).length)
        )
        return attributed
    }

    private static func drawWatermark(in context: CGContext, pageRect: CGRect, theme: ExportTheme) {
        // Draw the watermark using Core Text directly so we never depend on
        // the AppKit drawing stack inside a PDF (which has the bottom-left
        // origin and no NSGraphicsContext).
        let attributed = CFAttributedStringCreate(
            nil,
            "Made with MarkLens" as CFString,
            [
                kCTFontAttributeName: CTFontCreateWithName("HelveticaNeue" as CFString, 9, nil),
                kCTForegroundColorAttributeName: theme.inkColor.withAlphaComponent(0.45).cgColor
            ] as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetImageBounds(line, context)

        context.saveGState()
        context.textPosition = CGPoint(
            x: pageRect.maxX - bounds.width - 36,
            y: 28
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func makeHTMLDocument(
        title: String,
        text: String,
        theme: ExportTheme
    ) -> String {
        let escapedTitle = htmlEscape(title)
        let renderedBody = renderMarkdownToHTML(text)
        let css = htmlStylesheet(for: theme)
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        <style>\(css)</style>
        </head>
        <body>
        <main class="page">
        <h1 class="brand">\(escapedTitle)</h1>
        \(renderedBody)
        <footer>Made with MarkLens · Markdown Reader & Presenter</footer>
        </main>
        </body>
        </html>
        """
    }

    private static func htmlStylesheet(for theme: ExportTheme) -> String {
        let bg = htmlColor(theme.backgroundColor)
        let ink = htmlColor(theme.inkColor)
        let accent = htmlColor(theme.accentColor)
        return """
        :root { color-scheme: light; }
        body { margin: 0; background: \(bg); font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Microsoft YaHei", sans-serif; color: \(ink); }
        .page { max-width: 760px; margin: 48px auto; padding: 32px 40px 64px; background: #fff; border-radius: 18px; box-shadow: 0 18px 48px rgba(0,0,0,0.08); }
        .brand { font-weight: 800; font-size: 2.0em; color: \(accent); border-bottom: 2px solid \(accent); padding-bottom: 12px; margin-top: 0; }
        h1, h2, h3, h4, h5, h6 { color: \(ink); line-height: 1.32; }
        h2 { border-bottom: 1px solid rgba(0,0,0,0.08); padding-bottom: 6px; }
        p { line-height: 1.78; font-size: 16px; }
        blockquote { margin: 0 0 16px; padding: 12px 18px; background: rgba(0,0,0,0.04); border-left: 4px solid \(accent); border-radius: 8px; color: rgba(0,0,0,0.78); }
        code { font-family: ui-monospace, "SF Mono", Menlo, monospace; background: rgba(0,0,0,0.06); padding: 2px 6px; border-radius: 4px; font-size: 0.92em; }
        pre { background: rgba(0,0,0,0.05); padding: 16px; border-radius: 12px; overflow-x: auto; }
        pre code { background: transparent; padding: 0; }
        table { border-collapse: collapse; width: 100%; margin: 16px 0; }
        th, td { border: 1px solid rgba(0,0,0,0.10); padding: 8px 12px; text-align: left; }
        th { background: rgba(0,0,0,0.04); }
        a { color: \(accent); }
        ul, ol { line-height: 1.78; padding-left: 1.4em; }
        hr { border: 0; border-top: 1px solid rgba(0,0,0,0.10); margin: 28px 0; }
        footer { text-align: center; font-size: 12px; color: rgba(0,0,0,0.45); margin-top: 32px; }
        """
    }

    private static func htmlColor(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Lightweight Markdown → HTML conversion that covers the common cases
    /// (headings, paragraphs, fenced code, blockquote, lists, inline code,
    /// emphasis, links). Heavy parser features such as tables and footnotes
    /// fall back to plain text inside paragraphs to keep the dependency
    /// surface small for the export pipeline.
    private static func renderMarkdownToHTML(_ source: String) -> String {
        var html = ""
        var inFence = false
        var fenceBuffer: [String] = []
        var fenceLanguage = ""
        var paragraphBuffer: [String] = []
        var listBuffer: [String] = []
        var listType: String? = nil

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphBuffer.removeAll()
            guard !joined.isEmpty else { return }
            html += "<p>\(applyInlineFormatting(joined))</p>\n"
        }

        func flushList() {
            guard let type = listType, !listBuffer.isEmpty else { return }
            html += "<\(type)>\n"
            for item in listBuffer {
                html += "  <li>\(applyInlineFormatting(item))</li>\n"
            }
            html += "</\(type)>\n"
            listBuffer.removeAll()
            listType = nil
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inFence {
                    let code = fenceBuffer.joined(separator: "\n")
                    let escaped = htmlEscape(code)
                    let lang = fenceLanguage.isEmpty ? "" : " class=\"language-\(htmlEscape(fenceLanguage))\""
                    html += "<pre><code\(lang)>\(escaped)</code></pre>\n"
                    fenceBuffer.removeAll()
                    fenceLanguage = ""
                    inFence = false
                } else {
                    flushParagraph()
                    flushList()
                    fenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inFence = true
                }
                continue
            }

            if inFence {
                fenceBuffer.append(line)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                flushList()
                let title = String(trimmed.dropFirst(hashes + 1))
                html += "<h\(hashes)>\(applyInlineFormatting(title))</h\(hashes)>\n"
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushList()
                let body = String(trimmed.dropFirst(2))
                html += "<blockquote>\(applyInlineFormatting(body))</blockquote>\n"
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                if listType != nil && listType != "ul" {
                    flushList()
                }
                listType = "ul"
                listBuffer.append(String(trimmed.dropFirst(2)))
                continue
            }

            if trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                flushParagraph()
                if listType != nil && listType != "ol" {
                    flushList()
                }
                listType = "ol"
                if let dotIndex = trimmed.firstIndex(of: ".") {
                    let after = trimmed.index(after: dotIndex)
                    listBuffer.append(trimmed[after...].trimmingCharacters(in: .whitespaces))
                }
                continue
            }

            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") {
                flushParagraph()
                flushList()
                html += "<hr/>\n"
                continue
            }

            paragraphBuffer.append(line.trimmingCharacters(in: .whitespaces))
        }

        flushParagraph()
        flushList()
        if inFence {
            let code = fenceBuffer.joined(separator: "\n")
            html += "<pre><code>\(htmlEscape(code))</code></pre>\n"
        }
        return html
    }

    private static func applyInlineFormatting(_ raw: String) -> String {
        var output = htmlEscape(raw)
        output = applyRegex(output, pattern: #"`([^`]+)`"#, template: "<code>$1</code>")
        output = applyRegex(output, pattern: #"\*\*([^*]+)\*\*"#, template: "<strong>$1</strong>")
        output = applyRegex(output, pattern: #"\*([^*]+)\*"#, template: "<em>$1</em>")
        output = applyRegex(output, pattern: #"~~([^~]+)~~"#, template: "<del>$1</del>")
        output = applyRegex(output, pattern: #"\[([^\]]+)\]\(([^\)]+)\)"#, template: "<a href=\"$2\">$1</a>")
        return output
    }

    private static func applyRegex(_ value: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, range: range, withTemplate: template)
    }

    private static func flashStatus(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = message
        alert.runModal()
    }
}

enum ExportTheme: String, CaseIterable, Identifiable {
    case paper
    case report
    case note
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: "纸张"
        case .report: "报告"
        case .note: "手记"
        case .card: "卡片"
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .paper: NSColor(red: 0.985, green: 0.970, blue: 0.925, alpha: 1)
        case .report: NSColor(red: 0.950, green: 0.955, blue: 0.985, alpha: 1)
        case .note: NSColor(red: 0.930, green: 0.965, blue: 0.955, alpha: 1)
        case .card: NSColor(red: 0.980, green: 0.940, blue: 0.900, alpha: 1)
        }
    }

    var inkColor: NSColor {
        NSColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    }

    var accentColor: NSColor {
        switch self {
        case .paper: NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1)
        case .report: NSColor(red: 0.42, green: 0.30, blue: 0.56, alpha: 1)
        case .note: NSColor(red: 0.22, green: 0.42, blue: 0.455, alpha: 1)
        case .card: NSColor(red: 0.58, green: 0.31, blue: 0.18, alpha: 1)
        }
    }
}

enum ExportError: LocalizedError {
    case userCancelled
    case contextCreation

    var errorDescription: String? {
        switch self {
        case .userCancelled: "已取消"
        case .contextCreation: "创建导出上下文失败"
        }
    }
}
