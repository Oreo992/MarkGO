import SwiftUI
import AppKit
import MarkdownUI

/// Top-level container for any opened Markdown document. On macOS we present
/// a three-pane workspace (outline · reader/editor · inspector) plus a
/// titlebar with mode controls and an export menu.
struct DocumentReaderRoot: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var selectedMode: ReadingMode = .article
    @State private var workspaceMode: WorkspaceMode = .read
    @State private var editorLayout: EditorLayout = .split
    @State private var showOutline: Bool = true
    @State private var showInspector: Bool = false
    @State private var exportPresentation: ExportPresentation?
    @State private var fontScale: CGFloat = 1.0
    @State private var pendingScrollID: String?
    /// Cached parse output. We refresh it from `.task(id:)` so we never re-run
    /// the analyzer in the middle of SwiftUI's render pass and the body itself
    /// stays a pure read against the cache.
    @State private var analysis: MarkdownAnalysis = MarkdownAnalysis(text: "")

    private var resolvedTitle: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        return analysis.title
    }

    var body: some View {
        NavigationSplitView {
            OutlineSidebar(
                analysis: analysis,
                workspaceMode: $workspaceMode,
                onSelectHeading: { id in
                    pendingScrollID = id
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            ZStack {
                selectedMode.background.ignoresSafeArea()

                workspaceContent
            }
            .navigationTitle(resolvedTitle)
            .toolbar { toolbarContent }
            .sheet(item: $exportPresentation) { presentation in
                ExportPanel(
                    request: presentation.request,
                    title: resolvedTitle,
                    text: document.text,
                    style: selectedMode
                )
                .frame(minWidth: 540, minHeight: 580)
            }
            .onReceive(NotificationCenter.default.publisher(for: .markLensSwitchMode)) { note in
                guard let raw = note.object as? String,
                      let mode = ReadingMode(rawValue: raw) else { return }
                withAnimation(.smooth(duration: 0.22)) {
                    selectedMode = mode
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .markLensToggleOutline)) { _ in
                withAnimation(.smooth(duration: 0.18)) {
                    showOutline.toggle()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .markLensToggleEditor)) { _ in
                workspaceMode = workspaceMode == .read ? .edit : .read
            }
            .onReceive(NotificationCenter.default.publisher(for: .markLensExport)) { note in
                guard let raw = note.object as? String,
                      let request = ExportRequest(rawValue: raw) else { return }
                handleExportRequest(request)
            }
            .onAppear {
                analysis = MarkdownAnalysis(text: document.text)
                trackRecent()
            }
            .task(id: document.text) {
                // Debounce re-parsing so fast typing in the editor does not
                // trigger an analyzer pass on every keystroke.
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                analysis = MarkdownAnalysis(text: document.text)
                trackRecent()
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceMode {
        case .read:
            ReaderSurface(
                analysis: analysis,
                selectedMode: selectedMode,
                fontScale: fontScale,
                pendingScrollID: $pendingScrollID
            )
        case .edit:
            EditorWorkspace(
                text: $document.text,
                selectedMode: selectedMode,
                editorLayout: $editorLayout,
                fontScale: fontScale,
                pendingScrollID: $pendingScrollID
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                workspaceMode = .read
            } label: {
                Label("阅读", systemImage: "book.pages")
                    .labelStyle(.titleAndIcon)
            }
            .help("阅读模式 (⌘E 切换)")
            .keyboardShortcut("1", modifiers: [.command, .control])
            .disabled(workspaceMode == .read)

            Button {
                workspaceMode = .edit
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
                    .labelStyle(.titleAndIcon)
            }
            .help("编辑模式 (⌘E 切换)")
            .keyboardShortcut("2", modifiers: [.command, .control])
            .disabled(workspaceMode == .edit)
        }

        ToolbarItem(placement: .principal) {
            ModeStrip(selectedMode: $selectedMode)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if workspaceMode == .edit {
                Picker("布局", selection: $editorLayout) {
                    ForEach(EditorLayout.allCases) { layout in
                        Image(systemName: layout.symbol)
                            .help(layout.title)
                            .tag(layout)
                    }
                }
                .pickerStyle(.segmented)
                .help("源码 / 分屏 / 预览")
            }

            Menu {
                Button("缩小字号") { fontScale = max(0.75, fontScale - 0.05) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("还原字号") { fontScale = 1.0 }
                    .keyboardShortcut("0", modifiers: .command)
                Button("放大字号") { fontScale = min(1.6, fontScale + 0.05) }
                    .keyboardShortcut("=", modifiers: .command)
            } label: {
                Label("字号 \(Int(fontScale * 100))%", systemImage: "textformat.size")
            }
            .help("阅读字号")

            Menu {
                Button("导出 PDF") { handleExportRequest(.pdf) }
                Button("导出长图") { handleExportRequest(.longImage) }
                Button("导出 HTML") { handleExportRequest(.html) }
                Button("导出 Markdown") { handleExportRequest(.markdown) }
                Divider()
                Button("复制富文本") { handleExportRequest(.copyRichText) }
                Button("复制纯文本") { handleExportRequest(.copyPlain) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .help("导出与分享")
        }
    }

    private func trackRecent() {
        guard !document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        RecentDocumentStore.save(
            title: resolvedTitle,
            text: document.text,
            source: fileURL == nil ? "内联" : "文件",
            fileURL: fileURL
        )
    }

    private func handleExportRequest(_ request: ExportRequest) {
        switch request {
        case .copyRichText:
            ExportRunner.copyRichText(title: resolvedTitle, text: document.text, style: selectedMode)
        case .copyPlain:
            ExportRunner.copyPlainText(title: resolvedTitle, text: document.text)
        default:
            exportPresentation = ExportPresentation(request: request)
        }
    }
}

enum WorkspaceMode {
    case read
    case edit
}

enum EditorLayout: String, CaseIterable, Identifiable {
    case source
    case split
    case preview

    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: "源码"
        case .split: "分屏"
        case .preview: "预览"
        }
    }
    var symbol: String {
        switch self {
        case .source: "chevron.left.forwardslash.chevron.right"
        case .split: "rectangle.split.2x1"
        case .preview: "text.alignleft"
        }
    }
}

struct ModeStrip: View {
    @Binding var selectedMode: ReadingMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ReadingMode.allCases) { mode in
                Button {
                    withAnimation(.smooth(duration: 0.18)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 11, weight: .bold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: .bold))
                            .fixedSize()
                    }
                    .foregroundStyle(selectedMode == mode ? .white : mode.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        selectedMode == mode ? mode.accent : mode.accent.opacity(0.10),
                        in: Capsule()
                    )
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help("\(mode.title) · \(mode.subtitle) (⌘⌥\(modeShortcut(for: mode)))")
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppPalette.line.opacity(0.4), lineWidth: 1))
        .fixedSize()
    }

    private func modeShortcut(for mode: ReadingMode) -> String {
        switch mode {
        case .article: "1"
        case .manual: "2"
        case .book: "3"
        case .report: "4"
        case .cards: "5"
        }
    }
}

struct ExportPresentation: Identifiable {
    let id = UUID()
    let request: ExportRequest
}
