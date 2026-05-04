import SwiftUI
import AppKit

/// Sheet shown after the user picks an export action. Provides format-specific
/// options (page size, theme, watermark) and runs the export through
/// `ExportRunner`.
struct ExportPanel: View {
    @Environment(\.dismiss) private var dismiss

    let request: ExportRequest
    let title: String
    let text: String
    let style: ReadingMode
    let sourceURL: URL?

    @State private var selectedTheme: ExportTheme = .paper
    @State private var pageSize: ExportPageSize = .a4
    @State private var includeWatermark = false
    @State private var imageWidth: ImageWidth = .standard
    @State private var status: ExportStatus = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(AppPalette.ink)
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppPalette.mutedInk)
                            .lineLimit(1)
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
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 18)

            Divider().background(AppPalette.line.opacity(0.6))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    themeSection
                    formatSection
                    additionalSection
                }
                .padding(24)
            }

            Divider().background(AppPalette.line.opacity(0.6))

            HStack {
                if case .success(let url) = status {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.teal)
                        Text("已保存到 ").font(.caption.weight(.semibold)) + Text(url.lastPathComponent).font(.caption.weight(.bold))
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.link)
                    }
                    .foregroundStyle(AppPalette.ink)
                } else if case .failure(let message) = status {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.rust)
                } else {
                    Text("成品会保存到你选择的位置。")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.mutedInk)
                }

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: runExport) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("导出 \(formatLabel)")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(AppPalette.cobalt)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(AppPalette.paper.opacity(0.6))
        }
        .background(AppPalette.canvas)
    }

    private var headline: String {
        switch request {
        case .pdf: "导出 PDF"
        case .longImage: "导出长图"
        case .html: "导出 HTML"
        case .markdown: "导出 Markdown"
        case .copyRichText, .copyPlain: "导出"
        }
    }

    private var formatLabel: String {
        switch request {
        case .pdf: "PDF"
        case .longImage: "PNG"
        case .html: "HTML"
        case .markdown: "MD"
        case .copyRichText: "富文本"
        case .copyPlain: "文本"
        }
    }

    @ViewBuilder
    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "主题")
            HStack(spacing: 10) {
                ForEach(ExportTheme.allCases) { theme in
                    Button {
                        selectedTheme = theme
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(theme.backgroundColor))
                                    .frame(height: 44)
                                VStack(alignment: .leading, spacing: 4) {
                                    Capsule().fill(Color(theme.accentColor)).frame(width: 30, height: 3)
                                    Capsule().fill(Color(theme.inkColor).opacity(0.3)).frame(width: 56, height: 3)
                                    Capsule().fill(Color(theme.inkColor).opacity(0.3)).frame(width: 40, height: 3)
                                }
                                .padding(8)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(selectedTheme == theme ? Color(theme.accentColor) : AppPalette.line, lineWidth: selectedTheme == theme ? 2 : 1)
                            )

                            Text(theme.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedTheme == theme ? AppPalette.ink : AppPalette.mutedInk)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch request {
            case .pdf:
                SectionLabel(title: "页面尺寸")
                Picker("页面", selection: $pageSize) {
                    ForEach(ExportPageSize.allCases) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            case .longImage:
                SectionLabel(title: "图像宽度")
                Picker("宽度", selection: $imageWidth) {
                    ForEach(ImageWidth.allCases) { width in
                        Text(width.title).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            case .html:
                SectionLabel(title: "HTML 选项")
                Text("生成内嵌主题样式与中文排版的离线 HTML 文档，双击即可在浏览器中打开。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppPalette.mutedInk)
            case .markdown:
                SectionLabel(title: "Markdown 源文件")
                Text("保留原始 Markdown 文本，可分享给开发者或归档。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppPalette.mutedInk)
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var additionalSection: some View {
        if request == .pdf || request == .longImage {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "其他")
                Toggle("加上 MarkGo 水印", isOn: $includeWatermark)
            }
        }
    }

    private func runExport() {
        do {
            switch request {
            case .pdf:
                let url = try ExportRunner.savePDF(
                    title: title,
                    text: text,
                    theme: selectedTheme,
                    pageSize: pageSize,
                    sourceURL: sourceURL,
                    watermark: includeWatermark
                )
                status = .success(url)
            case .longImage:
                let url = try ExportRunner.saveLongImage(
                    title: title,
                    text: text,
                    theme: selectedTheme,
                    width: imageWidth,
                    sourceURL: sourceURL,
                    watermark: includeWatermark
                )
                status = .success(url)
            case .html:
                let url = try ExportRunner.saveHTML(
                    title: title,
                    text: text,
                    theme: selectedTheme
                )
                status = .success(url)
            case .markdown:
                let url = try ExportRunner.saveMarkdown(
                    title: title,
                    text: text
                )
                status = .success(url)
            case .copyRichText, .copyPlain:
                break
            }
        } catch {
            status = .failure(error.localizedDescription)
        }
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.black))
            .tracking(1.2)
            .foregroundStyle(AppPalette.mutedInk)
    }
}

enum ExportStatus {
    case idle
    case success(URL)
    case failure(String)
}

enum ExportPageSize: String, CaseIterable, Identifiable {
    case a4
    case letter
    case a5

    var id: String { rawValue }
    var title: String {
        switch self {
        case .a4: "A4"
        case .letter: "Letter"
        case .a5: "A5"
        }
    }

    var size: CGSize {
        switch self {
        case .a4: CGSize(width: 595, height: 842)
        case .letter: CGSize(width: 612, height: 792)
        case .a5: CGSize(width: 420, height: 595)
        }
    }
}

enum ImageWidth: String, CaseIterable, Identifiable {
    case compact
    case standard
    case wide

    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: "750"
        case .standard: "1080"
        case .wide: "1440"
        }
    }

    var width: CGFloat {
        switch self {
        case .compact: 750
        case .standard: 1080
        case .wide: 1440
        }
    }
}
