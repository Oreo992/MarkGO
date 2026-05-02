import SwiftUI

/// Five reading shapes shared with the iOS product. Each mode swaps content
/// width, spacing, accent color, and surface treatment so the same Markdown
/// reads as a different artifact (article, manual, book, report, cards).
enum ReadingMode: String, CaseIterable, Identifiable {
    case article
    case manual
    case book
    case report
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .article: "文章"
        case .manual: "手册"
        case .book: "书本"
        case .report: "报告"
        case .cards: "卡片"
        }
    }

    var subtitle: String {
        switch self {
        case .article: "网页文章质感"
        case .manual: "技术文档手册"
        case .book: "电子书排版"
        case .report: "正式报告封面"
        case .cards: "可分享卡片组"
        }
    }

    var symbol: String {
        switch self {
        case .article: "text.alignleft"
        case .manual: "terminal"
        case .book: "book"
        case .report: "doc.richtext"
        case .cards: "rectangle.grid.1x2"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .article: "1"
        case .manual: "2"
        case .book: "3"
        case .report: "4"
        case .cards: "5"
        }
    }

    var accent: Color {
        switch self {
        case .article: AppPalette.teal
        case .manual: Color(red: 0.24, green: 0.34, blue: 0.42)
        case .book: Color(red: 0.54, green: 0.34, blue: 0.25)
        case .report: Color(red: 0.34, green: 0.29, blue: 0.55)
        case .cards: AppPalette.rust
        }
    }

    var background: Color {
        switch self {
        case .article: AppPalette.canvas
        case .manual: Color(red: 0.93, green: 0.95, blue: 0.95)
        case .book: Color(red: 0.96, green: 0.93, blue: 0.87)
        case .report: Color(red: 0.95, green: 0.95, blue: 0.98)
        case .cards: Color(red: 0.97, green: 0.94, blue: 0.90)
        }
    }

    /// Macs have larger viewports than phones, so content widths grow but stay
    /// within comfortable line-length ranges (52–82 characters per line).
    var contentWidth: CGFloat {
        switch self {
        case .manual: 980
        case .report: 820
        case .cards: 620
        case .book: 720
        case .article: 760
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .manual: 36
        case .cards: 24
        default: 32
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .cards: 18
        case .manual: 14
        case .report: 8
        case .book: 6
        case .article: 18
        }
    }

    var inlineSectionPadding: CGFloat {
        switch self {
        case .manual: 2
        default: 0
        }
    }
}
