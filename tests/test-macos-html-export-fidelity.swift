// Headless source-level check for macOS HTML export fidelity.
//
// The HTML exporter is intentionally lightweight, but it should not turn
// Markdown images into broken "!<a>" links, and the export panel should not
// promise a fully offline document while Mermaid still uses a CDN runtime.

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let exportURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Export/ExportRunner.swift")
let panelURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Export/ExportPanel.swift")

let exportSource = try String(contentsOf: exportURL, encoding: .utf8)
let panelSource = try String(contentsOf: panelURL, encoding: .utf8)

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        failures.append(message)
    }
}

expect(exportSource.contains("sourceURL: URL?"), "HTML export receives the source document URL")
expect(exportSource.contains("makeHTMLDocument(title: title, text: text, theme: theme, sourceURL: sourceURL)"), "HTML export passes sourceURL into the renderer")
expect(exportSource.contains("renderMarkdownToHTML(text, baseURL: sourceURL?.deletingLastPathComponent())"), "HTML renderer resolves relative resources from the Markdown file")
expect(exportSource.contains("applyImageFormatting"), "HTML inline formatting handles Markdown image syntax before links")
expect(exportSource.contains(#"pattern: #"(?<!!)\[([^\]]+)\]\(([^\)]+)\)""#), "HTML link regex excludes Markdown images")
expect(exportSource.contains("<img src=\\\""), "HTML exporter emits real image tags")
expect(exportSource.contains("dataURLForImage"), "HTML exporter can embed local images as data URLs")
expect(exportSource.contains("maxHTMLInlineImageBytes"), "HTML exporter caps embedded image size")
expect(exportSource.contains("preferredMIMEType"), "HTML exporter preserves image MIME types")
expect(exportSource.contains("img { max-width: 100%; height: auto;"), "HTML stylesheet keeps exported images within the page")
expect(panelSource.contains("sourceURL: sourceURL"), "Export panel passes sourceURL to HTML export")
expect(!panelSource.contains("离线 HTML 文档"), "Export panel no longer over-promises full offline HTML while Mermaid uses CDN")
expect(panelSource.contains("Mermaid 图表需要网络加载运行时"), "Export panel discloses the Mermaid runtime limitation")

if failures.isEmpty {
    print("All macOS HTML export fidelity checks passed.")
} else {
    print("\nFailures: \(failures.count)")
    exit(1)
}
