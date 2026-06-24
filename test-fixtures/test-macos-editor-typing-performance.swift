// Headless source-level check for macOS editor typing performance.
//
// Typing should not run full-document Markdown normalization on every
// NSTextView change. Normalization still happens at the document container
// debounce boundary, but the keystroke path should only move the raw string
// into SwiftUI state.

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let editorURL = repoRoot.appendingPathComponent("MarkdownReaderMac/Features/Editor/EditorWorkspace.swift")
let source = try String(contentsOf: editorURL, encoding: .utf8)

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        failures.append(message)
    }
}

expect(source.contains("func textDidChange"), "test can locate the NSTextView change handler")
expect(source.contains("text = textView.string"), "keystroke path writes the raw editor string")
expect(!source.contains("let normalized = MarkdownSection.normalize(textView.string)"), "keystroke path does not normalize the full document")
expect(!source.contains("textView.string = normalized"), "keystroke path does not rewrite the text view content")
expect(source.contains("private var nonWhitespaceCount"), "toolbar computes character stats without allocating a filtered string")
expect(!source.contains("text.filter { !$0.isWhitespace }.count"), "toolbar avoids filter allocation for long documents")

if failures.isEmpty {
    print("All macOS editor typing performance checks passed.")
} else {
    print("\nFailures: \(failures.count)")
    exit(1)
}
