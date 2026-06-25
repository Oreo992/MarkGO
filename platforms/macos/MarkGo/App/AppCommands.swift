import SwiftUI
import AppKit
import CoreServices
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

            Button("粘贴文本…") {
                AppActions.openFromClipboard()
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("新建空白笔记") {
                AppActions.openBlank()
            }
            .keyboardShortcut("n", modifiers: .command)
        }

        CommandGroup(replacing: .appInfo) {
            Button("关于 MarkGo") {
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
            panel.allowedContentTypes = [
                markdown,
                .plainText,
                .text,
                UTType("public.source-code") ?? .text
            ]
        } else {
            panel.allowedContentTypes = [
                .plainText,
                .text,
                UTType("public.source-code") ?? .text
            ]
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
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 260))
        let textView = NSTextView(frame: scrollView.bounds)
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: 260)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = "粘贴 Markdown"
        alert.informativeText = "把文本粘贴到输入框里，再打开阅读。"
        alert.accessoryView = scrollView
        alert.addButton(withTitle: "打开阅读")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    @MainActor
    static func openExample() {
        let example = """
        # MarkGo 示例

        Markdown 在 AI 时代变得越来越常见，但源码并不适合快速阅读。MarkGo 的目标很直接：把 `.md` 文件变成干净、可读、可分享的页面。

        > 从源码到阅读，中间只差一次打开。

        ## 适合这些内容

        - AI 生成的回答和资料整理
        - README、产品方案、会议记录
        - 带表格、代码块、任务列表的长文档
        - 需要导出给别人看的 Markdown

        ## 一个简单表格

        | 场景 | MarkGo 帮你做什么 |
        | --- | --- |
        | 收到 `.md` 文件 | 直接预览，不需要打开编辑器 |
        | AI 生成长回答 | 把结构和层级读清楚 |
        | 需要分享 | 导出 PDF、长图或 HTML |

        ## 代码也会保留结构

        ```swift
        let markdown = "raw source"
        let page = MarkGo.render(markdown)
        ```

        ## 下一步

        - [ ] 拖入一份自己的 Markdown
        - [ ] 试试阅读模式
        - [ ] 导出成 PDF 或长图
        """
        openInlineText(example, baseTitle: "示例")
    }

    @MainActor
    static func setAsDefaultMarkdownApp() {
        let bundleIdentifier = "com.oreo.MarkGo" as CFString
        let contentTypes = [
            "net.daringfireball.markdown"
        ]

        let failures = contentTypes.compactMap { identifier -> String? in
            let status = LSSetDefaultRoleHandlerForContentType(
                identifier as CFString,
                LSRolesMask.all,
                bundleIdentifier
            )
            return status == noErr ? nil : "\(identifier): \(status)"
        }

        let alert = NSAlert()
        if failures.isEmpty {
            alert.alertStyle = .informational
            alert.messageText = "已设为 Markdown 默认打开方式"
            alert.informativeText = "之后双击 .md 或 .markdown 文件，会默认用 MarkGo 打开。"
        } else {
            alert.alertStyle = .warning
            alert.messageText = "默认打开方式设置失败"
            alert.informativeText = failures.joined(separator: "\n")
        }
        alert.addButton(withTitle: "好")
        alert.runModal()
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
            .appendingPathComponent("MarkGo-Inline-\(UUID().uuidString.prefix(8))", isDirectory: true)
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
            .applicationName: "MarkGo",
            .applicationVersion: "1.0",
            .version: "Open source · 2026"
        ])
    }
}
