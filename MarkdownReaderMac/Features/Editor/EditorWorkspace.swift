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

        // Register the text view with the editor command bus so toolbar
        // buttons can target the correct cursor position.
        EditorCommandBus.shared.register(textView)

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

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        if let textView = nsView.documentView as? NSTextView {
            EditorCommandBus.shared.unregister(textView)
        }
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

/// Routes toolbar actions from SwiftUI buttons to the most recent
/// `NSTextView` in the foreground document so insertions land at the cursor
/// (or wrap the active selection) instead of being appended.
final class EditorCommandBus {
    static let shared = EditorCommandBus()

    private weak var current: NSTextView?
    private var observers: [Any] = []

    private init() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            if let textView = self?.findTextView(in: window) {
                self?.current = textView
            }
        })
    }

    func register(_ textView: NSTextView) {
        current = textView
    }

    func unregister(_ textView: NSTextView) {
        if current === textView { current = nil }
    }

    /// Replaces the selection (or inserts at the caret) with `replacement`.
    /// If the selection is empty and `placeholder` is non-nil, uses it as
    /// fallback content so the user can immediately overwrite it.
    @discardableResult
    func replaceSelection(with replacement: String, placeholder: String? = nil) -> Bool {
        guard let textView = activeTextView() else { return false }

        let nsString = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let resolved: String
        if selectedRange.length == 0, let placeholder {
            resolved = replacement.replacingOccurrences(of: "{}", with: placeholder)
        } else {
            let selected = nsString.substring(with: selectedRange)
            resolved = replacement.replacingOccurrences(of: "{}", with: selected)
        }

        if textView.shouldChangeText(in: selectedRange, replacementString: resolved) {
            textView.replaceCharacters(in: selectedRange, with: resolved)
            textView.didChangeText()
            // Place the caret right after the inserted block.
            textView.setSelectedRange(NSRange(
                location: selectedRange.location + (resolved as NSString).length,
                length: 0
            ))
        }
        return true
    }

    /// Toggles a line-prefix marker (e.g. `# `, `> `, `- `) on every line that
    /// intersects the current selection.
    @discardableResult
    func togglePrefix(_ prefix: String) -> Bool {
        guard let textView = activeTextView() else { return false }
        let nsString = textView.string as NSString
        let lineRange = nsString.lineRange(for: textView.selectedRange())
        let block = nsString.substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let allHave = lines.allSatisfy { $0.isEmpty || $0.hasPrefix(prefix) }
        let transformed: [String] = lines.map { line in
            if line.isEmpty { return line }
            if allHave {
                return String(line.dropFirst(prefix.count))
            }
            return prefix + line
        }
        let replacement = transformed.joined(separator: "\n")
        if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
            textView.replaceCharacters(in: lineRange, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            ))
        }
        return true
    }

    private func activeTextView() -> NSTextView? {
        if let current { return current }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            return findTextView(in: window)
        }
        return nil
    }

    private func findTextView(in window: NSWindow) -> NSTextView? {
        if let firstResponder = window.firstResponder as? NSTextView { return firstResponder }
        return locateTextView(in: window.contentView)
    }

    private func locateTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView { return textView }
        for sub in view.subviews {
            if let found = locateTextView(in: sub) { return found }
        }
        return nil
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
        HStack(spacing: 6) {
            ToolButton(title: "H1") { EditorCommandBus.shared.togglePrefix("# ") }
            ToolButton(title: "H2") { EditorCommandBus.shared.togglePrefix("## ") }
            ToolButton(title: "H3") { EditorCommandBus.shared.togglePrefix("### ") }
            Divider().frame(height: 18)
            ToolButton(title: "B") { EditorCommandBus.shared.replaceSelection(with: "**{}**", placeholder: "粗体") }
            ToolButton(title: "I") { EditorCommandBus.shared.replaceSelection(with: "*{}*", placeholder: "斜体") }
            ToolButton(title: "S") { EditorCommandBus.shared.replaceSelection(with: "~~{}~~", placeholder: "删除") }
            Divider().frame(height: 18)
            ToolButton(title: "代码") { EditorCommandBus.shared.replaceSelection(with: "`{}`", placeholder: "code") }
            ToolButton(title: "引用") { EditorCommandBus.shared.togglePrefix("> ") }
            ToolButton(title: "列表") { EditorCommandBus.shared.togglePrefix("- ") }
            ToolButton(title: "任务") { EditorCommandBus.shared.togglePrefix("- [ ] ") }
            ToolButton(title: "链接") { EditorCommandBus.shared.replaceSelection(with: "[{}](https://)", placeholder: "标题") }
            ToolButton(title: "分割") { EditorCommandBus.shared.replaceSelection(with: "\n\n---\n\n") }
            ToolButton(title: "代码块") { EditorCommandBus.shared.replaceSelection(with: "\n```\n{}\n```\n", placeholder: "// code") }
            Spacer()
            Text("\(text.filter { !$0.isWhitespace }.count) 字 · \(text.count) 字符")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
                .monospacedDigit()
        }
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
