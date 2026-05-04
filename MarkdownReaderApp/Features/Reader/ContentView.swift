import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers
import UIKit
import CoreText

struct HomeView: View {
    @State private var showImporter = false
    @State private var importIntent: ImportIntent = .open
    @State private var showPasteComposer = false
    @State private var activeDocument: ReaderDocument?
    @State private var exportDraft: ExportDraft?
    @State private var recentDocuments = RecentDocumentStore.load()

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HomeHeader(
                            hasRecents: !recentDocuments.isEmpty,
                            onClear: clearRecents
                        )

                        if recentDocuments.isEmpty {
                            EmptyRecentPaper(onOpen: openImporter)
                        } else {
                            RecentDocumentList(
                                documents: recentDocuments,
                                onOpen: openRecent,
                                onExport: exportRecent,
                                onTogglePin: togglePin,
                                onRemove: removeRecent
                            )
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 116)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HomeActionDock(
                    onPaste: { showPasteComposer = true },
                    onOpen: openImporter,
                    onExport: quickExport
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            }
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.markdownDocument, .plainText],
                allowsMultipleSelection: false,
                onCompletion: handleImportedFile
            )
            .fullScreenCover(item: $activeDocument) { document in
                ReaderContainer(document: document)
            }
            .sheet(item: $exportDraft) { draft in
                ExportPanel(text: draft.text, title: draft.title)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showPasteComposer) {
                PasteComposer { text in
                    openPastedText(text)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                recentDocuments = RecentDocumentStore.load()
            }
            .preferredColorScheme(.light)
        }
    }

    private func openImporter() {
        importIntent = .open
        showImporter = true
    }

    private func openPastedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let saved = saveRecent(title: MarkdownAnalysis(text: trimmed).title, text: trimmed, source: "粘贴")
        activeDocument = ReaderDocument(title: saved.title, text: saved.text, recentID: saved.id, initialSectionID: saved.readingSectionID)
    }

    private func quickExport() {
        importIntent = .export
        showImporter = true
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) {
        guard let loaded = loadFirstFile(result) else { return }
        let saved = saveRecent(title: loaded.title, text: loaded.text, source: "文件")
        switch importIntent {
        case .open:
            activeDocument = ReaderDocument(title: saved.title, text: saved.text, recentID: saved.id, initialSectionID: saved.readingSectionID)
        case .export:
            exportDraft = ExportDraft(title: saved.title, text: saved.text)
        }
    }

    private func openRecent(_ recent: RecentDocument) {
        RecentDocumentStore.touch(recent.id)
        recentDocuments = RecentDocumentStore.load()
        activeDocument = ReaderDocument(title: recent.title, text: recent.text, recentID: recent.id, initialSectionID: recent.readingSectionID)
    }

    private func exportRecent(_ recent: RecentDocument) {
        RecentDocumentStore.touch(recent.id)
        recentDocuments = RecentDocumentStore.load()
        exportDraft = ExportDraft(title: recent.title, text: recent.text)
    }

    private func togglePin(_ recent: RecentDocument) {
        RecentDocumentStore.togglePin(recent.id)
        recentDocuments = RecentDocumentStore.load()
    }

    private func removeRecent(_ recent: RecentDocument) {
        RecentDocumentStore.remove(recent.id)
        recentDocuments = RecentDocumentStore.load()
    }

    private func clearRecents() {
        RecentDocumentStore.clear()
        recentDocuments = []
    }

    private func saveRecent(title: String, text: String, source: String) -> RecentDocument {
        let saved = RecentDocumentStore.save(title: title, text: text, source: source)
        recentDocuments = RecentDocumentStore.load()
        return saved
    }

    private func loadFirstFile(_ result: Result<[URL], Error>) -> ReaderDocument? {
        guard case .success(let urls) = result, let url = urls.first else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        let title = MarkdownAnalysis(text: text).resolvedTitle(fallback: fallbackTitle)
        return ReaderDocument(title: title, text: text)
    }
}

private enum ImportIntent {
    case open
    case export
}

private struct PasteComposer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    let onOpen: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppPalette.highlight, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("在这里粘贴 Markdown")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(AppPalette.mutedInk.opacity(0.58))
                                .padding(26)
                                .allowsHitTesting(false)
                        }
                    }

                Button {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    onOpen(value)
                    dismiss()
                } label: {
                    Label("预览", systemImage: "book.pages")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.cobalt)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
            .background(AppPalette.canvas)
            .navigationTitle("粘贴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        text = UIPasteboard.general.string ?? text
                    } label: {
                        Label("粘贴板", systemImage: "doc.on.clipboard")
                    }
                }
            }
        }
    }
}

private struct HomeHeader: View {
    let hasRecents: Bool
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(AppPalette.ink)

                Text(hasRecents ? "点一下继续阅读" : "先放入一个 Markdown")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
            }

            Spacer()

            if hasRecents {
                Menu {
                    Button(role: .destructive, action: onClear) {
                        Label("清空最近", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppPalette.mutedInk)
                        .frame(width: 40, height: 40)
                        .background(AppPalette.paper.opacity(0.8), in: Circle())
                        .overlay(Circle().stroke(AppPalette.highlight, lineWidth: 1))
                }
                .accessibilityLabel("整理")
            }
        }
    }
}

private struct RecentDocumentList: View {
    let documents: [RecentDocument]
    let onOpen: (RecentDocument) -> Void
    let onExport: (RecentDocument) -> Void
    let onTogglePin: (RecentDocument) -> Void
    let onRemove: (RecentDocument) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(documents) { document in
                RecentDocumentCard(
                    document: document,
                    onOpen: { onOpen(document) },
                    onExport: { onExport(document) },
                    onTogglePin: { onTogglePin(document) },
                    onRemove: { onRemove(document) }
                )
            }
        }
    }
}

private struct RecentDocumentCard: View {
    let document: RecentDocument
    let onOpen: () -> Void
    let onExport: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 14) {
                PaperThumb(isPinned: document.isPinned)

                VStack(alignment: .leading, spacing: 7) {
                    Text(document.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(document.source)
                        Text("·")
                        Text(document.openedAt.relativeLabel)
                        Text("·")
                        Text(document.readingTime)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppPalette.line)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: .white.opacity(0.75), radius: 1, x: -1, y: -1)
                    .shadow(color: AppPalette.ink.opacity(0.07), radius: 14, x: 0, y: 9)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onOpen) {
                Label("打开", systemImage: "book.pages")
            }
            Button(action: onExport) {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            Button(action: onTogglePin) {
                Label(document.isPinned ? "取消置顶" : "置顶", systemImage: document.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive, action: onRemove) {
                Label("移除", systemImage: "trash")
            }
        }
    }
}

private struct EmptyRecentPaper: View {
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 12) {
                SoftIconSurface(symbol: "doc.text.magnifyingglass", tint: AppPalette.cobalt)
                    .scaleEffect(1.12)

                Text("打开 Markdown")
                    .font(.title2.weight(.black))
                    .foregroundStyle(AppPalette.ink)

                Text("文件会出现在这里")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: .white.opacity(0.82), radius: 1, x: -1, y: -1)
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 22, x: 0, y: 14)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PaperThumb: View {
    let isPinned: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppPalette.canvas)
                .frame(width: 58, height: 70)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(AppPalette.cobalt).frame(width: 28, height: 5)
                        Capsule().fill(AppPalette.line).frame(width: 36, height: 4)
                        Capsule().fill(AppPalette.line.opacity(0.70)).frame(width: 26, height: 4)
                    }
                    .padding(10)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppPalette.highlight, lineWidth: 1)
                }

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppPalette.rust)
                    .padding(7)
            }
        }
    }
}

private struct HomeActionDock: View {
    let onPaste: () -> Void
    let onOpen: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DockButton(title: "粘贴", symbol: "doc.on.clipboard", tint: AppPalette.teal, isPrimary: false, action: onPaste)
            DockButton(title: "打开", symbol: "folder", tint: AppPalette.cobalt, isPrimary: true, action: onOpen)
            DockButton(title: "导出", symbol: "square.and.arrow.up", tint: AppPalette.rust, isPrimary: false, action: onExport)
        }
        .padding(10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(AppPalette.highlight, lineWidth: 1))
        .shadow(color: AppPalette.ink.opacity(0.10), radius: 18, x: 0, y: 10)
    }
}

private struct DockButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.bold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isPrimary ? .white : tint)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isPrimary ? 13 : 11)
                .background(isPrimary ? tint : tint.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ReaderContainer: View {
    @Environment(\.dismiss) private var dismiss
    @State private var document: MarkdownDocument
    private let recentID: UUID?
    private let initialSectionID: String?
    private let title: String

    init(document: ReaderDocument) {
        self.title = document.title
        self.recentID = document.recentID
        self.initialSectionID = document.initialSectionID
        _document = State(initialValue: MarkdownDocument(text: document.text))
    }

    var body: some View {
        ReaderView(
            document: $document,
            titleOverride: title,
            initialSectionID: initialSectionID,
            onReadingPositionChange: { sectionID in
                guard let recentID else { return }
                RecentDocumentStore.updateReadingPosition(recentID, sectionID: sectionID)
            }
        ) {
            dismiss()
        }
    }
}

struct ReaderView: View {
    @Binding var document: MarkdownDocument
    let titleOverride: String?
    var initialSectionID: String?
    var onReadingPositionChange: ((String) -> Void)?
    var onClose: (() -> Void)?

    @State private var selectedMode: ReadingMode = .clear
    @State private var showOutline = false
    @State private var showExport = false
    @State private var isEditing = false

    private var analysis: MarkdownAnalysis {
        MarkdownAnalysis(text: document.text)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                selectedMode.background.ignoresSafeArea()

                if isEditing {
                    LightweightEditor(text: $document.text)
                } else {
                    ReaderSurface(
                        analysis: analysis,
                        selectedMode: selectedMode,
                        showOutline: showOutline,
                        initialSectionID: initialSectionID,
                        onReadingPositionChange: onReadingPositionChange
                    )
                }
            }
            .navigationTitle(analysis.resolvedTitle(fallback: titleOverride ?? "Markdown"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let onClose {
                        Button("关闭", action: onClose)
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.smooth(duration: 0.24)) {
                            showOutline.toggle()
                        }
                    } label: {
                        Image(systemName: showOutline ? "list.bullet.rectangle.fill" : "list.bullet.rectangle")
                    }
                    .accessibilityLabel("目录")

                    Button {
                        isEditing.toggle()
                    } label: {
                        Image(systemName: isEditing ? "book.pages" : "pencil")
                    }
                    .accessibilityLabel(isEditing ? "阅读" : "轻编辑")

                    Button {
                        showExport = true
                    } label: {
                        Label("导出", systemImage: "square.and.arrow.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.ink)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isEditing {
                    ModeStrip(selectedMode: $selectedMode)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: $showExport) {
                ExportPanel(
                    text: document.text,
                    title: analysis.resolvedTitle(fallback: titleOverride ?? "Markdown")
                )
                .presentationDetents([.medium, .large])
            }
            .preferredColorScheme(.light)
        }
    }
}

private struct ReaderSurface: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode
    let showOutline: Bool
    let initialSectionID: String?
    var onReadingPositionChange: ((String) -> Void)?

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 1
    @State private var currentSectionID: String?
    @State private var didRestorePosition = false

    var body: some View {
        GeometryReader { viewport in
            VStack(spacing: 0) {
                ReadingProgressBar(progress: readingProgress(viewportHeight: viewport.size.height))

                ScrollViewReader { proxy in
                    ScrollView {
                        GeometryReader { marker in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: marker.frame(in: .named("readerScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        VStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                            ReaderHeader(analysis: analysis, selectedMode: selectedMode)
                                .id("reader-top")

                            if showOutline {
                                OutlinePanel(
                                    headings: analysis.headings,
                                    currentSectionID: currentSectionID,
                                    onTop: {
                                        withAnimation(.smooth(duration: 0.32)) {
                                            proxy.scrollTo("reader-top", anchor: .top)
                                        }
                                    }
                                ) { id in
                                    withAnimation(.smooth(duration: 0.32)) {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                    onReadingPositionChange?(id)
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            ReaderBody(sections: analysis.sections, selectedMode: selectedMode)
                        }
                        .padding(.horizontal, selectedMode.horizontalPadding)
                        .padding(.top, 22)
                        .padding(.bottom, 104)
                        .frame(maxWidth: selectedMode.contentWidth, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: ContentHeightPreferenceKey.self,
                                    value: contentProxy.size.height
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "readerScroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
                    .onPreferenceChange(ContentHeightPreferenceKey.self) { contentHeight = max(1, $0) }
                    .onPreferenceChange(SectionPositionPreferenceKey.self) { positions in
                        updateCurrentSection(positions)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if readingProgress(viewportHeight: viewport.size.height) > 0.08 {
                            Button {
                                withAnimation(.smooth(duration: 0.32)) {
                                    proxy.scrollTo("reader-top", anchor: .top)
                                }
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.headline.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 42, height: 42)
                                    .background(selectedMode.accent, in: Circle())
                                    .shadow(color: selectedMode.accent.opacity(0.24), radius: 12, x: 0, y: 8)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 18)
                            .padding(.bottom, 84)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .onAppear {
                        guard !didRestorePosition, let initialSectionID else { return }
                        didRestorePosition = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.smooth(duration: 0.34)) {
                                proxy.scrollTo(initialSectionID, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }

    private func updateCurrentSection(_ positions: [String: CGFloat]) {
        guard let nearest = positions.min(by: { abs($0.value - 120) < abs($1.value - 120) }) else { return }
        guard currentSectionID != nearest.key else { return }
        currentSectionID = nearest.key
        onReadingPositionChange?(nearest.key)
    }

    private func readingProgress(viewportHeight: CGFloat) -> Double {
        let scrollableHeight = max(1, contentHeight - viewportHeight)
        return min(1, max(0, -scrollOffset / scrollableHeight))
    }
}

private struct ExportPanel: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activityItems: [Any] = []
    @State private var showActivity = false
    @State private var selectedStyle: ExportStyle = .paper

    let text: String
    let title: String

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("导出")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ExportStylePicker(selectedStyle: $selectedStyle)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ExportAction(title: "PDF", subtitle: "归档", symbol: "doc.richtext", tint: AppPalette.cobalt) {
                        share([ExportRenderer.makePDF(title: title, text: text, style: selectedStyle)])
                    }
                    ExportAction(title: "长图", subtitle: "群聊", symbol: "photo", tint: AppPalette.rust) {
                        share([ExportRenderer.makeLongImage(title: title, text: text, style: selectedStyle)])
                    }
                    ExportAction(title: "文本", subtitle: "复制", symbol: "text.quote", tint: AppPalette.teal) {
                        share([ExportRenderer.makePlainText(title: title, text: text)])
                    }
                    ExportAction(title: "MD", subtitle: "源码", symbol: "number", tint: AppPalette.plum) {
                        share([ExportRenderer.makeMarkdownFile(title: title, text: text)])
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(22)
            .background(AppPalette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showActivity) {
                ActivityView(activityItems: activityItems)
            }
        }
    }

    private func share(_ items: [Any]) {
        activityItems = items
        showActivity = true
    }
}

private struct LightweightEditor: View {
    @Binding var text: String
    @State private var mode: EditorMode = .source

    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("标题", text: titleBinding)
                    .font(.title2.weight(.black))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 8) {
                    EditorToolButton(title: "H1") { applyHeading(level: 1) }
                    EditorToolButton(title: "H2") { applyHeading(level: 2) }
                    EditorToolButton(title: "B") { appendSnippet("**加粗文字**") }
                    EditorToolButton(title: "列表") { appendSnippet("\n- 项目一\n- 项目二") }
                    EditorToolButton(title: "引用") { appendSnippet("\n> 引用内容") }
                    Spacer(minLength: 0)
                    Picker("", selection: $mode) {
                        Text("源码").tag(EditorMode.source)
                        Text("预览").tag(EditorMode.preview)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 132)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Group {
                switch mode {
                case .source:
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(14)
                        .background(AppPalette.paper)
                case .preview:
                    ScrollView {
                        Markdown(text)
                            .markdownTheme(.custom)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
                    .background(AppPalette.paper)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(AppPalette.canvas)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { MarkdownTextTools.title(in: text) },
            set: { newValue in
                text = MarkdownTextTools.settingTitle(newValue, in: text)
            }
        )
    }

    private func applyHeading(level: Int) {
        let title = MarkdownTextTools.title(in: text)
        text = MarkdownTextTools.settingTitle(title, in: text, level: level)
    }

    private func appendSnippet(_ snippet: String) {
        if text.hasSuffix("\n") || text.isEmpty {
            text += snippet.trimmingCharacters(in: .newlines)
        } else {
            text += "\n\n" + snippet.trimmingCharacters(in: .newlines)
        }
    }
}

private enum EditorMode {
    case source
    case preview
}

private struct EditorToolButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(AppPalette.paper, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private enum MarkdownTextTools {
    static func title(in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                return trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    static func settingTitle(_ title: String, in text: String, level: Int = 1) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = "\(String(repeating: "#", count: level)) \(cleanTitle.isEmpty ? "Untitled Markdown" : cleanTitle)"
        var lines = text.components(separatedBy: .newlines)

        if let index = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let hashes = trimmed.prefix(while: { $0 == "#" }).count
            return (1...6).contains(hashes) && trimmed.dropFirst(hashes).first == " "
        }) {
            lines[index] = heading
            return lines.joined(separator: "\n")
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return heading + "\n\n"
        }

        return heading + "\n\n" + text
    }
}

private struct SoftIconSurface: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.title3.weight(.bold))
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.55), lineWidth: 1)
            }
    }
}

private struct TintedSurfaceModifier: ViewModifier {
    let tint: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: .white.opacity(0.80), radius: 1, x: -1, y: -1)
                    .shadow(color: tint.opacity(0.16), radius: 16, x: 0, y: 10)
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            }
    }
}

private extension View {
    func tintedSurface(_ tint: Color, radius: CGFloat = 24) -> some View {
        modifier(TintedSurfaceModifier(tint: tint, radius: radius))
    }

    func trackSectionPosition(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SectionPositionPreferenceKey.self,
                    value: [id: proxy.frame(in: .named("readerScroll")).minY]
                )
            }
        )
    }
}

private struct ReaderChromeTitle: View {
    let mode: ReadingMode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mode.accent)
                .frame(width: 8, height: 8)
            Text(mode.title)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(mode.accent)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(mode.accent.opacity(0.12), in: Capsule())
    }
}

private struct ModeStrip: View {
    @Binding var selectedMode: ReadingMode

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReadingMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .foregroundStyle(selectedMode == mode ? .white : mode.accent)
                            .background(
                                selectedMode == mode ? mode.accent : AppPalette.paper,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .background(.regularMaterial, in: Capsule())
    }
}

private struct ExportAction: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SoftIconSurface(symbol: symbol, tint: tint)
                Text(title)
                    .font(.title3.weight(.black))
                    .foregroundStyle(AppPalette.ink)
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .tintedSurface(tint, radius: 22)
        }
        .buttonStyle(.plain)
    }
}

private enum ExportStyle: String, CaseIterable, Identifiable {
    case clear
    case paper
    case report
    case lesson
    case card

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "清读"
        case .paper: "纸张"
        case .report: "报告"
        case .lesson: "讲义"
        case .card: "卡片"
        }
    }

    var accent: Color {
        switch self {
        case .clear: AppPalette.teal
        case .paper: AppPalette.cobalt
        case .report: AppPalette.plum
        case .lesson: AppPalette.gold
        case .card: AppPalette.rust
        }
    }

    var backgroundColor: UIColor {
        switch self {
        case .clear: UIColor(red: 0.965, green: 0.948, blue: 0.910, alpha: 1)
        case .paper: UIColor(red: 0.985, green: 0.970, blue: 0.925, alpha: 1)
        case .report: UIColor(red: 0.950, green: 0.955, blue: 0.985, alpha: 1)
        case .lesson: UIColor(red: 0.965, green: 0.945, blue: 0.885, alpha: 1)
        case .card: UIColor(red: 0.980, green: 0.940, blue: 0.900, alpha: 1)
        }
    }

    var inkColor: UIColor {
        UIColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    }

    var accentColor: UIColor {
        switch self {
        case .clear: UIColor(red: 0.22, green: 0.42, blue: 0.455, alpha: 1)
        case .paper: UIColor(red: 0.20, green: 0.31, blue: 0.62, alpha: 1)
        case .report: UIColor(red: 0.42, green: 0.30, blue: 0.56, alpha: 1)
        case .lesson: UIColor(red: 0.815, green: 0.610, blue: 0.235, alpha: 1)
        case .card: UIColor(red: 0.58, green: 0.31, blue: 0.18, alpha: 1)
        }
    }
}

private struct ExportStylePicker: View {
    @Binding var selectedStyle: ExportStyle

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ExportStyle.allCases) { style in
                Button {
                    selectedStyle = style
                } label: {
                    Text(style.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedStyle == style ? .white : style.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedStyle == style ? style.accent : style.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(AppPalette.paper.opacity(0.70), in: Capsule())
    }
}

private struct ReaderBody: View {
    let sections: [MarkdownSection]
    let selectedMode: ReadingMode

    var body: some View {
        switch selectedMode {
        case .cards:
            VStack(spacing: 18) {
                ForEach(sections) { section in
                    MarkdownSectionCard(section: section, selectedMode: selectedMode)
                }
            }
        case .paper:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    MarkdownSectionView(section: section, selectedMode: selectedMode)
                }
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 26)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: .white.opacity(0.78), radius: 1, x: -1, y: -1)
                    .shadow(color: AppPalette.ink.opacity(0.08), radius: 22, x: 0, y: 12)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(selectedMode.accent.opacity(0.12))
                    .frame(width: 7)
                    .padding(.vertical, 18)
            }
        case .report:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    MarkdownSectionView(section: section, selectedMode: selectedMode)
                        .padding(.bottom, section.heading?.level == 1 ? 18 : 8)
                }
            }
            .padding(.vertical, 34)
            .padding(.horizontal, 30)
            .tintedSurface(selectedMode.accent, radius: 22)
        case .book:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    HStack(alignment: .top, spacing: 14) {
                        if let heading = section.heading {
                            Text("\(heading.displayNumber)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(selectedMode.accent)
                                .frame(width: 32, alignment: .trailing)
                                .padding(.top, 8)
                        } else {
                            Spacer().frame(width: 32)
                        }
                        MarkdownSectionView(section: section, selectedMode: selectedMode)
                    }
                }
            }
            .padding(.vertical, 26)
            .padding(.horizontal, 22)
            .tintedSurface(selectedMode.accent, radius: 18)
        default:
            VStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    MarkdownSectionView(section: section, selectedMode: selectedMode)
                }
            }
        }
    }
}

private struct MarkdownSectionView: View {
    let section: MarkdownSection
    let selectedMode: ReadingMode

    var body: some View {
        Markdown(section.markdown)
            .markdownTheme(.reader(mode: selectedMode))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(section.id)
            .trackSectionPosition(section.id)
            .padding(.vertical, selectedMode.inlineSectionPadding)
    }
}

private struct MarkdownSectionCard: View {
    let section: MarkdownSection
    let selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.heading?.title {
                Label(title, systemImage: selectedMode.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedMode.accent)
                    .lineLimit(2)
            }

            Markdown(section.bodyMarkdown.isEmpty ? section.markdown : section.bodyMarkdown)
                .markdownTheme(.reader(mode: selectedMode))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(section.id)
        .trackSectionPosition(section.id)
        .padding(18)
        .tintedSurface(selectedMode.accent, radius: 24)
    }
}

private struct ReaderHeader: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ReaderChromeTitle(mode: selectedMode)

            Text(analysis.title)
                .font(.system(size: selectedMode == .report ? 38 : 42, weight: .black, design: selectedMode.bodyFontDesign))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.78)

            Text("\(selectedMode.headerNote) · \(analysis.subtitle)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
        }
        .padding(.bottom, 6)
    }
}

private struct OutlinePanel: View {
    let headings: [MarkdownHeading]
    let currentSectionID: String?
    let onTop: () -> Void
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("目录", systemImage: "list.bullet.indent")
                    .font(.title3.weight(.black))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                Button(action: onTop) {
                    Label("顶部", systemImage: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppPalette.teal.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if headings.isEmpty {
                Text("这是一篇连续内容。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(headings) { heading in
                    Button { onSelect(heading.sectionID) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(currentSectionID == heading.sectionID ? AppPalette.teal : AppPalette.line)
                                .frame(width: currentSectionID == heading.sectionID ? 8 : 5, height: 18)
                                .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)
                            Text(heading.title)
                                .font(.body.weight(heading.level <= 2 ? .bold : .semibold))
                                .foregroundStyle(heading.level <= 2 ? AppPalette.ink : .secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .tintedSurface(AppPalette.teal, radius: 22)
    }
}

private struct ReadingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(AppPalette.line.opacity(0.55))
                Rectangle()
                    .fill(AppPalette.cobalt)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

enum ReadingMode: String, CaseIterable, Identifiable {
    case clear
    case paper
    case book
    case report
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "清读"
        case .paper: "纸页"
        case .book: "讲义"
        case .report: "报告"
        case .cards: "卡片"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "text.alignleft"
        case .paper: "doc.text"
        case .book: "book"
        case .report: "doc.richtext"
        case .cards: "rectangle.grid.1x2"
        }
    }

    var accent: Color {
        switch self {
        case .clear: AppPalette.teal
        case .paper: Color(red: 0.54, green: 0.34, blue: 0.25)
        case .book: AppPalette.gold
        case .report: Color(red: 0.34, green: 0.29, blue: 0.55)
        case .cards: AppPalette.rust
        }
    }

    var background: Color {
        switch self {
        case .clear: AppPalette.canvas
        case .paper: Color(red: 0.96, green: 0.93, blue: 0.87)
        case .book: Color(red: 0.965, green: 0.945, blue: 0.885)
        case .report: Color(red: 0.95, green: 0.95, blue: 0.98)
        case .cards: Color(red: 0.97, green: 0.94, blue: 0.90)
        }
    }

    var contentWidth: CGFloat {
        switch self {
        case .book: 720
        case .report: 760
        case .cards: 540
        default: 680
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .cards: 18
        case .report: 22
        default: 24
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .cards: 18
        case .book: 22
        case .report: 18
        case .paper: 10
        case .clear: 18
        }
    }

    var inlineSectionPadding: CGFloat {
        switch self {
        case .report: 8
        case .book: 6
        default: 0
        }
    }

    var bodyFontDesign: Font.Design {
        switch self {
        case .paper, .book: .serif
        default: .default
        }
    }

    var headerNote: String {
        switch self {
        case .clear: "安静阅读"
        case .paper: "纸页长读"
        case .book: "分节讲义"
        case .report: "正式交付"
        case .cards: "扫读分享"
        }
    }
}

private struct MarkdownAnalysis {
    let text: String
    let headings: [MarkdownHeading]
    let sections: [MarkdownSection]

    init(text: String) {
        self.text = text
        sections = MarkdownSection.parse(text)
        headings = sections.compactMap(\.heading)
    }

    var title: String {
        resolvedTitle(fallback: "Untitled Markdown")
    }

    var subtitle: String {
        let sectionText = headings.isEmpty ? "连续" : "\(headings.count) 节"
        return "\(readingTimeText) · \(sectionText)"
    }

    var readingTimeText: String {
        "\(max(1, characterCount / 450)) 分钟"
    }

    func resolvedTitle(fallback: String) -> String {
        if let first = headings.first?.title, !first.isEmpty {
            return first
        }
        return fallback
    }

    private var characterCount: Int {
        text.filter { !$0.isWhitespace }.count
    }
}

private struct MarkdownHeading: Identifiable {
    let id: String
    let sectionID: String
    let level: Int
    let title: String
    let displayNumber: Int
}

private struct MarkdownSection: Identifiable {
    let id: String
    let heading: MarkdownHeading?
    let markdown: String

    var bodyMarkdown: String {
        guard heading != nil else { return markdown }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if !lines.isEmpty { lines.removeFirst() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ text: String) -> [MarkdownSection] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var sections: [MarkdownSection] = []
        var currentLines: [String] = []
        var currentHeading: MarkdownHeading?
        var sectionIndex = 0
        var inFence = false

        func flush() {
            let markdown = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { return }
            let id = currentHeading?.sectionID ?? "section-\(sectionIndex)"
            sections.append(MarkdownSection(id: id, heading: currentHeading, markdown: markdown))
            sectionIndex += 1
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
            }

            if !inFence, let heading = parseHeading(line: line, sectionIndex: sectionIndex) {
                flush()
                currentLines = [line]
                currentHeading = heading
            } else {
                currentLines.append(line)
            }
        }

        flush()
        return sections.isEmpty ? [MarkdownSection(id: "section-0", heading: nil, markdown: text)] : sections
    }

    private static func parseHeading(line: String, sectionIndex: Int) -> MarkdownHeading? {
        let raw = line.trimmingCharacters(in: .whitespaces)
        let count = raw.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), raw.dropFirst(count).first == " " else { return nil }
        let title = raw.dropFirst(count).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        let id = "section-\(sectionIndex)"
        return MarkdownHeading(id: id, sectionID: id, level: count, title: title, displayNumber: sectionIndex + 1)
    }
}

private struct ReaderDocument: Identifiable {
    let id = UUID()
    let title: String
    let text: String
    var recentID: UUID? = nil
    var initialSectionID: String? = nil
}

private struct RecentDocument: Identifiable, Codable {
    let id: UUID
    var title: String
    var text: String
    var source: String
    var openedAt: Date
    var isPinned: Bool
    var readingSectionID: String?

    var readingTime: String {
        let count = text.filter { !$0.isWhitespace }.count
        return "\(max(1, count / 450)) 分钟"
    }
}

private enum RecentDocumentStore {
    private static let key = "recent.markdown.documents.v1"
    private static let limit = 12

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
    static func save(title: String, text: String, source: String) -> RecentDocument {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? MarkdownAnalysis(text: text).title : trimmedTitle
        var documents = load()

        if let index = documents.firstIndex(where: { $0.text == text || $0.title == resolvedTitle }) {
            documents[index].title = resolvedTitle
            documents[index].text = text
            documents[index].source = source
            documents[index].openedAt = Date()
            let saved = documents[index]
            persist(Array(documents.sortedForRecent().prefix(limit)))
            return saved
        } else {
            let saved = RecentDocument(
                id: UUID(),
                title: resolvedTitle,
                text: text,
                source: source,
                openedAt: Date(),
                isPinned: false,
                readingSectionID: nil
            )
            documents.insert(saved, at: 0)
            persist(Array(documents.sortedForRecent().prefix(limit)))
            return saved
        }
    }

    static func touch(_ id: UUID) {
        var documents = load()
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].openedAt = Date()
        persist(documents.sortedForRecent())
    }

    static func togglePin(_ id: UUID) {
        var documents = load()
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].isPinned.toggle()
        documents[index].openedAt = Date()
        persist(documents.sortedForRecent())
    }

    static func updateReadingPosition(_ id: UUID, sectionID: String) {
        var documents = load()
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[index].readingSectionID = sectionID
        persist(documents.sortedForRecent())
    }

    static func remove(_ id: UUID) {
        persist(load().filter { $0.id != id })
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func persist(_ documents: [RecentDocument]) {
        guard let data = try? JSONEncoder().encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private extension Array where Element == RecentDocument {
    func sortedForRecent() -> [RecentDocument] {
        sorted { first, second in
            if first.isPinned != second.isPinned {
                return first.isPinned && !second.isPinned
            }
            return first.openedAt > second.openedAt
        }
    }
}

private extension Date {
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

private struct ExportDraft: Identifiable {
    let id = UUID()
    let title: String
    let text: String
}

private enum ExportRenderer {
    static func makePlainText(title: String, text: String) -> String {
        "\(title)\n\n\(text)"
    }

    static func makeMarkdownFile(title: String, text: String) -> URL {
        let url = temporaryURL(title: title, extension: "md")
        try? text.data(using: .utf8)?.write(to: url)
        return url
    }

    static func makePDF(title: String, text: String, style: ExportStyle) -> URL {
        let url = temporaryURL(title: title, extension: "pdf")
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let body = exportAttributedString(title: title, text: text, style: style, bodySize: 12, titleSize: 25)

        try? renderer.writePDF(to: url) { context in
            var range = CFRange(location: 0, length: 0)
            let framesetter = CTFramesetterCreateWithAttributedString(body)
            repeat {
                context.beginPage()
                style.backgroundColor.setFill()
                context.fill(page)

                let path = CGMutablePath()
                path.addRect(page.insetBy(dx: 42, dy: 48))
                let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
                context.cgContext.saveGState()
                context.cgContext.textMatrix = .identity
                context.cgContext.translateBy(x: 0, y: page.height)
                context.cgContext.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, context.cgContext)
                context.cgContext.restoreGState()
                let visible = CTFrameGetVisibleStringRange(frame)
                range.location += visible.length
            } while range.location < body.length
        }
        return url
    }

    static func makeLongImage(title: String, text: String, style: ExportStyle) -> UIImage {
        let width: CGFloat = 1080
        let horizontalPadding: CGFloat = 72
        let contentWidth = width - horizontalPadding * 2
        let attributed = exportAttributedString(title: title, text: text, style: style, bodySize: 34, titleSize: 58)
        let measured = attributed.boundingRect(
            with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = max(1280, measured.height + 240)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            style.backgroundColor.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            style.accentColor.withAlphaComponent(0.16).setFill()
            context.fill(CGRect(x: horizontalPadding, y: 74, width: 160, height: 12))
            attributed.draw(in: CGRect(x: horizontalPadding, y: 112, width: contentWidth, height: measured.height + 40))
        }
    }

    private static func exportAttributedString(
        title: String,
        text: String,
        style: ExportStyle,
        bodySize: CGFloat,
        titleSize: CGFloat
    ) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        switch style {
        case .report:
            paragraph.lineSpacing = bodySize * 0.50
            paragraph.paragraphSpacing = bodySize * 0.86
        case .lesson:
            paragraph.lineSpacing = bodySize * 0.44
            paragraph.paragraphSpacing = bodySize * 0.70
        case .card:
            paragraph.lineSpacing = bodySize * 0.40
            paragraph.paragraphSpacing = bodySize * 0.78
        default:
            paragraph.lineSpacing = bodySize * 0.36
            paragraph.paragraphSpacing = bodySize * 0.54
        }

        let attributed = NSMutableAttributedString(
            string: "\(title)\n\n\(text)",
            attributes: [
                .font: UIFont.systemFont(ofSize: bodySize),
                .foregroundColor: style.inkColor,
                .paragraphStyle: paragraph
            ]
        )
        attributed.addAttributes(
            [
                .font: UIFont.systemFont(ofSize: titleSize, weight: .black),
                .foregroundColor: style.accentColor
            ],
            range: NSRange(location: 0, length: (title as NSString).length)
        )
        return attributed
    }

    private static func temporaryURL(title: String, extension pathExtension: String) -> URL {
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(safeTitle.isEmpty ? "Markdown" : safeTitle)
            .appendingPathExtension(pathExtension)
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SectionPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum AppPalette {
    static let canvas = Color(red: 0.965, green: 0.948, blue: 0.910)
    static let paper = Color(red: 0.995, green: 0.984, blue: 0.948)
    static let bookPaper = Color(red: 0.985, green: 0.958, blue: 0.895)
    static let ink = Color(red: 0.105, green: 0.115, blue: 0.125)
    static let mutedInk = Color(red: 0.430, green: 0.405, blue: 0.375)
    static let teal = Color(red: 0.220, green: 0.420, blue: 0.455)
    static let rust = Color(red: 0.580, green: 0.310, blue: 0.180)
    static let cobalt = Color(red: 0.200, green: 0.310, blue: 0.620)
    static let plum = Color(red: 0.420, green: 0.300, blue: 0.560)
    static let gold = Color(red: 0.815, green: 0.610, blue: 0.235)
    static let line = Color(red: 0.760, green: 0.700, blue: 0.590).opacity(0.42)
    static let highlight = Color.white.opacity(0.74)
}
