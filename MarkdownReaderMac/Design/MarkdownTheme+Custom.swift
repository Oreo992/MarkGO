import SwiftUI
import MarkdownUI
import AppKit

extension Theme {
    /// Reading theme aligned with the iOS app: editorial paper background,
    /// quiet code blocks, and Chinese-aware spacing.
    static let custom = Theme.reader(mode: .clear, scale: 1.0)

    /// Returns a copy of the editorial reading theme whose body font scales
    /// uniformly. MarkdownUI ignores SwiftUI's `.font` modifier on
    /// `Markdown` views, so we have to bake the size into the theme.
    static func scaled(_ factor: CGFloat) -> Theme {
        .reader(mode: .clear, scale: factor)
    }

    static func reader(mode: ReadingMode, scale factor: CGFloat, includeCodeCopy: Bool = true) -> Theme {
        let accent = mode.accent
        let bodySize: CGFloat = {
            switch mode {
            case .report: 16.5
            case .paper, .lesson: 17.5
            default: 16.5
            }
        }()
        let paragraphBottom: Double = {
            switch mode {
            case .report: 24
            case .lesson: 20
            case .cards: 14
            default: 18
            }
        }()

        return Theme()
        .text {
            ForegroundColor(Color(red: 0.12, green: 0.13, blue: 0.13))
            BackgroundColor(.clear)
            FontSize(bodySize * factor)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(accent)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(Color(red: 0.47, green: 0.22, blue: 0.13))
            BackgroundColor(Color(red: 0.92, green: 0.89, blue: 0.82))
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(mode == .report ? 0.44 : 0.34))
                .markdownMargin(top: 0, bottom: paragraphBottom)
        }
        .heading1 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: mode == .report ? 20 : 12, bottom: mode == .report ? 30 : 22)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(mode == .cards ? 1.72 : 2.10))
                }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: mode == .report ? 14 : 10) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.12))
                    .markdownTextStyle {
                        FontWeight(mode == .report ? .bold : .semibold)
                        FontSize(.em(mode == .report ? 1.60 : 1.52))
                    }

                Rectangle()
                    .fill(accent.opacity(mode == .report ? 0.44 : 0.32))
                    .frame(width: mode == .report ? 76 : 44, height: mode == .report ? 3 : 2)
            }
            .markdownMargin(top: mode == .report ? 38 : 28, bottom: mode == .report ? 24 : 16)
        }
        .heading3 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.14))
                .markdownMargin(top: 22, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.18))
                }
        }
        .heading4 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 18, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                }
        }
        .heading5 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.94))
                }
        }
        .heading6 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.86))
                    ForegroundColor(.secondary)
                }
        }
        .blockquote { configuration in
            HStack(alignment: .top, spacing: 14) {
                Capsule()
                    .fill(accent)
                    .frame(width: 4)

                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color(red: 0.30, green: 0.31, blue: 0.30))
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                accent.opacity(mode == .report ? 0.075 : 0.10),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: mode == .report ? 24 : 18)
        }
        .codeBlock { configuration in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(configuration.language?.uppercased() ?? "CODE")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(accent)
                    Spacer()
                    if includeCodeCopy {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(configuration.content, forType: .string)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(accent.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                ScrollView(.horizontal) {
                    configuration.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.30))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(mode == .report ? 0.82 : 0.86))
                            ForegroundColor(Color(red: 0.17, green: 0.19, blue: 0.19))
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 16)
                }
            }
            .background(
                Color(red: 0.90, green: 0.88, blue: 0.82).opacity(mode == .report ? 0.72 : 1),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(accent.opacity(0.20), lineWidth: 1)
            )
            .markdownMargin(top: 2, bottom: mode == .report ? 28 : 20)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.18))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .imageScale(.small)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: Color(red: 0.76, green: 0.72, blue: 0.64).opacity(0.7)))
                .markdownTableBackgroundStyle(
                    .alternatingRows(
                        Color(red: 0.99, green: 0.98, blue: 0.95),
                        Color(red: 0.94, green: 0.92, blue: 0.86)
                    )
                )
                .markdownMargin(top: 0, bottom: 20)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    if configuration.row == 0 {
                        FontWeight(.semibold)
                    }
                    BackgroundColor(nil)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .relativeLineSpacing(.em(0.24))
        }
        .thematicBreak {
            Rectangle()
                .fill(accent.opacity(0.22))
                .frame(height: 1)
                .markdownMargin(top: 26, bottom: 26)
        }
    }
}
