// Quick standalone test driver for MarkdownAnalysis.
// Run with: swift test-fixtures/test-markdown-analysis.swift
//
// Verifies heading detection, fenced-code awareness, and section grouping
// without spinning up Xcode tests.

import Foundation

// Minimal copies of the production types so this script is self-contained.
struct MarkdownHeading {
    let id: String
    let sectionID: String
    let level: Int
    let title: String
}

struct MarkdownSection {
    let id: String
    let heading: MarkdownHeading?
    let markdown: String

    static func parse(_ text: String) -> [MarkdownSection] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [MarkdownSection] = []
        var currentLines: [String] = []
        var currentHeading: MarkdownHeading?
        var sectionIndex = 0
        var inFence = false

        func flush() {
            let markdown = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { return }
            let id = currentHeading?.sectionID ?? "section-\(sectionIndex)"
            sections.append(MarkdownSection(id: id, heading: currentHeading, markdown: markdown))
            sectionIndex += 1
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
            }

            if !inFence, let heading = parseHeading(line: line, sectionIndex: sectionIndex) {
                flush()
                currentLines = [line]
                currentHeading = heading
            } else {
                currentLines.append(line)
            }
        }

        flush()
        return sections.isEmpty ? [MarkdownSection(id: "section-0", heading: nil, markdown: text)] : sections
    }

    private static func parseHeading(line: String, sectionIndex: Int) -> MarkdownHeading? {
        let raw = line.trimmingCharacters(in: .whitespaces)
        let count = raw.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), raw.dropFirst(count).first == " " else { return nil }
        let title = raw.dropFirst(count).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let id = "section-\(sectionIndex)"
        return MarkdownHeading(id: id, sectionID: id, level: count, title: title)
    }
}

var passed = 0
var failed = 0

func expect(_ condition: Bool, _ message: String) {
    if condition {
        passed += 1
        print("  ✔ \(message)")
    } else {
        failed += 1
        print("  ✘ \(message)")
    }
}

print("\n▶︎ MarkdownSection.parse")

let one = MarkdownSection.parse("# Title\n\nbody one\n\n## Sub\n\nmore body")
expect(one.count == 2, "Splits into 2 sections by heading")
expect(one.first?.heading?.title == "Title", "First heading title")
expect(one.first?.heading?.level == 1, "First heading level")
expect(one.last?.heading?.level == 2, "Second heading level")

let withCode = MarkdownSection.parse("""
# Real
prelude

```swift
# not a heading
let x = 1
```

actual content
""")
expect(withCode.count == 1, "Headings inside fenced code do not split")
expect(withCode.first?.heading?.title == "Real", "Outer heading still detected")

let noHeading = MarkdownSection.parse("just some text")
expect(noHeading.count == 1, "Plain text yields one section")
expect(noHeading.first?.heading == nil, "Plain text section has no heading")

let mixed = MarkdownSection.parse("preface\n\n# Heading\n\nbody")
expect(mixed.count == 2, "Preface preserved as its own section")
expect(mixed.first?.heading == nil, "Preface section heading is nil")
expect(mixed.last?.heading?.title == "Heading", "Trailing heading captured")

print("\n=================================")
print("  Passed: \(passed)")
print("  Failed: \(failed)")
print("=================================")

exit(failed == 0 ? 0 : 1)
