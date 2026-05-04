import SwiftUI
import AppKit
import MarkdownUI

/// Reading-mode surface. Renders the document inside a paper-style content
/// container whose width, padding, and accent are controlled by the active
/// `ReadingMode`. Includes a sticky reading-progress strip at the top.
struct ReaderSurface: View {
    static let topID = "reader-top"

    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    let documentURL: URL?
    @Binding var pendingScrollID: String?
    let navigationState: ReaderNavigationState
    let onReadingPositionChange: (String) -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 1
    @State private var viewportHeight: CGFloat = 1
    @State private var scrollCoordinator = ReaderScrollCoordinator()

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ReadingProgressBar(progress: progress)
                    .frame(height: 3)

                GeometryReader { viewport in
                    ScrollView {
                        GeometryReader { marker in
                            Color.clear.preference(
                                key: ScrollOffsetKey.self,
                                value: marker.frame(in: .named("readerScroll")).minY
                            )
                        }
                        .frame(height: 0)

                        LazyVStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                            ReaderHeader(
                                analysis: analysis,
                                selectedMode: selectedMode
                            )
                            .id(Self.topID)

                            ReaderBody(
                                sections: analysis.sections,
                                selectedMode: selectedMode,
                                fontScale: fontScale,
                                documentURL: documentURL
                            )

                            Color.clear
                                .frame(height: max(180, viewportHeight * 0.55))
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, selectedMode.horizontalPadding)
                        .padding(.top, 32)
                        .padding(.bottom, 36)
                        .frame(maxWidth: selectedMode.contentWidth, alignment: .center)
                        .frame(maxWidth: .infinity)
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear.preference(
                                    key: ContentHeightKey.self,
                                    value: contentProxy.size.height
                                )
                            }
                        )
                    }
                    .coordinateSpace(name: "readerScroll")
                    .onAppear {
                        viewportHeight = viewport.size.height
                    }
                    .onChange(of: viewport.size.height) { _, newValue in
                        viewportHeight = newValue
                    }
                    .onPreferenceChange(ScrollOffsetKey.self) { newOffset in
                        let oldProgress = progress
                        let newProgress = progress(for: newOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
                        let crossesTopButton = (oldProgress > 0.08) != (newProgress > 0.08)
                        if abs(newProgress - oldProgress) > 0.012 || crossesTopButton {
                            scrollOffset = newOffset
                        }
                    }
                    .onPreferenceChange(ContentHeightKey.self) { newHeight in
                        let normalizedHeight = max(1, newHeight)
                        if abs(normalizedHeight - contentHeight) > 2 {
                            contentHeight = normalizedHeight
                        }
                    }
                    .onPreferenceChange(SectionPositionKey.self) { positions in
                        updateCurrentSection(positions)
                    }
                    .onChange(of: pendingScrollID) { _, target in
                        guard let target else { return }
                        withAnimation(.smooth(duration: 0.42)) {
                            proxy.scrollTo(target, anchor: target == Self.topID ? .top : .center)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            pendingScrollID = nil
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if progress > 0.08 {
                            Button {
                                withAnimation(.smooth(duration: 0.28)) {
                                    proxy.scrollTo(Self.topID, anchor: .top)
                                }
                            } label: {
                                Label("顶部", systemImage: "arrow.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 11)
                                    .background(selectedMode.accent, in: Capsule())
                                    .shadow(color: selectedMode.accent.opacity(0.24), radius: 14, x: 0, y: 8)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                }
            }
        }
    }

    private func updateCurrentSection(_ positions: [String: CGFloat]) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - scrollCoordinator.lastSectionUpdateTime > 0.12 else { return }
        scrollCoordinator.lastSectionUpdateTime = now
        guard let target = stableCurrentSection(in: positions) else { return }
        guard navigationState.currentSectionID != target else { return }
        navigationState.updateCurrentSection(target)
        onReadingPositionChange(target)
    }

    private func stableCurrentSection(in positions: [String: CGFloat]) -> String? {
        let anchorY: CGFloat = 138
        let passedAnchor = positions.filter { $0.value <= anchorY }
        if let current = passedAnchor.max(by: { $0.value < $1.value }) {
            return current.key
        }
        return positions.min(by: { $0.value < $1.value })?.key
    }

    private var progress: Double {
        progress(for: scrollOffset, contentHeight: contentHeight, viewportHeight: viewportHeight)
    }

    private func progress(for offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Double {
        let scrollableHeight = max(1, contentHeight - viewportHeight)
        return min(1, max(0, -offset / scrollableHeight))
    }
}

private final class ReaderScrollCoordinator {
    var lastSectionUpdateTime: TimeInterval = 0
}

private struct ReaderHeader: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeBadge(mode: selectedMode)

            Text(analysis.subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
        }
        .padding(.bottom, 2)
    }
}

private struct ModeBadge: View {
    let mode: ReadingMode

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mode.accent)
                .frame(width: 8, height: 8)
            Text(mode.title)
                .font(.caption.weight(.bold))
            Text("·")
                .font(.caption.weight(.bold))
                .foregroundStyle(mode.accent.opacity(0.5))
            Text(mode.subtitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(mode.accent.opacity(0.85))
        }
        .foregroundStyle(mode.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(mode.accent.opacity(0.12), in: Capsule())
    }
}

private struct ReaderBody: View {
    let sections: [MarkdownSection]
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    let documentURL: URL?

    var body: some View {
        switch selectedMode {
        case .cards:
            LazyVStack(spacing: 18) {
                ForEach(sections) { section in
                    MarkdownSectionCard(
                        section: section,
                        selectedMode: selectedMode,
                        fontScale: fontScale,
                        documentURL: documentURL
                    )
                        .equatable()
                }
            }
        case .paper:
            LazyVStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    MarkdownSectionView(
                        section: section,
                        selectedMode: selectedMode,
                        fontScale: fontScale,
                        documentURL: documentURL
                    )
                        .equatable()
                }
            }
            .padding(.vertical, 44)
            .padding(.horizontal, 40)
            .background(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(0.10), radius: 18, x: 0, y: 12)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(selectedMode.accent.opacity(0.12))
                    .frame(width: 8)
                    .padding(.vertical, 18)
            }
            .overlay(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            )
        case .report:
            LazyVStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    MarkdownSectionView(
                        section: section,
                        selectedMode: selectedMode,
                        fontScale: fontScale,
                        documentURL: documentURL
                    )
                        .equatable()
                        .padding(.bottom, section.heading?.level == 1 ? 8 : 0)
                }
            }
            .padding(.vertical, 42)
            .padding(.horizontal, 44)
            .background(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(0.09), radius: 18, x: 0, y: 12)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(selectedMode.accent.opacity(0.20))
                    .frame(height: 7)
            }
            .overlay(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .stroke(selectedMode.accent.opacity(0.18), lineWidth: 1)
            )
        case .lesson:
            LazyVStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    HStack(alignment: .top, spacing: 16) {
                        if let heading = section.heading {
                            Text("\(heading.displayNumber)")
                                .font(.caption.weight(.black))
                                .foregroundStyle(selectedMode.accent)
                                .frame(width: 34, alignment: .trailing)
                                .padding(.top, 8)
                        } else {
                            Spacer().frame(width: 34)
                        }
                        MarkdownSectionView(
                            section: section,
                            selectedMode: selectedMode,
                            fontScale: fontScale,
                            documentURL: documentURL
                        )
                            .equatable()
                    }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 30)
            .background(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: selectedMode.accent.opacity(0.14), radius: 16, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: selectedMode.cornerRadius, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            )
        default:
            LazyVStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    MarkdownSectionView(
                        section: section,
                        selectedMode: selectedMode,
                        fontScale: fontScale,
                        documentURL: documentURL
                    )
                        .equatable()
                }
            }
        }
    }
}

private struct MarkdownSectionView: View, Equatable {
    let section: MarkdownSection
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    let documentURL: URL?

    static func == (lhs: MarkdownSectionView, rhs: MarkdownSectionView) -> Bool {
        lhs.section == rhs.section
            && lhs.selectedMode == rhs.selectedMode
            && lhs.fontScale == rhs.fontScale
            && lhs.documentURL == rhs.documentURL
    }

    var body: some View {
        Markdown(section.markdown, baseURL: baseURL, imageBaseURL: baseURL)
            .markdownTheme(.reader(mode: selectedMode, scale: fontScale))
            .markdownImageProvider(MarkGoMarkdownImageProvider())
            .markdownInlineImageProvider(MarkGoMarkdownInlineImageProvider())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(section.id)
            .trackSectionPosition(section.id)
            .padding(.vertical, selectedMode.inlineSectionPadding)
    }

    private var baseURL: URL? {
        documentURL?.deletingLastPathComponent()
    }
}

private struct MarkdownSectionCard: View, Equatable {
    let section: MarkdownSection
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    let documentURL: URL?

    static func == (lhs: MarkdownSectionCard, rhs: MarkdownSectionCard) -> Bool {
        lhs.section == rhs.section
            && lhs.selectedMode == rhs.selectedMode
            && lhs.fontScale == rhs.fontScale
            && lhs.documentURL == rhs.documentURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = section.heading?.title {
                HStack(spacing: 8) {
                    Image(systemName: selectedMode.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedMode.accent)
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(selectedMode.accent)
                        .lineLimit(2)
                }
            }

            Markdown(markdown, baseURL: baseURL, imageBaseURL: baseURL)
                .markdownTheme(.reader(mode: selectedMode, scale: fontScale))
                .markdownImageProvider(MarkGoMarkdownImageProvider())
                .markdownInlineImageProvider(MarkGoMarkdownInlineImageProvider())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(section.id)
        .trackSectionPosition(section.id)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppPalette.paper)
                .shadow(color: selectedMode.accent.opacity(0.16), radius: 14, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppPalette.highlight, lineWidth: 1)
        )
    }

    private var markdown: String {
        section.bodyMarkdown.isEmpty ? section.markdown : section.bodyMarkdown
    }

    private var baseURL: URL? {
        documentURL?.deletingLastPathComponent()
    }
}

private struct MarkGoMarkdownImageProvider: ImageProvider {
    @ViewBuilder
    func makeImage(url: URL?) -> some View {
        if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DefaultImageProvider().makeImage(url: url)
        }
    }
}

private struct MarkGoMarkdownInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        if url.isFileURL, let image = NSImage(contentsOf: url) {
            return Image(nsImage: image)
        }
        return try await DefaultInlineImageProvider().image(with: url, label: label)
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
        .accessibilityHidden(true)
    }
}

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct SectionPositionKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func trackSectionPosition(_ id: String) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SectionPositionKey.self,
                    value: [id: proxy.frame(in: .named("readerScroll")).minY]
                )
            }
        )
    }
}
