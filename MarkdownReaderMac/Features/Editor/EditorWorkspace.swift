import SwiftUI
import AppKit
import MarkdownUI

/// Editor workspace shown in the document window when the user enters
/// edit mode. Hosts source-only / split / preview-only layouts so the wider
/// Mac viewport can be used for live editing alongside the rendered output.
struct EditorWorkspace: View {
    @Binding var text: String
    let selectedMode: ReadingMode
    @Binding var editorLayout: EditorLayout
    let fontScale: CGFloat
    @Binding var pendingScrollID: String?

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(text: $text)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppPalette.line.opacity(0.6))
                        .frame(height: 1)
                }

            switch editorLayout {
            case .source:
                SourceEditor(text: $text)
            case .preview:
                PreviewPane(
                    text: text,
                    selectedMode: selectedMode,
                    fontScale: fontScale,
                    pendingScrollID: $pendingScrollID
                )
            case .split:
                HSplitView {
                    SourceEditor(text: $text)
                        .frame(minWidth: 360, idealWidth: 480)
                    PreviewPane(
                        text: text,
                        selectedMode: selectedMode,
                        fontScale: fontScale,
                        pendingScrollID: $pendingScrollID
                    )
                    .frame(minWidth: 360, idealWidth: 540)
                }
            }
        }
    }
}

/// Markdown source editor backed by an `NSTextView` for fast typing on long
/// documents and to retain native macOS conveniences like undo/redo, find,
/// and substitution behavior.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(white: 0.99, alpha: 1.0)

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.smartInsertDeleteEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor(red: 0.13, green: 0.14, blue: 0.16, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1.0)
        textView.string = text
        textView.delegate = context.coordinator
        textView.textContainerInset = NSSize(width: 14, height: 18)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView,
              textView.string != text else { return }
        let selectedRange = textView.selectedRange()
        textView.string = text
        textView.setSelectedRange(NSRange(
            location: min(selectedRange.location, text.utf16.count),
            length: 0
        ))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

private struct PreviewPane: View {
    let text: String
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    @Binding var pendingScrollID: String?

    var body: some View {
        let analysis = MarkdownAnalysis(text: text)

        ZStack {
            selectedMode.background.ignoresSafeArea()

            ReaderSurface(
                analysis: analysis,
                selectedMode: selectedMode,
                fontScale: fontScale,
                pendingScrollID: $pendingScrollID
            )
        }
    }
}

private struct EditorToolbar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            ToolButton(title: "H1") { wrap("# ") }
            ToolButton(title: "H2") { wrap("## ") }
            ToolButton(title: "H3") { wrap("### ") }
            Divider().frame(height: 18)
            ToolButton(title: "B") { surround("**") }
            ToolButton(title: "I") { surround("*") }
            ToolButton(title: "S") { surround("~~") }
            Divider().frame(height: 18)
            ToolButton(title: "代码") { surround("`") }
            ToolButton(title: "引用") { wrap("> ") }
            ToolButton(title: "列表") { wrap("- ") }
            ToolButton(title: "任务") { wrap("- [ ] ") }
            ToolButton(title: "链接") { insertLink() }
            ToolButton(title: "分割") { append("\n\n---\n\n") }
            ToolButton(title: "代码块") { append("\n\n```\n// code\n```\n\n") }
            Spacer()
            Text("\(text.filter { !$0.isWhitespace }.count) 字 · \(text.count) 字符")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
        }
    }

    private func append(_ snippet: String) {
        if text.hasSuffix("\n") || text.isEmpty {
            text += snippet.trimmingCharacters(in: .newlines) + "\n"
        } else {
            text += "\n" + snippet.trimmingCharacters(in: .newlines) + "\n"
        }
    }

    private func wrap(_ prefix: String) {
        var lines = text.components(separatedBy: "\n")
        if lines.isEmpty { lines = [""] }
        let last = lines.removeLast()
        lines.append(prefix + last)
        text = lines.joined(separator: "\n")
    }

    private func surround(_ marker: String) {
        text += "\(marker)文字\(marker)"
    }

    private func insertLink() {
        text += "[标题](https://)"
    }
}

private struct ToolButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppPalette.paper, in: Capsule())
                .overlay(Capsule().stroke(AppPalette.line.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
