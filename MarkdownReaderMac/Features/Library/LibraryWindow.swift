import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// First-run home for the app. The recent documents grid is the visual hero;
/// the open / paste / blank actions live in a slim, glanceable rail at the
/// top so they never compete with the user's library.
struct LibraryWindow: View {
    @State private var recentDocuments: [RecentDocument] = RecentDocumentStore.load()
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .top) {
            AppPalette.canvas.ignoresSafeArea()
            BackdropPattern()
                .opacity(0.45)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LibraryHeader()

                    if recentDocuments.isEmpty {
                        OnboardingHero(isHighlighted: dropTargeted)
                    }

                    QuickActionRail()

                    RecentSection(
                        recentDocuments: $recentDocuments,
                        dropTargeted: dropTargeted
                    )

                    Spacer(minLength: 12)

                    DragFooterHint(isHighlighted: dropTargeted)
                }
                .padding(.horizontal, 56)
                .padding(.top, 48)
                .padding(.bottom, 40)
                .frame(maxWidth: 1080, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reload()
        }
        .onDrop(of: [.fileURL, .plainText, .url], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .navigationTitle("MarkGo")
    }

    private func reload() {
        recentDocuments = RecentDocumentStore.load()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async {
                        NSDocumentController.shared.openDocument(
                            withContentsOf: url,
                            display: true
                        ) { _, _, _ in }
                    }
                }
                return true
            }

            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { string, _ in
                    guard let value = string as? String else { return }
                    DispatchQueue.main.async {
                        AppActions.openInlineText(value, baseTitle: "拖入")
                    }
                }
                return true
            }
        }
        return false
    }
}

// MARK: - Header

private struct LibraryHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            BrandMark()
            VStack(alignment: .leading, spacing: 2) {
                Text("MarkGo")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                Text("打开 Markdown，让它变成可阅读、可分享的成品")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppPalette.mutedInk)
            }
            Spacer()
        }
    }
}

private struct BrandMark: View {
    var body: some View {
        Image("MarkGoLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 42, height: 42)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .shadow(color: AppPalette.ink.opacity(0.12), radius: 8, x: 0, y: 5)
    }
}

// MARK: - Quick Actions

private struct QuickActionRail: View {
    @State private var showingPasteSheet = false

    var body: some View {
        HStack(spacing: 8) {
            QuickActionPill(
                title: "打开文件",
                shortcut: "⌘O",
                symbol: "folder",
                tint: AppPalette.cobalt,
                isPrimary: true
            ) {
                AppActions.openWithImporter()
            }

            QuickActionPill(
                title: "粘贴文本",
                shortcut: "⌘⇧V",
                symbol: "doc.on.clipboard",
                tint: AppPalette.teal,
                isPrimary: false
            ) {
                showingPasteSheet = true
            }

            QuickActionPill(
                title: "新建空白",
                shortcut: "⌘N",
                symbol: "square.and.pencil",
                tint: AppPalette.rust,
                isPrimary: false
            ) {
                AppActions.openBlank()
            }

            QuickActionPill(
                title: "查看示例",
                shortcut: nil,
                symbol: "sparkles.rectangle.stack",
                tint: AppPalette.cobalt,
                isPrimary: false
            ) {
                AppActions.openExample()
            }

            QuickActionPill(
                title: "设为默认",
                shortcut: nil,
                symbol: "checkmark.seal",
                tint: AppPalette.teal,
                isPrimary: false
            ) {
                AppActions.setAsDefaultMarkdownApp()
            }

            Spacer()
        }
        .sheet(isPresented: $showingPasteSheet) {
            PasteTextSheet()
        }
    }
}

private struct PasteTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var canOpen: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("粘贴 Markdown")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                    Text("把文本放进来，打开后直接进入阅读。")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppPalette.mutedInk)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppPalette.mutedInk)
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $text)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(AppPalette.ink)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(AppPalette.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppPalette.line, lineWidth: 1)
                )
                .frame(minHeight: 260)

            HStack {
                Text("\(text.count) 字符")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    AppActions.openInlineText(text, baseTitle: "粘贴")
                    dismiss()
                } label: {
                    Label("打开阅读", systemImage: "book.pages")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.teal)
                .disabled(!canOpen)
            }
        }
        .padding(22)
        .frame(width: 560)
        .background(AppPalette.canvas)
    }
}

private struct QuickActionPill: View {
    let title: String
    let shortcut: String?
    let symbol: String
    let tint: Color
    let isPrimary: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isPrimary ? Color.white : tint)

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isPrimary ? Color.white : AppPalette.ink)

                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isPrimary ? Color.white.opacity(0.78) : AppPalette.mutedInk.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (isPrimary ? Color.white.opacity(0.18) : AppPalette.canvas),
                            in: Capsule()
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(isPrimary ? tint : AppPalette.paper)
            )
            .overlay(
                Capsule().stroke(
                    isPrimary ? Color.clear : (hovered ? tint.opacity(0.55) : AppPalette.line),
                    lineWidth: 1
                )
            )
            .shadow(color: AppPalette.ink.opacity(isPrimary ? 0.14 : (hovered ? 0.10 : 0.04)),
                    radius: isPrimary ? 8 : (hovered ? 6 : 3),
                    x: 0, y: isPrimary ? 4 : 2)
            .scaleEffect(hovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.16), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - First-run onboarding

private struct OnboardingHero: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("把 Markdown 变成可读页面")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("AI 生成的回答、README、笔记和报告，不需要再盯着源码看。打开文件，MarkGo 会直接整理成适合阅读和分享的样子。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppPalette.mutedInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(alignment: .top, spacing: 14) {
                    OnboardingStep(index: "1", title: "打开", detail: "拖入或选择 .md")
                    OnboardingStep(index: "2", title: "阅读", detail: "自动排版成页面")
                    OnboardingStep(index: "3", title: "分享", detail: "导出 PDF / 长图")
                }
            }

            Spacer(minLength: 8)

            OnboardingPreview(isHighlighted: isHighlighted)
                .frame(width: 260, height: 180)
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(AppPalette.paper.opacity(0.72))
                .shadow(color: AppPalette.ink.opacity(0.08), radius: 20, x: 0, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(isHighlighted ? AppPalette.cobalt.opacity(0.75) : AppPalette.highlight, lineWidth: isHighlighted ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }
}

private struct OnboardingStep: View {
    let index: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(index)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(AppPalette.teal, in: Circle())

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppPalette.ink)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 118, alignment: .leading)
    }
}

private struct OnboardingPreview: View {
    let isHighlighted: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.canvas)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Circle().fill(AppPalette.rust.opacity(0.78)).frame(width: 7, height: 7)
                    Circle().fill(AppPalette.teal.opacity(0.78)).frame(width: 7, height: 7)
                    Circle().fill(AppPalette.cobalt.opacity(0.78)).frame(width: 7, height: 7)
                    Spacer()
                    Image("MarkGoLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                Capsule().fill(AppPalette.cobalt.opacity(0.24)).frame(width: 88, height: 7)
                Capsule().fill(AppPalette.ink.opacity(0.18)).frame(width: 174, height: 6)
                Capsule().fill(AppPalette.ink.opacity(0.13)).frame(width: 148, height: 6)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppPalette.teal.opacity(0.12))
                        .frame(width: 62, height: 44)
                        .overlay(
                            Image(systemName: "number")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(AppPalette.teal)
                        )

                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(AppPalette.ink.opacity(0.16)).frame(width: 92, height: 5)
                        Capsule().fill(AppPalette.ink.opacity(0.12)).frame(width: 74, height: 5)
                        Capsule().fill(AppPalette.ink.opacity(0.12)).frame(width: 112, height: 5)
                    }
                }
                .padding(.top, 3)

                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(isHighlighted ? AppPalette.cobalt.opacity(0.7) : AppPalette.line, style: StrokeStyle(lineWidth: 1, dash: isHighlighted ? [] : [5, 4]))
        )
    }
}

// MARK: - Recent (the hero)

private struct RecentSection: View {
    @Binding var recentDocuments: [RecentDocument]
    let dropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppPalette.ink)
                Text(recentDocuments.isEmpty ? "还没有打开过任何 Markdown" : "\(recentDocuments.count) 份")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
                    .padding(.leading, 4)
                Spacer()
                if !recentDocuments.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            RecentDocumentStore.clear()
                            recentDocuments = []
                        } label: {
                            Label("清空最近", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(AppPalette.mutedInk)
                            .frame(width: 28, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                }
            }

            if recentDocuments.isEmpty {
                EmptyRecentCard(isHighlighted: dropTargeted)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14)],
                    spacing: 14
                ) {
                    ForEach(recentDocuments) { document in
                        RecentCard(
                            document: document,
                            onOpen: { openRecent(document) },
                            onTogglePin: {
                                RecentDocumentStore.togglePin(document.id)
                                recentDocuments = RecentDocumentStore.load()
                            },
                            onRemove: {
                                RecentDocumentStore.remove(document.id)
                                recentDocuments = RecentDocumentStore.load()
                            }
                        )
                    }
                }
            }
        }
    }

    private func openRecent(_ recent: RecentDocument) {
        if let url = RecentDocumentStore.resolveFileURL(recent) {
            let didAccess = url.startAccessingSecurityScopedResource()
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { _, _, _ in
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        } else {
            AppActions.openInlineText(recent.snippet, baseTitle: recent.source)
        }
        RecentDocumentStore.touch(recent.id)
        recentDocuments = RecentDocumentStore.load()
    }
}

private struct RecentCard: View {
    let document: RecentDocument
    let onOpen: () -> Void
    let onTogglePin: () -> Void
    let onRemove: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 12) {
                PaperPreview(snippet: document.snippet, isPinned: document.isPinned)
                    .frame(height: 132)

                VStack(alignment: .leading, spacing: 6) {
                    Text(document.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: document.fileBookmark != nil ? "doc.text" : "text.alignleft")
                            .font(.caption2.weight(.bold))
                        Text(document.source)
                            .lineLimit(1)
                        Text("·")
                        Text(document.openedAt.relativeLabel)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)

                    HStack(spacing: 10) {
                        Label(document.readingTime, systemImage: "clock")
                        Label(document.characterCount.countLabel, systemImage: "textformat")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk.opacity(0.85))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(hovered ? 0.16 : 0.07),
                            radius: hovered ? 16 : 8,
                            x: 0, y: hovered ? 10 : 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(hovered ? AppPalette.cobalt.opacity(0.45) : AppPalette.highlight,
                            lineWidth: hovered ? 1.4 : 1)
            )
            .scaleEffect(hovered ? 1.015 : 1.0)
            .animation(.easeOut(duration: 0.18), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(action: onOpen) { Label("打开", systemImage: "book.pages") }
            Button(action: onTogglePin) {
                Label(document.isPinned ? "取消置顶" : "置顶",
                      systemImage: document.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive, action: onRemove) { Label("移除", systemImage: "trash") }
        }
    }
}

/// Paper-like preview tile that shows the first lines of the document so the
/// user can recognize content at a glance.
private struct PaperPreview: View {
    let snippet: String
    let isPinned: Bool

    private var previewLines: [String] {
        snippet
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(5)
            .map { String($0.prefix(60)) }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 5) {
                if previewLines.isEmpty {
                    Text("空文档")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppPalette.mutedInk.opacity(0.6))
                } else {
                    ForEach(Array(previewLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 11 : 10,
                                          weight: index == 0 ? .bold : .regular))
                            .foregroundStyle(index == 0 ? AppPalette.ink : AppPalette.mutedInk)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppPalette.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            )

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(AppPalette.rust, in: Circle())
                    .padding(8)
            }
        }
    }
}

private struct EmptyRecentCard: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppPalette.cobalt)
                .frame(width: 60, height: 60)
                .background(AppPalette.cobalt.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(isHighlighted ? "松手即可打开" : "把 Markdown 拖到这里，或使用上方按钮")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppPalette.ink)
                Text("打开过的文档会自动出现在这里，方便快速回看。")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.mutedInk)
            }
            Spacer()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? AppPalette.cobalt.opacity(0.10) : AppPalette.paper.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isHighlighted ? AppPalette.cobalt : AppPalette.line,
                    style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])
                )
        )
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }
}

// MARK: - Drag footer hint

private struct DragFooterHint: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppPalette.cobalt.opacity(0.85))

            Text(isHighlighted ? "松手即可打开" : "把 .md 文件拖到窗口任意位置，自动打开")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)

            Spacer()

            Text("⌘O · ⌘N · ⌘⇧V")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppPalette.mutedInk.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(isHighlighted ? AppPalette.cobalt.opacity(0.10) : Color.clear)
        )
        .overlay(
            Capsule().strokeBorder(
                isHighlighted ? AppPalette.cobalt.opacity(0.65) : AppPalette.line.opacity(0.7),
                style: StrokeStyle(lineWidth: 1, dash: isHighlighted ? [] : [4, 3])
            )
        )
        .animation(.easeOut(duration: 0.18), value: isHighlighted)
    }
}

// MARK: - Backdrop pattern

private struct BackdropPattern: View {
    var body: some View {
        Canvas { context, size in
            let dotSize: CGFloat = 1.2
            let spacing: CGFloat = 22
            let columns = Int(size.width / spacing)
            let rows = Int(size.height / spacing)
            let color = Color(red: 0.78, green: 0.72, blue: 0.60).opacity(0.18)
            for row in 0..<rows {
                for column in 0..<columns {
                    let x = CGFloat(column) * spacing + spacing / 2
                    let y = CGFloat(row) * spacing + spacing / 2
                    let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

private extension Int {
    var countLabel: String {
        if self >= 10_000 { return String(format: "%.1f万字", Double(self) / 10_000.0) }
        if self >= 1_000 { return "\(self / 1_000)k 字" }
        return "\(self) 字"
    }
}
