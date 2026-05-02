import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Menu bar commands attached to the library window. The library is the
/// command center; document windows attach a richer command set.
struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("打开 Markdown…") {
                AppActions.openWithImporter()
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("从剪贴板新建") {
                AppActions.openFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("新建空白笔记") {
                AppActions.openBlank()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button("关于 MarkLens") {
                AppActions.showAbout()
            }
        }

        CommandMenu("阅读") {
            ForEach(ReadingMode.allCases) { mode in
                Button(mode.title) {
                    NotificationCenter.default.post(
                        name: .markLensSwitchMode,
                        object: mode.rawValue
                    )
                }
                .keyboardShortcut(mode.shortcut, modifiers: [.command, .option])
            }

            Divider()

            Button("切换大纲侧栏") {
                NotificationCenter.default.post(name: .markLensToggleOutline, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command, .option])

            Button("切换编辑模式") {
                NotificationCenter.default.post(name: .markLensToggleEditor, object: nil)
            }
            .keyboardShortcut("e", modifiers: .command)
        }

        CommandMenu("导出") {
            Button("导出为 PDF…") {
                NotificationCenter.default.post(name: .markLensExport, object: ExportRequest.pdf.rawValue)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("导出为长图…") {
                NotificationCenter.default.post(name: .markLensExport, object: ExportRequest.longImage.rawValue)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("导出为 HTML…") {
                NotificationCenter.default.post(name: .markLensExport, object: ExportRequest.html.rawValue)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("复制为富文本") {
                NotificationCenter.default.post(name: .markLensExport, object: ExportRequest.copyRichText.rawValue)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("复制为纯文本") {
                NotificationCenter.default.post(name: .markLensExport, object: ExportRequest.copyPlain.rawValue)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
}

struct DocumentCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .windowSize) {
            Divider()
            Button("打开大纲侧栏") {
                NotificationCenter.default.post(name: .markLensToggleOutline, object: nil)
            }
            .keyboardShortcut("\\", modifiers: .command)
        }
    }
}

enum ExportRequest: String {
    case pdf
    case longImage
    case html
    case markdown
    case copyRichText
    case copyPlain
}

extension Notification.Name {
    static let markLensSwitchMode = Notification.Name("markLens.switchMode")
    static let markLensToggleOutline = Notification.Name("markLens.toggleOutline")
    static let markLensToggleEditor = Notification.Name("markLens.toggleEditor")
    static let markLensExport = Notification.Name("markLens.export")
}

enum AppActions {
    @MainActor
    static func openWithImporter() {
        let panel = NSOpenPanel()
        if let markdown = UTType("net.daringfireball.markdown") {
            panel.allowedContentTypes = [markdown, .plainText, .text]
        } else {
            panel.allowedContentTypes = [.plainText, .text]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        if panel.runModal() == .OK, let url = panel.url {
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true,
                completionHandler: { _, _, _ in }
            )
        }
    }

    @MainActor
    static func openFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        openInlineText(text, baseTitle: "粘贴")
    }

    @MainActor
    static func openBlank() {
        let starter = "# 新笔记\n\n开始写点什么…\n"
        openInlineText(starter, baseTitle: "新笔记")
    }

    /// Persists the inline text to a temporary file and opens it through the
    /// standard NSDocumentController pipeline so the resulting window matches
    /// every other DocumentGroup window.
    @MainActor
    static func openInlineText(_ text: String, baseTitle: String) {
        let analysis = MarkdownAnalysis(text: text)
        let resolved = analysis.resolvedTitle(fallback: baseTitle)
        let safeName = resolved.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkLens-Inline-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName).md")

        do {
            try text.data(using: .utf8)?.write(to: url, options: .atomic)
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true,
                completionHandler: { _, _, _ in }
            )
            RecentDocumentStore.save(title: resolved, text: text, source: baseTitle)
        } catch {
            NSSound.beep()
        }
    }

    @MainActor
    static func showAbout() {
        let credits = NSAttributedString(
            string: "Markdown Reader & Presenter for macOS\n\n打开 .md，像作品一样阅读、转化与分享。\n\nMIT License",
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.systemFont(ofSize: 12)
            ]
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: credits,
            .applicationName: "MarkLens",
            .applicationVersion: "1.0",
            .version: "Open source · 2026"
        ])
    }
}
