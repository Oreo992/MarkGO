import SwiftUI
import UniformTypeIdentifiers

/// File-based document used by SwiftUI's `DocumentGroup`. Persists Markdown as
/// UTF-8 text and forwards the contents into `ReaderRoot`.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdown, .plainText, .text]
    }

    static var writableContentTypes: [UTType] {
        [.markdown]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    /// `public.markdown` ships in modern macOS, but we provide a fallback so
    /// the app keeps working on older systems where the type is not known.
    static var markdown: UTType {
        UTType("net.daringfireball.markdown")
            ?? UTType("public.markdown")
            ?? .plainText
    }
}
