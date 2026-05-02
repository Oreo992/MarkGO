import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// First-run home for the app. Shows the brand wordmark, three call-to-action
/// buttons (open / paste / blank), and a recents list. Drag-and-drop a `.md`
/// file anywhere on the surface to open it instantly.
struct LibraryWindow: View {
    @State private var recentDocuments: [RecentDocument] = RecentDocumentStore.load()
    @State private var hovering = false
    @State private var dropTargeted = false

    var body: some View {
        ZStack(alignment: .top) {
            AppPalette.canvas.ignoresSafeArea()
            BackdropPattern()
                .opacity(0.55)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    LibraryHero()

                    LibraryActions()

                    DragHintCard(isHighlighted: dropTargeted)

                    RecentSection(
                        recentDocuments: $recentDocuments
                    )
                }
                .padding(.horizontal, 56)
                .padding(.top, 64)
                .padding(.bottom, 64)
                .frame(maxWidth: 920, alignment: .leading)
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
        .navigationTitle("MarkLens")
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

private struct LibraryHero: View {
    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    BrandMark()
                    Text("MarkLens")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(AppPalette.ink)
                }

                Text("打开 Markdown，让它变成可阅读、可分享、可交付的成品。")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppPalette.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}

private struct BrandMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppPalette.cobalt, AppPalette.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            Image(systemName: "text.book.closed.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
        }
        .shadow(color: AppPalette.ink.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

private struct LibraryActions: View {
    var body: some View {
        HStack(spacing: 14) {
            ActionTile(
                title: "打开 .md",
                subtitle: "别人发来的文件",
                symbol: "folder",
                tint: AppPalette.cobalt,
                isPrimary: true
            ) {
                AppActions.openWithImporter()
            }

            ActionTile(
                title: "粘贴 AI 内容",
                subtitle: "ChatGPT / Claude 输出",
                symbol: "doc.on.clipboard",
                tint: AppPalette.teal,
                isPrimary: false
            ) {
                AppActions.openFromClipboard()
            }

            ActionTile(
                title: "新建空白",
                subtitle: "现写 Markdown",
                symbol: "square.and.pencil",
                tint: AppPalette.rust,
                isPrimary: false
            ) {
                AppActions.openBlank()
            }
        }
    }
}

private struct ActionTile: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isPrimary: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(isPrimary ? Color.white : tint)
                    .frame(width: 46, height: 46)
                    .background(
                        isPrimary ? tint : tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(AppPalette.ink)
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.mutedInk)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(hovered ? 0.18 : 0.10), radius: hovered ? 18 : 10, x: 0, y: hovered ? 12 : 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(hovered ? tint.opacity(0.55) : AppPalette.highlight, lineWidth: hovered ? 1.5 : 1)
            )
            .scaleEffect(hovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct DragHintCard: View {
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppPalette.cobalt)
                .frame(width: 44, height: 44)
                .background(AppPalette.cobalt.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(isHighlighted ? "松手即可打开" : "把 .md 拖到这里直接打开")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppPalette.ink)
                Text("支持 Finder、Mail、网盘、聊天工具的拖拽")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
            }

            Spacer()

            Text("⌘O")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(AppPalette.mutedInk)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppPalette.canvas, in: Capsule())
                .overlay(Capsule().stroke(AppPalette.line, lineWidth: 1))
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? AppPalette.cobalt.opacity(0.10) : AppPalette.paper.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    isHighlighted ? AppPalette.cobalt : AppPalette.line,
                    style: StrokeStyle(lineWidth: 1.4, dash: [6, 4])
                )
        )
        .animation(.smooth(duration: 0.22), value: isHighlighted)
    }
}

private struct RecentSection: View {
    @Binding var recentDocuments: [RecentDocument]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近")
                    .font(.title3.weight(.black))
                    .foregroundStyle(AppPalette.ink)
                Text(recentDocuments.isEmpty ? "还没有打开过任何 Markdown" : "\(recentDocuments.count) 份")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.mutedInk)
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
                EmptyRecentCard()
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
                    spacing: 12
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
                HStack(alignment: .top, spacing: 10) {
                    PaperThumb(isPinned: document.isPinned)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(document.title)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppPalette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(document.source)
                            Text("·")
                            Text(document.openedAt.relativeLabel)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.mutedInk)
                    }
                    Spacer(minLength: 0)
                }

                Text(document.snippet)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(AppPalette.mutedInk)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Label(document.readingTime, systemImage: "clock")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppPalette.mutedInk)
                    Spacer()
                    Text(document.fileBookmark != nil ? "本地文件" : "内联")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppPalette.mutedInk.opacity(0.8))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(hovered ? 0.16 : 0.08), radius: hovered ? 14 : 8, x: 0, y: hovered ? 10 : 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(hovered ? AppPalette.cobalt.opacity(0.4) : AppPalette.highlight, lineWidth: hovered ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(action: onOpen) {
                Label("打开", systemImage: "book.pages")
            }
            Button(action: onTogglePin) {
                Label(document.isPinned ? "取消置顶" : "置顶", systemImage: document.isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("移除", systemImage: "trash")
            }
        }
    }
}

private struct PaperThumb: View {
    let isPinned: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppPalette.canvas)
                .frame(width: 48, height: 60)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(AppPalette.cobalt).frame(width: 22, height: 4)
                        Capsule().fill(AppPalette.line).frame(width: 30, height: 3)
                        Capsule().fill(AppPalette.line.opacity(0.7)).frame(width: 22, height: 3)
                    }
                    .padding(8)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppPalette.highlight, lineWidth: 1)
                )

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppPalette.rust)
                    .padding(5)
            }
        }
    }
}

private struct EmptyRecentCard: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(AppPalette.cobalt)
                .frame(width: 60, height: 60)
                .background(AppPalette.cobalt.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("还没有打开过任何 Markdown")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppPalette.ink)
                Text("打开一份 .md，或粘贴一段 AI 输出，最近列表会出现在这里。")
                    .font(.subheadline)
                    .foregroundStyle(AppPalette.mutedInk)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.highlight, lineWidth: 1)
        )
    }
}

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
