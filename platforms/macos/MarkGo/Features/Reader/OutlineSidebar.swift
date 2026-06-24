import SwiftUI

/// Sidebar focused on reading navigation. Mode switching lives in the window
/// chrome, so this column stays quiet: outline and stats.
struct OutlineSidebar: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode
    @ObservedObject var navigationState: ReaderNavigationState
    let onSelectHeading: (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                OutlineList(
                    headings: analysis.headings,
                    selectedMode: selectedMode,
                    currentSectionID: navigationState.currentSectionID,
                    onSelect: onSelectHeading
                )

                Divider().background(AppPalette.line.opacity(0.6))

                StatsPanel(analysis: analysis, selectedMode: selectedMode)
            }
            .padding(18)
        }
        .background(
            ZStack {
                selectedMode.sidebarBackground
                LinearGradient(
                    colors: [
                        selectedMode.accent.opacity(0.10),
                        selectedMode.sidebarBackground.opacity(0.25),
                        selectedMode.sidebarPanel.opacity(0.38)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea(edges: .top)
        )
        .scrollContentBackground(.hidden)
    }
}

private struct OutlineList: View {
    let headings: [MarkdownHeading]
    let selectedMode: ReadingMode
    let currentSectionID: String?
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SidebarLabel(title: "目录")

            if headings.isEmpty {
                Text("这是一篇连续内容，没有标题层级。")
                    .font(.callout)
                    .foregroundStyle(AppPalette.mutedInk)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(headings) { heading in
                        OutlineRow(
                            heading: heading,
                            selectedMode: selectedMode,
                            isCurrent: currentSectionID == heading.sectionID,
                            onSelect: onSelect
                        )
                    }
                }
            }
        }
    }
}

private struct OutlineRow: View {
    let heading: MarkdownHeading
    let selectedMode: ReadingMode
    let isCurrent: Bool
    let onSelect: (String) -> Void

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.22)) {
                onSelect(heading.sectionID)
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isCurrent ? selectedMode.accent : AppPalette.line)
                    .frame(width: isCurrent ? 7 : 4, height: 18)
                    .padding(.top, 2)
                    .padding(.leading, CGFloat(max(0, heading.level - 1)) * 12)

                Text(heading.title)
                    .font(.system(size: heading.level <= 2 ? 14 : 13, weight: heading.level <= 2 ? .bold : .semibold))
                    .foregroundStyle(heading.level <= 2 ? AppPalette.ink : AppPalette.mutedInk)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                isCurrent ? selectedMode.sidebarSelection : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct StatsPanel: View {
    let analysis: MarkdownAnalysis
    let selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarLabel(title: "统计")

            VStack(alignment: .leading, spacing: 6) {
                StatRow(label: "字数", value: analysis.wordCountText)
                StatRow(label: "节数", value: "\(analysis.sections.count)")
                StatRow(label: "标题", value: "\(analysis.headings.count)")
                StatRow(label: "时长", value: analysis.readingTimeText)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppPalette.ink)
            .padding(10)
            .background(selectedMode.sidebarPanel.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selectedMode.accent.opacity(0.16), lineWidth: 1))
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(AppPalette.mutedInk)
            Spacer()
            Text(value)
                .foregroundStyle(AppPalette.ink)
                .fontWeight(.bold)
        }
    }
}

private struct SidebarLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.headline.weight(.black))
            .foregroundStyle(AppPalette.mutedInk)
    }
}
