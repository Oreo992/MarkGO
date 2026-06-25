import SwiftUI
import AppKit
import MarkdownUI

/// Top-level container for any opened Markdown document. On macOS we present
/// a three-pane workspace (outline · reader/editor · inspector) plus a
/// titlebar with mode controls and an export menu.
struct DocumentReaderRoot: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var selectedMode: ReadingMode = .clear
    @State private var workspaceMode: WorkspaceMode = .read
    @State private var editorLayout: EditorLayout = .split
    @State private var showOutline: Bool = true
    @State private var showInspector: Bool = false
    @State private var exportPresentation: ExportPresentation?
    @State private var fontScale: CGFloat = 1.0
    @State private var showFontScalePopover = false
    @State private var pendingScrollID: String?
    @State private var restoredInitialPosition = false
    @State private var readingPositionCoordinator = ReadingPositionCoordinator()
    @State private var recentTrackingCoordinator = RecentTrackingCoordinator()
    @StateObject private var readerNavigation = ReaderNavigationState()
    /// Cached parse output. We refresh it from `.task(id:)` so we never re-run
    /// the analyzer in the middle of SwiftUI's render pass and the body itself
    /// stays a pure read against the cache.
    @State private var analysis: MarkdownAnalysis = MarkdownAnalysis(text: "")

    private static var expandedDocumentWindows = Set<ObjectIdentifier>()

    private static let minimumFontScale: CGFloat = 0.75
    private static let defaultFontScale: CGFloat = 1.0
    private static let maximumFontScale: CGFloat = 1.6

    private var resolvedTitle: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        return analysis.title
    }

    var body: some View {
        NavigationSplitView {
            OutlineSidebar(
                analysis: analysis,
                selectedMode: selectedMode,
                navigationState: readerNavigation,
                onSelectHeading: { id in
                    pendingScrollID = id
                }
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 390)
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
                    style: selectedMode,
                    sourceURL: fileURL
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
                refreshDocumentAnalysis()
                restoreReadingPositionIfNeeded()
                trackRecentImmediately()
            }
            .task(id: document.text) {
                // Debounce re-parsing so fast typing in the editor does not
                // trigger an analyzer pass on every keystroke.
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                refreshDocumentAnalysis()
                scheduleRecentTracking()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(WindowAccessor { window in
            configureDocumentWindow(window)
        })
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceMode {
        case .read:
            ReaderSurface(
                analysis: analysis,
                selectedMode: selectedMode,
                fontScale: fontScale,
                documentURL: fileURL,
                pendingScrollID: $pendingScrollID,
                navigationState: readerNavigation,
                onReadingPositionChange: updateReadingPosition
            )
        case .edit:
            EditorWorkspace(
                text: $document.text,
                analysis: analysis,
                selectedMode: selectedMode,
                editorLayout: $editorLayout,
                fontScale: fontScale,
                documentURL: fileURL,
                pendingScrollID: $pendingScrollID
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            WorkspaceModeSwitch(workspaceMode: $workspaceMode)
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

            Button {
                showFontScalePopover.toggle()
            } label: {
                Label("字号 \(Int(fontScale * 100))%", systemImage: "textformat.size")
            }
            .help("阅读字号")
            .popover(isPresented: $showFontScalePopover, arrowEdge: .bottom) {
                FontScalePopover(
                    fontScale: $fontScale,
                    minimumScale: Self.minimumFontScale,
                    defaultScale: Self.defaultFontScale,
                    maximumScale: Self.maximumFontScale,
                    accent: selectedMode.accent
                )
                .frame(width: 268)
            }

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

    private func trackRecentImmediately() {
        persistRecentDocument(title: resolvedTitle, text: document.text)
    }

    private func scheduleRecentTracking() {
        let text = document.text
        let fingerprint = RecentDocumentFingerprint(text: text)
        guard recentTrackingCoordinator.lastSavedFingerprint != fingerprint else { return }

        let title = resolvedTitle
        recentTrackingCoordinator.pendingTask?.cancel()
        recentTrackingCoordinator.pendingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            persistRecentDocument(title: title, text: text)
        }
    }

    private func persistRecentDocument(title: String, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        RecentDocumentStore.save(
            title: title,
            text: text,
            source: fileURL == nil ? "内联" : "文件",
            fileURL: fileURL
        )
        recentTrackingCoordinator.lastSavedFingerprint = RecentDocumentFingerprint(text: text)
    }

    private func restoreReadingPositionIfNeeded() {
        guard !restoredInitialPosition else { return }
        restoredInitialPosition = true
        guard let recent = RecentDocumentStore.find(title: resolvedTitle, fileURL: fileURL),
              let sectionID = recent.readingSectionID else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            pendingScrollID = sectionID
        }
    }

    private func refreshDocumentAnalysis() {
        let normalized = MarkdownSection.normalize(document.text)
        if normalized != document.text {
            document.text = normalized
        }
        analysis = MarkdownAnalysis(text: normalized)
    }

    private func updateReadingPosition(_ sectionID: String) {
        guard sectionID != ReaderSurface.topID else { return }
        guard readingPositionCoordinator.lastPersistedSectionID != sectionID else { return }
        readingPositionCoordinator.lastPersistedSectionID = sectionID
        readingPositionCoordinator.pendingTask?.cancel()
        let title = resolvedTitle
        let url = fileURL
        readingPositionCoordinator.pendingTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            RecentDocumentStore.updateReadingPosition(
                title: title,
                fileURL: url,
                sectionID: sectionID
            )
        }
    }

    private func configureDocumentWindow(_ window: NSWindow) {
        window.appearance = NSAppearance(named: .aqua)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(selectedMode.sidebarBackground)
        window.collectionBehavior.insert(.fullScreenPrimary)

        let windowID = ObjectIdentifier(window)
        guard !Self.expandedDocumentWindows.contains(windowID) else { return }
        Self.expandedDocumentWindows.insert(windowID)

        if let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            window.setFrame(visibleFrame, display: true, animate: false)
        }
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

final class ReaderNavigationState: ObservableObject {
    @Published var currentSectionID: String?

    func updateCurrentSection(_ sectionID: String) {
        guard currentSectionID != sectionID else { return }
        currentSectionID = sectionID
    }
}

final class ReadingPositionCoordinator {
    var lastPersistedSectionID: String?
    var pendingTask: Task<Void, Never>?
}

final class RecentTrackingCoordinator {
    var lastSavedFingerprint: RecentDocumentFingerprint?
    var pendingTask: Task<Void, Never>?
}

struct RecentDocumentFingerprint: Equatable {
    let count: Int
    let hash: Int

    init(text: String) {
        count = text.count
        hash = text.hashValue
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

private struct WorkspaceModeSwitch: View {
    @Binding var workspaceMode: WorkspaceMode

    var body: some View {
        HStack(spacing: 3) {
            modeButton(.read, title: "阅读", symbol: "book.pages")
                .keyboardShortcut("1", modifiers: [.command, .control])
            modeButton(.edit, title: "编辑", symbol: "square.and.pencil")
                .keyboardShortcut("2", modifiers: [.command, .control])
        }
        .padding(4)
        .background(AppPalette.paper.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(AppPalette.highlight, lineWidth: 1))
        .fixedSize()
    }

    private func modeButton(_ mode: WorkspaceMode, title: String, symbol: String) -> some View {
        let isSelected = workspaceMode == mode
        return Button {
            workspaceMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
            }
            .foregroundStyle(isSelected ? AppPalette.ink.opacity(0.76) : AppPalette.mutedInk.opacity(0.48))
            .frame(height: 28)
            .padding(.horizontal, 10)
            .background(isSelected ? Color.white.opacity(0.54) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(mode == .read ? "阅读模式 (⌘⌃1)" : "编辑模式 (⌘⌃2)")
        .animation(.smooth(duration: 0.16), value: isSelected)
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
        .background(selectedMode.sidebarPanel.opacity(0.94), in: Capsule())
        .overlay(Capsule().stroke(selectedMode.accent.opacity(0.18), lineWidth: 1))
        .fixedSize()
    }

    private func modeShortcut(for mode: ReadingMode) -> String {
        switch mode {
        case .clear: "1"
        case .paper: "2"
        case .lesson: "3"
        case .report: "4"
        case .cards: "5"
        }
    }
}

private struct FontScalePopover: View {
    @Binding var fontScale: CGFloat
    let minimumScale: CGFloat
    let defaultScale: CGFloat
    let maximumScale: CGFloat
    let accent: Color

    private var percentage: Int {
        Int((fontScale * 100).rounded())
    }

    private var isDefault: Bool {
        abs(fontScale - defaultScale) < 0.001
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "textformat.size")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)

                Text("阅读字号")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppPalette.ink)

                Spacer()

                Text("\(percentage)%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            Slider(
                value: Binding(
                    get: { Double(fontScale) },
                    set: { fontScale = CGFloat($0) }
                ),
                in: Double(minimumScale)...Double(maximumScale),
                step: 0.01
            )
            .tint(accent)

            HStack {
                Text("\(Int(minimumScale * 100))%")
                Spacer()
                Text("\(Int(maximumScale * 100))%")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppPalette.mutedInk)

            HStack {
                Button {
                    fontScale = defaultScale
                } label: {
                    Label("默认", systemImage: "arrow.counterclockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .disabled(isDefault)

                Spacer()
            }
        }
        .padding(16)
        .background(AppPalette.canvas)
    }
}

struct ExportPresentation: Identifiable {
    let id = UUID()
    let request: ExportRequest
}
