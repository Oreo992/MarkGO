import SwiftUI

/// Sidebar that exposes the document outline plus quick mode and workspace
/// switching. On larger Mac windows the sidebar is permanent; users can
/// collapse it from the standard NavigationSplitView affordance.
struct OutlineSidebar: View {
    let analysis: MarkdownAnalysis
    @Binding var selectedMode: ReadingMode
    @Binding var workspaceMode: WorkspaceMode
    let onSelectHeading: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                WorkspaceSwitcher(workspaceMode: $workspaceMode)

                Divider().background(AppPalette.line.opacity(0.6))

                ModeList(selectedMode: $selectedMode)

                Divider().background(AppPalette.line.opacity(0.6))

                OutlineList(
                    headings: analysis.headings,
                    onSelect: onSelectHeading
                )

                Divider().background(AppPalette.line.opacity(0.6))

                StatsPanel(analysis: analysis)
            }
            .padding(18)
        }
        .background(AppPalette.sidebar.opacity(0.7))
    }
}

private struct WorkspaceSwitcher: View {
    @Binding var workspaceMode: WorkspaceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarLabel(title: "工作模式")

            HStack(spacing: 6) {
                workspaceTile(.read, title: "阅读", symbol: "book.pages")
                workspaceTile(.edit, title: "编辑", symbol: "square.and.pencil")
            }
        }
    }

    private func workspaceTile(_ mode: WorkspaceMode, title: String, symbol: String) -> some View {
        Button {
            workspaceMode = mode
        } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3.weight(.bold))
                Text(title)
                    .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(workspaceMode == mode ? .white : AppPalette.ink)
            .background(
                workspaceMode == mode ? AppPalette.cobalt : AppPalette.paper.opacity(0.85),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppPalette.highlight, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ModeList: View {
    @Binding var selectedMode: ReadingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SidebarLabel(title: "阅读形态")

            VStack(spacing: 6) {
                ForEach(ReadingMode.allCases) { mode in
                    Button {
                        withAnimation(.smooth(duration: 0.18)) {
                            selectedMode = mode
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(mode.accent)
                                .frame(width: 10, height: 10)
                            Text(mode.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(selectedMode == mode ? AppPalette.ink : AppPalette.ink.opacity(0.78))
                            Spacer()
                            Text(mode.subtitle)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppPalette.mutedInk)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedMode == mode
                                ? mode.accent.opacity(0.15)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selectedMode == mode ? mode.accent.opacity(0.45) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct OutlineList: View {
    let headings: [MarkdownHeading]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SidebarLabel(title: "目录")
                Spacer()
                Text(headings.isEmpty ? "无" : "\(headings.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppPalette.mutedInk)
            }

            if headings.isEmpty {
                Text("这是一篇连续内容，没有标题层级。")
                    .font(.caption)
                    .foregroundStyle(AppPalette.mutedInk)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(headings) { heading in
                        Button {
                            onSelect(heading.sectionID)
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text(String(repeating: "·", count: max(0, heading.level - 1)))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(AppPalette.line)
                                    .frame(width: 18, alignment: .leading)
                                Text(heading.title)
                                    .font(.caption.weight(heading.level <= 2 ? .bold : .semibold))
                                    .foregroundStyle(heading.level <= 2 ? AppPalette.ink : AppPalette.mutedInk)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct StatsPanel: View {
    let analysis: MarkdownAnalysis

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
            .background(AppPalette.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(AppPalette.line, lineWidth: 1))
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
        Text(title.uppercased())
            .font(.caption2.weight(.black))
            .tracking(1.2)
            .foregroundStyle(AppPalette.mutedInk)
    }
}
