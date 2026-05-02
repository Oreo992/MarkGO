import SwiftUI
import MarkdownUI

/// Reading-mode surface. Renders the document inside a paper-style content
/// container whose width, padding, and accent are controlled by the active
/// `ReadingMode`. Includes a sticky reading-progress strip at the top.
struct ReaderSurface: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode
    let fontScale: CGFloat
    @Binding var pendingScrollID: String?

    @State private var scrollOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 1
    @State private var viewportHeight: CGFloat = 1

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

                        VStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                            ReaderHeader(
                                analysis: analysis,
                                selectedMode: selectedMode
                            )
                            .id("reader-top")

                            ReaderBody(
                                sections: analysis.sections,
                                selectedMode: selectedMode,
                                fontScale: fontScale
                            )
                        }
                        .padding(.horizontal, selectedMode.horizontalPadding)
                        .padding(.top, 32)
                        .padding(.bottom, 96)
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
                    .onPreferenceChange(ScrollOffsetKey.self) { scrollOffset = $0 }
                    .onPreferenceChange(ContentHeightKey.self) { contentHeight = max(1, $0) }
                    .onChange(of: pendingScrollID) { _, target in
                        guard let target else { return }
                        withAnimation(.smooth(duration: 0.32)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            pendingScrollID = nil
                        }
                    }
                }
            }
        }
    }

    private var progress: Double {
        let scrollableHeight = max(1, contentHeight - viewportHeight)
        return min(1, max(0, -scrollOffset / scrollableHeight))
    }
}

private struct ReaderHeader: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeBadge(mode: selectedMode)

            Text(analysis.title)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.78)

            Text(analysis.subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppPalette.mutedInk)
        }
        .padding(.bottom, 6)
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

    var body: some View {
        switch selectedMode {
        case .cards:
            VStack(spacing: 18) {
                ForEach(sections) { section in
                    MarkdownSectionCard(section: section, selectedMode: selectedMode, fontScale: fontScale)
                }
            }
        case .report, .book:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(sections) { section in
                    MarkdownSectionView(section: section, selectedMode: selectedMode, fontScale: fontScale)
                }
            }
            .padding(.vertical, selectedMode == .book ? 28 : 26)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: selectedMode == .book ? 18 : 22, style: .continuous)
                    .fill(AppPalette.paper)
                    .shadow(color: AppPalette.ink.opacity(0.10), radius: 18, x: 0, y: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: selectedMode == .book ? 18 : 22, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            )
        default:
            VStack(alignment: .leading, spacing: selectedMode.sectionSpacing) {
                ForEach(sections) { section in
                    MarkdownSectionView(section: section, selectedMode: selectedMode, fontScale: fontScale)
                }
            }
        }
    }
}

private struct MarkdownSectionView: View {
    let section: MarkdownSection
    let selectedMode: ReadingMode
    let fontScale: CGFloat

    var body: some View {
        Markdown(section.markdown)
            .markdownTheme(.custom)
            .textSelection(.enabled)
            .font(.system(size: 16 * fontScale))
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(section.id)
            .padding(.vertical, selectedMode.inlineSectionPadding)
    }
}

private struct MarkdownSectionCard: View {
    let section: MarkdownSection
    let selectedMode: ReadingMode
    let fontScale: CGFloat

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

            Markdown(section.bodyMarkdown.isEmpty ? section.markdown : section.bodyMarkdown)
                .markdownTheme(.custom)
                .textSelection(.enabled)
                .font(.system(size: 16 * fontScale))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(section.id)
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
