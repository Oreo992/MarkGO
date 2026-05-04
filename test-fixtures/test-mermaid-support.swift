// Headless source-level check for Mermaid rendering support.
//
// Run: swift test-fixtures/test-mermaid-support.swift

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let themeURL = repoRoot.appendingPathComponent("MarkdownReaderMac/Design/MarkdownTheme+Custom.swift")
let source = try String(contentsOf: themeURL, encoding: .utf8)
let exportURL = repoRoot.appendingPathComponent("MarkdownReaderMac/Features/Export/ExportRunner.swift")
let exportSource = try String(contentsOf: exportURL, encoding: .utf8)

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        exit(1)
    }
}

expect(source.contains("import WebKit"), "macOS Markdown theme can host a Mermaid WebView")
expect(source.contains("MermaidBlockView"), "Mermaid code blocks use a dedicated diagram view")
expect(source.contains("isMermaidLanguage"), "Mermaid language aliases are detected explicitly")
expect(source.contains("cdn.jsdelivr.net/npm/mermaid"), "Mermaid renderer loads the Mermaid runtime")
expect(source.contains("renderMermaid: Bool = true"), "Mermaid rendering can be disabled for bitmap exports")
expect(!source.contains("crypto.randomUUID"), "Mermaid renderer avoids crypto.randomUUID for WKWebView compatibility")
expect(source.contains("makeDiagramId"), "Mermaid renderer uses a local compatible diagram id")
expect(source.contains("@State private var zoom"), "Mermaid blocks keep local zoom state")
expect(source.contains("setZoom"), "Mermaid WebView can zoom without reloading the diagram")
expect(source.contains("minimumScale") && source.contains("maximumScale"), "Mermaid zoom has sensible limits")
expect(source.contains("overflow: auto"), "Mermaid WebView allows scrolling when diagrams are zoomed")
expect(source.contains("websiteDataStore = .default()"), "Mermaid WebViews use the default data store so the runtime can be cached")
expect(source.contains("plus.magnifyingglass") && source.contains("minus.magnifyingglass"), "Mermaid blocks expose zoom buttons")
expect(exportSource.contains("renderMermaid: false"), "PDF and long-image exports avoid blank async WebView snapshots")
expect(exportSource.contains("containsMermaidFence"), "HTML export detects Mermaid fences")
expect(exportSource.contains("<div class=\\\"mermaid\\\">"), "HTML export emits Mermaid diagram containers")
