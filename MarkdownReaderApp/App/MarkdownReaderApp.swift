import SwiftUI

@main
struct MarkdownReaderApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.light)
        }

        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ReaderView(
                document: .constant(file.document),
                titleOverride: file.fileURL?.deletingPathExtension().lastPathComponent
            )
            .preferredColorScheme(.light)
        }
    }
}
