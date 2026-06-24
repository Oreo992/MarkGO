import SwiftUI

/// Editorial paper-and-ink palette shared across windows. Mirrors the iOS
/// brand language: warm cream canvas, deep ink text, jewel-tone accents.
enum AppPalette {
    static let canvas = Color(red: 0.965, green: 0.948, blue: 0.910)
    static let paper = Color(red: 0.995, green: 0.984, blue: 0.948)
    static let bookPaper = Color(red: 0.985, green: 0.958, blue: 0.895)
    static let ink = Color(red: 0.105, green: 0.115, blue: 0.125)
    static let mutedInk = Color(red: 0.430, green: 0.405, blue: 0.375)
    static let teal = Color(red: 0.220, green: 0.420, blue: 0.455)
    static let rust = Color(red: 0.580, green: 0.310, blue: 0.180)
    static let cobalt = Color(red: 0.200, green: 0.310, blue: 0.620)
    static let plum = Color(red: 0.420, green: 0.300, blue: 0.560)
    static let gold = Color(red: 0.815, green: 0.610, blue: 0.235)
    static let line = Color(red: 0.760, green: 0.700, blue: 0.590).opacity(0.42)
    static let highlight = Color.white.opacity(0.74)

    static let sidebar = Color(red: 0.945, green: 0.928, blue: 0.890)
    static let sidebarSelected = Color(red: 0.200, green: 0.310, blue: 0.620).opacity(0.10)
}
