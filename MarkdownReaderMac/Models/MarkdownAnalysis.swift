import Foundation

/// Lightweight Markdown structural analyzer used to drive titles, outline,
/// reading time, and section-aware layout. Splits on ATX headings while
/// honoring fenced code blocks so headings inside code are not promoted.
struct MarkdownAnalysis {
    let text: String
    let headings: [MarkdownHeading]
    let sections: [MarkdownSection]

    init(text: String) {
        self.text = text
        sections = MarkdownSection.parse(text)
        headings = sections.compactMap(\.heading)
    }

    var title: String {
        resolvedTitle(fallback: "Untitled Markdown")
    }

    var subtitle: String {
        let sectionText = headings.isEmpty ? "连续" : "\(headings.count) 节"
        return "\(readingTimeText) · \(sectionText) · \(wordCountText)"
    }

    var readingTimeText: String {
        "\(max(1, characterCount / 450)) 分钟"
    }

    var wordCountText: String {
        "\(characterCount) 字"
    }

    func resolvedTitle(fallback: String) -> String {
        if let first = headings.first?.title, !first.isEmpty {
            return first
        }
        return fallback
    }

    private var characterCount: Int {
        text.filter { !$0.isWhitespace }.count
    }
}

struct MarkdownHeading: Identifiable, Hashable {
    let id: String
    let sectionID: String
    let level: Int
    let title: String
}

struct MarkdownSection: Identifiable {
    let id: String
    let heading: MarkdownHeading?
    let markdown: String

    var bodyMarkdown: String {
        guard heading != nil else { return markdown }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !lines.isEmpty { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
