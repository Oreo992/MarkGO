import SwiftUI

/// Five reading shapes. These are content forms, not color skins: each mode
/// changes width, spacing, surface structure, and typographic tone so the same
/// Markdown becomes a different kind of artifact.
enum ReadingMode: String, CaseIterable, Identifiable {
    case clear
    case paper
    case report
    case lesson
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clear: "清读"
        case .paper: "纸页"
        case .report: "报告"
        case .lesson: "讲义"
        case .cards: "卡片"
        }
    }

    var subtitle: String {
        switch self {
        case .clear: "打开就读"
        case .paper: "长文纸感"
        case .report: "正式交付"
        case .lesson: "分节学习"
        case .cards: "扫读分享"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "text.alignleft"
        case .paper: "doc.text"
        case .report: "doc.richtext"
        case .lesson: "book"
        case .cards: "rectangle.grid.1x2"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .clear: "1"
        case .paper: "2"
        case .report: "4"
        case .lesson: "3"
        case .cards: "5"
        }
    }

    var accent: Color {
        switch self {
        case .clear: AppPalette.teal
        case .paper: Color(red: 0.54, green: 0.34, blue: 0.25)
        case .report: Color(red: 0.34, green: 0.29, blue: 0.55)
        case .lesson: AppPalette.gold
        case .cards: AppPalette.rust
        }
    }

    var background: Color {
        switch self {
        case .clear: AppPalette.canvas
        case .paper: Color(red: 0.960, green: 0.934, blue: 0.874)
        case .report: Color(red: 0.95, green: 0.95, blue: 0.98)
        case .lesson: Color(red: 0.965, green: 0.945, blue: 0.885)
        case .cards: Color(red: 0.97, green: 0.94, blue: 0.90)
        }
    }

    var sidebarBackground: Color {
        switch self {
        case .clear: Color(red: 0.930, green: 0.925, blue: 0.895)
        case .paper: Color(red: 0.925, green: 0.890, blue: 0.815)
        case .report: Color(red: 0.918, green: 0.915, blue: 0.952)
        case .lesson: Color(red: 0.940, green: 0.910, blue: 0.830)
        case .cards: Color(red: 0.945, green: 0.895, blue: 0.850)
        }
    }

    var sidebarPanel: Color {
        switch self {
        case .clear: Color(red: 0.985, green: 0.972, blue: 0.930)
        case .paper: Color(red: 0.985, green: 0.955, blue: 0.885)
        case .report: Color(red: 0.970, green: 0.970, blue: 0.992)
        case .lesson: Color(red: 0.988, green: 0.960, blue: 0.895)
        case .cards: Color(red: 0.990, green: 0.945, blue: 0.900)
        }
    }

    var sidebarSelection: Color {
        accent.opacity(self == .report ? 0.14 : 0.12)
    }

    /// Macs have larger viewports than phones, so content widths grow but stay
    /// within comfortable line-length ranges (52–82 characters per line).
    var contentWidth: CGFloat {
        switch self {
        case .clear: 980
        case .paper: 900
        case .report: 1040
        case .lesson: 960
        case .cards: 760
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .cards: 28
        case .report: 44
        case .lesson: 40
        default: 32
        }
    }

    var sectionSpacing: CGFloat {
        switch self {
        case .cards: 18
        case .paper: 26
        case .report: 24
        case .lesson: 18
        case .clear: 18
        }
    }

    var inlineSectionPadding: CGFloat {
        switch self {
        case .paper: 8
        case .report: 10
        case .lesson: 6
        default: 0
        }
    }

    var bodyFontDesign: Font.Design {
        switch self {
        case .paper, .lesson: .serif
        default: .default
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .paper: 14
        case .report: 10
        case .lesson: 18
        case .cards: 22
        case .clear: 0
        }
    }
}
