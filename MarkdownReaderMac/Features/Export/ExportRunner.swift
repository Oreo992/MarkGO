import AppKit
import CoreText
import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers

/// Runs the actual export by drawing into PDF, PNG, or HTML targets and
/// presenting the system save panel. Mirrors the iOS rendering rules so
/// exports look like the same brand artifact regardless of platform.
@MainActor
enum ExportRunner {
    private static let maxHTMLInlineImageBytes = 8 * 1_024 * 1_024

    static func savePDF(
        title: String,
        text: String,
        theme: ExportTheme,
        pageSize: ExportPageSize,
        sourceURL: URL?,
        watermark: Bool
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "pdf",
            contentType: .pdf
        )
        try writePDF(
            to: url,
            title: title,
            text: text,
            theme: theme,
            pageSize: pageSize,
            sourceURL: sourceURL,
            watermark: watermark
        )
        return url
    }

    static func writePDF(
        to url: URL,
        title: String,
        text: String,
        theme: ExportTheme,
        pageSize: ExportPageSize,
        sourceURL: URL?,
        watermark: Bool
    ) throws {
        let hostingView = makeRenderedMarkdownHostingView(
            title: title,
            text: text,
            theme: theme,
            canvasWidth: pageSize.size.width * 2,
            sourceURL: sourceURL,
            watermark: watermark
        )
        let imageSize = hostingView.bounds.size
        var pageRect = CGRect(origin: .zero, size: pageSize.size)

        guard let context = CGContext(
            url as CFURL,
            mediaBox: &pageRect,
            nil
        ) else {
            throw ExportError.contextCreation
        }

        let outputScale = pageSize.size.width / max(1, imageSize.width)
        let maxSliceHeight = pageSize.size.height / max(0.01, outputScale)
        var sourceY: CGFloat = 0

        while sourceY < imageSize.height {
            context.beginPDFPage(nil)

            context.setFillColor(theme.backgroundColor.cgColor)
            context.fill(pageRect)

            let remainingHeight = imageSize.height - sourceY
            let sliceHeight = nextPDFSliceHeight(
                hostingView: hostingView,
                sourceY: sourceY,
                maxHeight: min(maxSliceHeight, remainingHeight),
                remainingHeight: remainingHeight,
                backgroundColor: theme.backgroundColor
            )
            let sliceRect = viewRectFromTop(sourceY: sourceY, height: sliceHeight, in: hostingView)

            if let bitmap = renderSliceBitmap(hostingView: hostingView, rect: sliceRect),
               let slice = bitmap.cgImage {
                let drawnHeight = sliceHeight * outputScale
                context.draw(
                    slice,
                    in: CGRect(
                        x: 0,
                        y: pageSize.size.height - drawnHeight,
                        width: pageSize.size.width,
                        height: drawnHeight
                    )
                )
            }

            if watermark {
                drawWatermark(in: context, pageRect: pageRect, theme: theme)
            }

            context.endPDFPage()
            sourceY += max(1, sliceHeight)
        }

        context.closePDF()
    }

    static func saveLongImage(
        title: String,
        text: String,
        theme: ExportTheme,
        width: ImageWidth,
        sourceURL: URL?,
        watermark: Bool
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "png",
            contentType: .png
        )
        try writeLongImage(
            to: url,
            title: title,
            text: text,
            theme: theme,
            width: width,
            sourceURL: sourceURL,
            watermark: watermark
        )
        return url
    }

    static func writeLongImage(
        to url: URL,
        title: String,
        text: String,
        theme: ExportTheme,
        width: ImageWidth,
        sourceURL: URL?,
        watermark: Bool
    ) throws {
        let canvasWidth: CGFloat = width.width
        let image = try makeRenderedMarkdownImage(
            title: title,
            text: text,
            theme: theme,
            canvasWidth: canvasWidth,
            sourceURL: sourceURL,
            watermark: watermark
        )

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.contextCreation
        }
        try pngData.write(to: url, options: .atomic)
    }

    static func saveHTML(
        title: String,
        text: String,
        theme: ExportTheme,
        sourceURL: URL?
    ) throws -> URL {
        let url = try askSaveURL(
            title: sanitize(title),
            extension: "html",
            contentType: .html
        )
        try writeHTML(to: url, title: title, text: text, theme: theme, sourceURL: sourceURL)
        return url
    }

    static func writeHTML(
        to url: URL,
        title: String,
        text: String,
        theme: ExportTheme,
        sourceURL: URL?
    ) throws {
        let html = makeHTMLDocument(title: title, text: text, theme: theme, sourceURL: sourceURL)
        try html.write(to: url, atomically: true, encoding: .utf8)
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

    private static func makeRenderedMarkdownImage(
        title: String,
        text: String,
        theme: ExportTheme,
        canvasWidth: CGFloat,
        sourceURL: URL?,
        watermark: Bool
    ) throws -> NSImage {
        let hostingView = makeRenderedMarkdownHostingView(
            title: title,
            text: text,
            theme: theme,
            canvasWidth: canvasWidth,
            sourceURL: sourceURL,
            watermark: watermark
        )

        guard let bitmap = makeBitmapImageRepForExport(size: hostingView.bounds.size) else {
            throw ExportError.contextCreation
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        let image = NSImage(size: hostingView.bounds.size)
        image.addRepresentation(bitmap)
        return image
    }

    private static func makeBitmapImageRepForExport(size: CGSize) -> NSBitmapImageRep? {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(size.width.rounded(.up))),
            pixelsHigh: max(1, Int(size.height.rounded(.up))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        bitmap?.size = size
        return bitmap
    }

    private static func makeRenderedMarkdownHostingView(
        title: String,
        text: String,
        theme: ExportTheme,
        canvasWidth: CGFloat,
        sourceURL: URL?,
        watermark: Bool
    ) -> NSHostingView<ExportMarkdownDocumentView> {
        let content = ExportMarkdownDocumentView(
            title: title,
            text: MarkdownSection.normalize(text),
            theme: theme,
            canvasWidth: canvasWidth,
            sourceURL: sourceURL,
            watermark: watermark
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = CGRect(x: 0, y: 0, width: canvasWidth, height: 10)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let canvasHeight = max(canvasWidth * 1.0, ceil(fittingSize.height))
        hostingView.frame = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    private static func nextPDFSliceHeight(
        hostingView: NSView,
        sourceY: CGFloat,
        maxHeight: CGFloat,
        remainingHeight: CGFloat,
        backgroundColor: NSColor
    ) -> CGFloat {
        guard remainingHeight > maxHeight else { return remainingHeight }

        let minimumHeight = max(240, maxHeight * 0.62)
        let searchStart = max(minimumHeight, maxHeight * 0.74)
        let searchEnd = max(searchStart, maxHeight * 0.98)
        var bestHeight = maxHeight
        var bestScore = 0.0

        var candidate = searchEnd
        while candidate >= searchStart {
            let score = whitespaceScore(
                hostingView: hostingView,
                sourceY: sourceY + candidate,
                backgroundColor: backgroundColor
            )

            if score > bestScore {
                bestScore = score
                bestHeight = candidate
            }
            if score > 0.96 {
                return candidate
            }
            candidate -= 10
        }

        return bestScore > 0.82 ? bestHeight : maxHeight
    }

    private static func whitespaceScore(
        hostingView: NSView,
        sourceY: CGFloat,
        backgroundColor: NSColor
    ) -> Double {
        let background = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        let bandY = max(0, sourceY - 5)
        let bandHeight = min(11, max(0, hostingView.bounds.height - bandY))
        guard bandHeight > 0 else { return 0 }

        let rect = viewRectFromTop(sourceY: bandY, height: bandHeight, in: hostingView)
        guard let bitmap = renderSliceBitmap(hostingView: hostingView, rect: rect) else { return 0 }

        let yStart = 0
        let yEnd = bitmap.pixelsHigh - 1
        let xStep = max(1, bitmap.pixelsWide / 44)
        var samples = 0
        var matches = 0

        guard yStart <= yEnd else { return 0 }

        for y in yStart...yEnd {
            var x = 0
            while x < bitmap.pixelsWide {
                samples += 1
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    let delta = abs(color.redComponent - background.redComponent)
                        + abs(color.greenComponent - background.greenComponent)
                        + abs(color.blueComponent - background.blueComponent)
                    if delta < 0.18 {
                        matches += 1
                    }
                }
                x += xStep
            }
        }

        guard samples > 0 else { return 0 }
        return Double(matches) / Double(samples)
    }

    private static func renderSliceBitmap(hostingView: NSView, rect: CGRect) -> NSBitmapImageRep? {
        guard !rect.isEmpty,
              let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: rect) else {
            return nil
        }
        bitmap.size = rect.size
        hostingView.cacheDisplay(in: rect, to: bitmap)
        return bitmap
    }

    private static func viewRectFromTop(sourceY: CGFloat, height: CGFloat, in hostingView: NSView) -> CGRect {
        let bounds = hostingView.bounds
        let clampedTop = min(max(0, sourceY), bounds.height)
        let clampedHeight = min(max(1, height), max(1, bounds.height - clampedTop))
        let y = hostingView.isFlipped
            ? clampedTop
            : bounds.height - clampedTop - clampedHeight
        return CGRect(
            x: bounds.minX,
            y: y,
            width: bounds.width,
            height: clampedHeight
        ).integral
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
        switch theme {
        case .report:
            paragraph.lineSpacing = bodySize * 0.50
            paragraph.paragraphSpacing = bodySize * 0.88
        case .lesson:
            paragraph.lineSpacing = bodySize * 0.44
            paragraph.paragraphSpacing = bodySize * 0.72
        case .card:
            paragraph.lineSpacing = bodySize * 0.40
            paragraph.paragraphSpacing = bodySize * 0.78
        default:
            paragraph.lineSpacing = bodySize * 0.34
            paragraph.paragraphSpacing = bodySize * 0.55
        }

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
            "Made with MarkGo" as CFString,
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
        theme: ExportTheme,
        sourceURL: URL?
    ) -> String {
        let escapedTitle = htmlEscape(title)
        let renderedBody = renderMarkdownToHTML(text, baseURL: sourceURL?.deletingLastPathComponent())
        let css = htmlStylesheet(for: theme)
        let mermaidRuntime = containsMermaidFence(text) ? htmlMermaidRuntime() : ""
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
        <footer>Made with MarkGo · Markdown Reader & Presenter</footer>
        </main>
        \(mermaidRuntime)
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
        .mermaid { overflow-x: auto; padding: 18px; margin: 18px 0; background: rgba(255,255,255,0.55); border: 1px solid rgba(0,0,0,0.08); border-radius: 14px; }
        .mermaid svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
        img { max-width: 100%; height: auto; border-radius: 12px; display: block; margin: 16px 0; }
        table { border-collapse: collapse; width: 100%; margin: 16px 0; }
        th, td { border: 1px solid rgba(0,0,0,0.10); padding: 8px 12px; text-align: left; }
        th { background: rgba(0,0,0,0.04); }
        a { color: \(accent); }
        ul, ol { line-height: 1.78; padding-left: 1.4em; }
        hr { border: 0; border-top: 1px solid rgba(0,0,0,0.10); margin: 28px 0; }
        footer { text-align: center; font-size: 12px; color: rgba(0,0,0,0.45); margin-top: 32px; }
        """
    }

    private static func containsMermaidFence(_ source: String) -> Bool {
        source.range(of: #"(?m)^```\s*(mermaid|mmd)\s*$"#, options: .regularExpression) != nil
    }

    private static func htmlMermaidRuntime() -> String {
        """
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>
        mermaid.initialize({
          startOnLoad: true,
          securityLevel: "strict",
          theme: "base",
          themeVariables: {
            fontFamily: "-apple-system, BlinkMacSystemFont, PingFang SC, sans-serif",
            primaryColor: "#e7f7f4",
            primaryTextColor: "#1d2324",
            primaryBorderColor: "#18b7ad",
            lineColor: "#18b7ad"
          }
        });
        </script>
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
    private static func renderMarkdownToHTML(_ source: String, baseURL: URL?) -> String {
        var html = ""
        var inFence = false
        var fenceBuffer: [String] = []
        var fenceLanguage = ""
        var paragraphBuffer: [String] = []
        var listBuffer: [String] = []
        var listType: String? = nil
        var tableBuffer: [String] = []

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphBuffer.removeAll()
            guard !joined.isEmpty else { return }
            html += "<p>\(applyInlineFormatting(joined, baseURL: baseURL))</p>\n"
        }

        func flushList() {
            guard let type = listType, !listBuffer.isEmpty else { return }
            html += "<\(type)>\n"
            for item in listBuffer {
                html += "  <li>\(applyInlineFormatting(item, baseURL: baseURL))</li>\n"
            }
            html += "</\(type)>\n"
            listBuffer.removeAll()
            listType = nil
        }

        func tableCells(in row: String) -> [String] {
            var body = row.trimmingCharacters(in: .whitespaces)
            if body.first == "|" { body.removeFirst() }
            if body.last == "|" { body.removeLast() }
            return body
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }

        func isTableSeparator(_ row: String) -> Bool {
            let cells = tableCells(in: row)
            guard !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
            }
        }

        func flushTable() {
            guard !tableBuffer.isEmpty else { return }
            defer { tableBuffer.removeAll() }
            guard tableBuffer.count >= 2, isTableSeparator(tableBuffer[1]) else {
                paragraphBuffer.append(contentsOf: tableBuffer)
                return
            }

            let header = tableCells(in: tableBuffer[0])
            let rows = tableBuffer.dropFirst(2).map(tableCells)
            html += "<table>\n<thead><tr>"
            for cell in header {
                html += "<th>\(applyInlineFormatting(cell, baseURL: baseURL))</th>"
            }
            html += "</tr></thead>\n<tbody>\n"
            for row in rows {
                html += "<tr>"
                for cell in row {
                    html += "<td>\(applyInlineFormatting(cell, baseURL: baseURL))</td>"
                }
                html += "</tr>\n"
            }
            html += "</tbody>\n</table>\n"
        }

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inFence {
                    let code = fenceBuffer.joined(separator: "\n")
                    let escaped = htmlEscape(code)
                    if isMermaidLanguage(fenceLanguage) {
                        html += "<div class=\"mermaid\">\(escaped)</div>\n"
                    } else {
                        let lang = fenceLanguage.isEmpty ? "" : " class=\"language-\(htmlEscape(fenceLanguage))\""
                        html += "<pre><code\(lang)>\(escaped)</code></pre>\n"
                    }
                    fenceBuffer.removeAll()
                    fenceLanguage = ""
                    inFence = false
                } else {
                    flushTable()
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
                flushTable()
                flushParagraph()
                flushList()
                continue
            }

            if trimmed.hasPrefix("|"), trimmed.hasSuffix("|") {
                flushParagraph()
                flushList()
                tableBuffer.append(trimmed)
                continue
            } else {
                flushTable()
            }

            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flushParagraph()
                flushList()
                let title = String(trimmed.dropFirst(hashes + 1))
                html += "<h\(hashes)>\(applyInlineFormatting(title, baseURL: baseURL))</h\(hashes)>\n"
                continue
            }

            if trimmed.hasPrefix("> ") {
                flushParagraph()
                flushList()
                let body = String(trimmed.dropFirst(2))
                html += "<blockquote>\(applyInlineFormatting(body, baseURL: baseURL))</blockquote>\n"
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

        flushTable()
        flushParagraph()
        flushList()
        if inFence {
            let code = fenceBuffer.joined(separator: "\n")
            if isMermaidLanguage(fenceLanguage) {
                html += "<div class=\"mermaid\">\(htmlEscape(code))</div>\n"
            } else {
                html += "<pre><code>\(htmlEscape(code))</code></pre>\n"
            }
        }
        return html
    }

    private static func applyInlineFormatting(_ raw: String, baseURL: URL?) -> String {
        var output = htmlEscape(raw)
        output = applyImageFormatting(output, baseURL: baseURL)
        output = applyRegex(output, pattern: #"`([^`]+)`"#, template: "<code>$1</code>")
        output = applyRegex(output, pattern: #"\*\*([^*]+)\*\*"#, template: "<strong>$1</strong>")
        output = applyRegex(output, pattern: #"\*([^*]+)\*"#, template: "<em>$1</em>")
        output = applyRegex(output, pattern: #"~~([^~]+)~~"#, template: "<del>$1</del>")
        output = applyRegex(output, pattern: #"(?<!!)\[([^\]]+)\]\(([^\)]+)\)"#, template: "<a href=\"$2\">$1</a>")
        return output
    }

    private static func applyImageFormatting(_ value: String, baseURL: URL?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#) else { return value }
        let fullRange = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: fullRange)
        guard !matches.isEmpty else { return value }

        var output = value
        for match in matches.reversed() {
            let nsOutput = output as NSString
            let alt = nsOutput.substring(with: match.range(at: 1))
            let destination = htmlUnescape(nsOutput.substring(with: match.range(at: 2)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let source = htmlImageSource(for: destination, baseURL: baseURL)
            let replacement = "<img src=\"\(htmlEscape(source))\" alt=\"\(alt)\">"
            output = nsOutput.replacingCharacters(in: match.range, with: replacement)
        }
        return output
    }

    private static func htmlImageSource(for destination: String, baseURL: URL?) -> String {
        let cleaned = stripAngleBrackets(destination)
        if let url = URL(string: cleaned), let scheme = url.scheme, !scheme.isEmpty {
            if url.isFileURL, let dataURL = dataURLForImage(at: url) {
                return dataURL
            }
            return cleaned
        }

        if let url = resolveHTMLResourceURL(cleaned, baseURL: baseURL),
           let dataURL = dataURLForImage(at: url) {
            return dataURL
        }
        return cleaned
    }

    private static func resolveHTMLResourceURL(_ destination: String, baseURL: URL?) -> URL? {
        let path = (destination.removingPercentEncoding ?? destination)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    private static func dataURLForImage(at url: URL) -> String? {
        guard url.isFileURL else { return nil }
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) <= maxHTMLInlineImageBytes,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func stripAngleBrackets(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<"), trimmed.hasSuffix(">") {
            return String(trimmed.dropFirst().dropLast())
        }
        return trimmed
    }

    private static func htmlUnescape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
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

private struct ExportMarkdownDocumentView: View {
    let title: String
    let text: String
    let theme: ExportTheme
    let canvasWidth: CGFloat
    let sourceURL: URL?
    let watermark: Bool

    private var horizontalPadding: CGFloat {
        canvasWidth * 0.066
    }

    private var scale: CGFloat {
        canvasWidth >= 1080 ? 1.78 : 1.32
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Capsule()
                .fill(Color(theme.accentColor).opacity(0.20))
                .frame(width: min(180, canvasWidth * 0.16), height: 12)

            Text(title)
                .font(.system(size: canvasWidth >= 1080 ? 56 : 42, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(theme.accentColor))
                .fixedSize(horizontal: false, vertical: true)

            Markdown(text, baseURL: baseURL, imageBaseURL: baseURL)
                .markdownTheme(.reader(mode: theme.readingMode, scale: scale, includeCodeCopy: false, renderMermaid: false))
                .markdownImageProvider(ExportMarkdownImageProvider())
                .markdownInlineImageProvider(ExportMarkdownInlineImageProvider())
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if watermark {
                HStack {
                    Spacer()
                    Text("Made with MarkGo")
                        .font(.system(size: canvasWidth >= 1080 ? 18 : 14, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor).opacity(0.45))
                }
                .padding(.top, 18)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, canvasWidth >= 1080 ? 72 : 56)
        .padding(.bottom, canvasWidth >= 1080 ? 84 : 64)
        .frame(width: canvasWidth, alignment: .topLeading)
        .background(Color(theme.backgroundColor))
    }

    private var baseURL: URL? {
        sourceURL?.deletingLastPathComponent()
    }
}

private struct ExportMarkdownImageProvider: ImageProvider {
    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let image = MarkdownImageCache.shared.image(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DefaultImageProvider.default.makeImage(url: url)
        }
    }
}

private struct ExportMarkdownInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        if let image = MarkdownImageCache.shared.image(for: url) {
            return Image(nsImage: image)
        }
        return try await DefaultInlineImageProvider.default.image(with: url, label: label)
    }
}

enum ExportTheme: String, CaseIterable, Identifiable {
    case clear
    case paper
    case report
    case lesson
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "清读"
        case .paper: "纸张"
        case .report: "报告"
        case .lesson: "讲义"
        case .card: "卡片"
        }
    }

    var backgroundColor: NSColor {
        switch self {
        case .clear: NSColor(red: 0.965, green: 0.948, blue: 0.910, alpha: 1)
        case .paper: NSColor(red: 0.985, green: 0.970, blue: 0.925, alpha: 1)
        case .report: NSColor(red: 0.950, green: 0.955, blue: 0.985, alpha: 1)
        case .lesson: NSColor(red: 0.965, green: 0.945, blue: 0.885, alpha: 1)
        case .card: NSColor(red: 0.980, green: 0.940, blue: 0.900, alpha: 1)
        }
    }

    var inkColor: NSColor {
        NSColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    }

    var accentColor: NSColor {
        switch self {
        case .clear: NSColor(red: 0.22, green: 0.42, blue: 0.455, alpha: 1)
        case .paper: NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1)
        case .report: NSColor(red: 0.42, green: 0.30, blue: 0.56, alpha: 1)
        case .lesson: NSColor(red: 0.815, green: 0.610, blue: 0.235, alpha: 1)
        case .card: NSColor(red: 0.58, green: 0.31, blue: 0.18, alpha: 1)
        }
    }

    var readingMode: ReadingMode {
        switch self {
        case .clear: .clear
        case .paper: .paper
        case .report: .report
        case .lesson: .lesson
        case .card: .cards
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
