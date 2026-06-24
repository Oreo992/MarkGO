// Headless source-level checks for iOS reader performance parity.
//
// Run: swift tests/test-ios-performance-parity.swift

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let contentURL = repoRoot.appendingPathComponent("platforms/ios/MarkGo/Features/Reader/ContentView.swift")
let source = try String(contentsOf: contentURL, encoding: .utf8)

func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        exit(1)
    }
}

expect(
    source.contains("@State private var analysis: MarkdownAnalysis = MarkdownAnalysis(text: \"\")"),
    "iOS reader caches MarkdownAnalysis outside SwiftUI body"
)
expect(
    source.contains(".task(id: document.text)") && source.contains("120_000_000"),
    "iOS reader debounces MarkdownAnalysis refresh while editing"
)
expect(
    !source.contains("private var analysis: MarkdownAnalysis {\n        MarkdownAnalysis(text: document.text)\n    }"),
    "iOS reader no longer recomputes MarkdownAnalysis from a computed body property"
)
expect(
    source.contains("LazyVStack"),
    "iOS reader lazily realizes long Markdown section lists"
)
expect(
    source.contains("private struct MarkdownSectionView: View, Equatable"),
    "iOS Markdown section views are Equatable"
)
expect(
    source.contains("private struct MarkdownSectionCard: View, Equatable"),
    "iOS Markdown card views are Equatable"
)
expect(
    source.contains(".equatable()"),
    "iOS reader marks expensive Markdown section subtrees as equatable"
)
expect(
    source.contains("private final class ReadingPositionCoordinator"),
    "iOS reader debounces reading-position persistence"
)
expect(
    source.contains("Task.sleep(nanoseconds: 700_000_000)"),
    "iOS reading-position writes wait for scrolling to settle"
)
