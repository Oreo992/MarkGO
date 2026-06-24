import SwiftUI
import UniformTypeIdentifiers

/// A simple file document that stores its contents as a UTF‑8 encoded
/// Markdown string.
///
/// `FileDocument` is part of SwiftUI’s document‑based API.  By
/// conforming to `FileDocument`, this type can be used with
/// `DocumentGroup` so that users can open and save files from the system
/// document browser.  Only the `.md` (Markdown) file type is supported.
struct MarkdownDocument: FileDocument {
    /// Declare the uniform type identifiers that this document supports.
    /// The app registers the Markdown UTI in Info.plist so Files, AirDrop,
    /// and share surfaces can route `.md` and `.markdown` documents here.
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument] }

    /// The raw Markdown text stored in the document.
    var text: String

    /// Initialise a new empty Markdown document.  This is used when
    /// creating a new document from the document browser.
    init(text: String = "") {
        self.text = text
    }

    /// Initialise a document from a file on disk.  The system provides
    /// a `ReadConfiguration` containing a `FileWrapper`.  We extract the
    /// contents and decode them as UTF‑8.  If decoding fails, throw a
    /// `CocoaError` to signal the failure.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = string
    }

    /// Write the document back to disk.  Convert the string into UTF‑8
    /// encoded `Data` and wrap it in a `FileWrapper`.  If encoding fails
    /// (which it shouldn’t for a `String`), throw an error to abort the
    /// save operation.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let markdownDocument = UTType("net.daringfireball.markdown") ?? .plainText
}
