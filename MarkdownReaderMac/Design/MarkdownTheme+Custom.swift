import SwiftUI
import MarkdownUI

extension Theme {
    /// Reading theme aligned with the iOS app: editorial paper background,
    /// quiet code blocks, and Chinese-aware spacing.
    static let custom = Theme.scaled(1.0)

    /// Returns a copy of the editorial reading theme whose body font scales
    /// uniformly. MarkdownUI ignores SwiftUI's `.font` modifier on
    /// `Markdown` views, so we have to bake the size into the theme.
    static func scaled(_ factor: CGFloat) -> Theme {
        Theme()
        .text {
            ForegroundColor(Color(red: 0.12, green: 0.13, blue: 0.13))
            BackgroundColor(.clear)
            FontSize(16 * factor)
        }
        .strong {
            FontWeight(.semibold)
        }
        .link {
            ForegroundColor(Color(red: 0.16, green: 0.38, blue: 0.42))
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
                .relativeLineSpacing(.em(0.34))
                .markdownMargin(top: 0, bottom: 18)
        }
        .heading1 { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.12))
                .markdownMargin(top: 12, bottom: 22)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(2.10))
                }
        }
        .heading2 { configuration in
            VStack(alignment: .leading, spacing: 10) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.12))
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.52))
                    }

                Rectangle()
                    .fill(Color(red: 0.22, green: 0.42, blue: 0.44).opacity(0.32))
                    .frame(width: 44, height: 2)
            }
            .markdownMargin(top: 28, bottom: 16)
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
                    .fill(Color(red: 0.23, green: 0.44, blue: 0.47))
                    .frame(width: 4)

                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color(red: 0.30, green: 0.31, blue: 0.30))
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                Color(red: 0.94, green: 0.92, blue: 0.86),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: 18)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.28))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.86))
                        ForegroundColor(Color(red: 0.17, green: 0.19, blue: 0.19))
                    }
                    .padding(.vertical, 18)
                    .padding(.horizontal, 18)
            }
            .background(
                Color(red: 0.90, green: 0.88, blue: 0.82),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(red: 0.75, green: 0.70, blue: 0.60).opacity(0.36), lineWidth: 1)
            )
            .markdownMargin(top: 2, bottom: 20)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.18))
        }
        .taskListMarker { configuration in
            Image(systemName: configuration.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color(red: 0.22, green: 0.43, blue: 0.45))
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
                .fill(Color(red: 0.76, green: 0.72, blue: 0.64).opacity(0.45))
                .frame(height: 1)
                .markdownMargin(top: 26, bottom: 26)
        }
    }
}
