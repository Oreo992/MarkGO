import Foundation

/// User-facing recent documents, persisted in `UserDefaults`. Stores both
/// inline (clipboard, blank) and file-backed entries with an optional bookmark
/// to retain access across app launches.
struct RecentDocument: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var snippet: String
    var source: String
    var openedAt: Date
    var isPinned: Bool
    var fileBookmark: Data?
    var characterCount: Int
    var readingSectionID: String?

    var readingTime: String {
        "\(max(1, characterCount / 450)) 分钟"
    }
}

enum RecentDocumentStore {
    private static let key = "markgo.recent.documents.v1"
    private static let limit = 24

    static func load() -> [RecentDocument] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([RecentDocument].self, from: data) else {
            return []
        }

        return decoded.sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned && !second.isPinned
            }
            return first.openedAt > second.openedAt
        }
    }

    @discardableResult
    static func save(title: String, text: String, source: String, fileURL: URL? = nil) -> RecentDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty
            ? MarkdownAnalysis(text: text).title
            : trimmedTitle

        let snippet = makeSnippet(text)
        let characterCount = text.filter { !$0.isWhitespace }.count
        var documents = load()

        let bookmark = fileURL.flatMap {
            try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        let matchIndex = documents.firstIndex(where: { existing in
            if let bookmark, let existingBookmark = existing.fileBookmark {
                return existingBookmark == bookmark
            }
            return existing.title == resolvedTitle && existing.snippet == snippet
        })

        let document: RecentDocument
        if let matchIndex {
            documents[matchIndex].title = resolvedTitle
            documents[matchIndex].snippet = snippet
            documents[matchIndex].source = source
            documents[matchIndex].openedAt = Date()
            documents[matchIndex].fileBookmark = bookmark ?? documents[matchIndex].fileBookmark
            documents[matchIndex].characterCount = characterCount
            document = documents[matchIndex]
        } else {
            let new = RecentDocument(
                id: UUID(),
                title: resolvedTitle,
                snippet: snippet,
                source: source,
                openedAt: Date(),
                isPinned: false,
                fileBookmark: bookmark,
                characterCount: characterCount,
                readingSectionID: nil
            )
            documents.insert(new, at: 0)
            document = new
        }

        persist(Array(documents.sortedForRecent().prefix(limit)))
        return document
    }

    static func touch(_ id: UUID) {
        var documents = load()
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].openedAt = Date()
        persist(documents.sortedForRecent())
    }

    static func find(title: String, fileURL: URL?) -> RecentDocument? {
        let bookmark = fileURL.flatMap {
            try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return load().first { existing in
            if let bookmark, let existingBookmark = existing.fileBookmark {
                return existingBookmark == bookmark
            }
            return existing.title == title
        }
    }

    static func updateReadingPosition(title: String, fileURL: URL?, sectionID: String) {
        var documents = load()
        let bookmark = fileURL.flatMap {
            try? $0.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        guard let index = documents.firstIndex(where: { existing in
            if let bookmark, let existingBookmark = existing.fileBookmark {
                return existingBookmark == bookmark
            }
            return existing.title == title
        }) else { return }
        documents[index].readingSectionID = sectionID
        persist(documents.sortedForRecent())
    }

    static func togglePin(_ id: UUID) {
        var documents = load()
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].isPinned.toggle()
        documents[index].openedAt = Date()
        persist(documents.sortedForRecent())
    }

    static func remove(_ id: UUID) {
        persist(load().filter { $0.id != id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func resolveFileURL(_ recent: RecentDocument) -> URL? {
        guard let bookmark = recent.fileBookmark else { return nil }
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return url
        } catch {
            return nil
        }
    }

    /// Snippet kept as a multi-line block (up to ~6 lines, 220 chars) so the
    /// home screen can render a paper-style preview of the document instead
    /// of a single squashed line.
    private static func makeSnippet(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(6)
        let joined = lines.joined(separator: "\n")
        return String(joined.prefix(220))
    }

    private static func persist(_ documents: [RecentDocument]) {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

extension Array where Element == RecentDocument {
    func sortedForRecent() -> [RecentDocument] {
        sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned && !second.isPinned
            }
            return first.openedAt > second.openedAt
        }
    }
}

extension Date {
    var relativeLabel: String {
        let now = Date()
        let seconds = max(0, Int(now.timeIntervalSince(self)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        if seconds < 86_400 { return "\(seconds / 3600) 小时前" }
        if seconds < 172_800 { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: self)
    }
}
