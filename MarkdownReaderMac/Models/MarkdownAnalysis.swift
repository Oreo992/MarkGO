import Foundation

/// Lightweight Markdown structural analyzer used to drive titles, outline,
/// reading time, and section-aware layout. Splits on ATX headings while
/// honoring fenced code blocks so headings inside code are not promoted.
struct MarkdownAnalysis: Equatable {
    let text: String
    let headings: [MarkdownHeading]
    let sections: [MarkdownSection]

    init(text: String) {
        let normalizedText = MarkdownSection.normalize(text)
        self.text = normalizedText
        sections = MarkdownSection.parse(normalizedText)
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
    let displayNumber: Int
}

struct MarkdownSection: Identifiable, Equatable {
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
        let lines = normalize(text).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [MarkdownSection] = []
        var currentLines: [String] = []
        var currentHeading: MarkdownHeading?
        var sectionIndex = 0
        var inFence = false
        var seenHeadingKeys = Set<String>()

        func flush() {
            let markdown = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { return }
            if let last = sections.last, canonicalMarkdown(last.markdown) == canonicalMarkdown(markdown) {
                return
            }
            if let currentHeading {
                let headingKey = duplicateKey(for: currentHeading)
                guard !seenHeadingKeys.contains(headingKey) else { return }
                seenHeadingKeys.insert(headingKey)
            }
            let id = currentHeading?.sectionID ?? "section-\(sectionIndex)"
            sections.append(MarkdownSection(id: id, heading: currentHeading, markdown: markdown))
            sectionIndex += 1
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
            }

            if !inFence, isHeadingLine(line) {
                flush()
                guard let heading = parseHeading(line: line, sectionIndex: sectionIndex) else {
                    currentLines.append(line)
                    continue
                }
                currentLines = [line]
                currentHeading = heading
            } else {
                currentLines.append(line)
            }
        }

        flush()
        return sections.isEmpty ? [MarkdownSection(id: "section-0", heading: nil, markdown: text)] : sections
    }

    static func normalize(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var output: [String] = []
        var outsideFence: [String] = []
        var inFence = false

        func flushOutsideFence() {
            guard !outsideFence.isEmpty else { return }
            output.append(contentsOf: normalizeWrappedPipeTables(outsideFence.map(normalizeLine)))
            outsideFence.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushOutsideFence()
                output.append(line)
                inFence.toggle()
                continue
            }

            if inFence {
                output.append(line)
            } else {
                outsideFence.append(line)
            }
        }

        flushOutsideFence()
        return output.joined(separator: "\n")
    }

    private static func normalizeLine(_ line: String) -> String {
        var normalized = decodeCommonHTMLEntities(in: line)
            .replacingOccurrences(
                of: #"\\([\\`*_\[\]{}()#+\-.!>|])"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: "****", with: "**")

        let raw = normalized.trimmingCharacters(in: .whitespaces)
        if raw == "*" {
            return ""
        }
        if raw == "\\" || raw.range(of: #"^<br\s*/?>$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return ""
        }

        if normalized.hasSuffix("\\") {
            normalized.removeLast()
        }
        normalized = repairOrphanedBulletLeadBold(in: normalized)

        let cleanedRaw = normalized.trimmingCharacters(in: .whitespaces)
        for marker in ["**", "__"] where cleanedRaw.hasPrefix(marker) && cleanedRaw.hasSuffix(marker) {
            let start = cleanedRaw.index(cleanedRaw.startIndex, offsetBy: marker.count)
            let end = cleanedRaw.index(cleanedRaw.endIndex, offsetBy: -marker.count)
            let unwrapped = String(cleanedRaw[start..<end]).trimmingCharacters(in: .whitespaces)
            if parseHeading(line: unwrapped, sectionIndex: 0) != nil {
                return unwrapped
            }
        }
        return normalized
    }

    private static func repairOrphanedBulletLeadBold(in line: String) -> String {
        let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let rest = String(line.dropFirst(indent.count))
        guard let marker = ["- ", "* ", "+ "].first(where: { rest.hasPrefix($0) }) else {
            return line
        }

        let contentStart = rest.index(rest.startIndex, offsetBy: marker.count)
        let content = String(rest[contentStart...])
        guard let colonRange = content.range(of: "：") ?? content.range(of: ":") else {
            return line
        }

        let label = String(content[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard label.hasSuffix("**"), !label.hasPrefix("**") else {
            return line
        }

        let repairedLabel = label.dropLast(2).trimmingCharacters(in: .whitespaces)
        guard !repairedLabel.isEmpty else { return line }

        return indent + marker + "**" + repairedLabel + "**" + content[colonRange.lowerBound...]
    }

    private static func decodeCommonHTMLEntities(in line: String) -> String {
        var output = ""
        var index = line.startIndex

        while index < line.endIndex {
            guard line[index] == "&",
                  let semicolon = line[index...].firstIndex(of: ";") else {
                output.append(line[index])
                index = line.index(after: index)
                continue
            }

            let entityStart = line.index(after: index)
            let entity = String(line[entityStart..<semicolon])
            if let decoded = decodeHTMLEntity(entity) {
                output.append(decoded)
                index = line.index(after: semicolon)
            } else {
                output.append(line[index])
                index = line.index(after: index)
            }
        }

        return output
    }

    private static func decodeHTMLEntity(_ entity: String) -> Character? {
        switch entity.lowercased() {
        case "nbsp": return " "
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default: break
        }

        if entity.lowercased().hasPrefix("#x"),
           let value = UInt32(entity.dropFirst(2), radix: 16),
           let scalar = UnicodeScalar(value) {
            return Character(scalar)
        }

        if entity.hasPrefix("#"),
           let value = UInt32(entity.dropFirst()),
           let scalar = UnicodeScalar(value) {
            return Character(scalar)
        }

        return nil
    }

    private static func normalizeWrappedPipeTables(_ lines: [String]) -> [String] {
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if isLikelyPipeTableStart(lines, at: index) {
                var block: [String] = []
                while index < lines.count {
                    let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || isHardBlockBoundary(trimmed) {
                        break
                    }
                    block.append(lines[index])
                    index += 1
                }
                result.append(contentsOf: normalizePipeTableBlock(block))
            } else {
                result.append(lines[index])
                index += 1
            }
        }

        return result
    }

    private static func isLikelyPipeTableStart(_ lines: [String], at index: Int) -> Bool {
        guard lines[index].contains("|") else { return false }
        let lookahead = lines[index..<min(lines.count, index + 6)]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
        return lookahead.contains("|") && lookahead.range(of: #"-{3,}"#, options: .regularExpression) != nil
    }

    private static func isHardBlockBoundary(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("#")
            || trimmed.hasPrefix("```")
            || trimmed.hasPrefix("~~~")
            || trimmed == "*"
            || trimmed == "---"
            || trimmed == "***"
    }

    private static func normalizePipeTableBlock(_ block: [String]) -> [String] {
        let targetPipeCount = max(2, block.map(pipeCount).max() ?? 0)
        let rows = logicalPipeRows(from: block, targetPipeCount: targetPipeCount)
        guard let separatorIndex = rows.firstIndex(where: isPipeTableSeparator) else {
            return block
        }

        let columnCount = max(2, tableCells(in: rows[max(0, separatorIndex - 1)]).count)
        let normalizedRows: [[String]] = rows.map { row in
            if isPipeTableSeparator(row) {
                return Array(repeating: "---", count: columnCount)
            }

            var cells = tableCells(in: row)
            if cells.count > columnCount {
                cells = Array(cells.prefix(columnCount - 1)) + [cells.dropFirst(columnCount - 1).joined(separator: " ")]
            } else if cells.count < columnCount {
                cells.append(contentsOf: Array(repeating: "", count: columnCount - cells.count))
            }
            return cells
        }

        let mergedRows = mergeContinuationRows(normalizedRows, separatorIndex: separatorIndex)
        return mergedRows.map { cells in
            "| " + cells.joined(separator: " | ") + " |"
        }
    }

    private static func mergeContinuationRows(_ rows: [[String]], separatorIndex: Int) -> [[String]] {
        var merged: [[String]] = []
        for (index, cells) in rows.enumerated() {
            guard index > separatorIndex,
                  isContinuationRow(cells),
                  var previous = merged.popLast() else {
                merged.append(cells)
                continue
            }

            let continuation = cleanContinuationCell(cells[0])
            let targetIndex = max(0, previous.count - 1)
            previous[targetIndex] = [previous[targetIndex], continuation]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "<br />")
            merged.append(previous)
        }
        return merged
    }

    private static func isContinuationRow(_ cells: [String]) -> Bool {
        guard let first = cells.first else { return false }
        let trailingCellsEmpty = cells.dropFirst().allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
        return trailingCellsEmpty && (trimmed.hasPrefix("<br") || trimmed.hasPrefix("- "))
    }

    private static func cleanContinuationCell(_ cell: String) -> String {
        cell
            .replacingOccurrences(
                of: #"^<br\s*/?>\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func logicalPipeRows(from block: [String], targetPipeCount: Int) -> [String] {
        var rows: [String] = []
        var current = ""

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { rows.append(trimmed) }
            current = ""
        }

        for line in block {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|"), pipeCount(current) >= targetPipeCount {
                flush()
                current = trimmed
            } else if current.isEmpty {
                current = trimmed
            } else {
                current += " " + trimmed
            }
        }

        flush()
        return rows
    }

    private static func tableCells(in row: String) -> [String] {
        var body = row.trimmingCharacters(in: .whitespaces)
        if body.first == "|" { body.removeFirst() }
        if body.last == "|" { body.removeLast() }
        return body
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isPipeTableSeparator(_ row: String) -> Bool {
        let cells = tableCells(in: row)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }

    private static func pipeCount(_ value: String) -> Int {
        value.reduce(0) { $1 == "|" ? $0 + 1 : $0 }
    }

    private static func isHeadingLine(_ line: String) -> Bool {
        parseHeading(line: line, sectionIndex: 0) != nil
    }

    private static func canonicalMarkdown(_ markdown: String) -> String {
        markdown
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func duplicateKey(for heading: MarkdownHeading) -> String {
        "\(heading.level)|\(heading.title.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    private static func parseHeading(line: String, sectionIndex: Int) -> MarkdownHeading? {
        let raw = line.trimmingCharacters(in: .whitespaces)
        let count = raw.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), raw.dropFirst(count).first == " " else { return nil }
        let title = raw.dropFirst(count).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let id = "section-\(sectionIndex)"
        return MarkdownHeading(id: id, sectionID: id, level: count, title: title, displayNumber: sectionIndex + 1)
    }
}
