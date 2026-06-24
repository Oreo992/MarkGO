// Headless source-level check for macOS PDF export memory behavior.
//
// PDF export should render page-sized slices from the SwiftUI document view
// instead of first creating one full-height bitmap. The full bitmap path is
// acceptable for PNG long-image export, but PDF should stay bounded by page
// height so long documents do not consume memory proportional to the whole
// document image.

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let exportURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Export/ExportRunner.swift")
let source = try String(contentsOf: exportURL, encoding: .utf8)

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        failures.append(message)
    }
}

func section(from start: String, to end: String) -> String {
    guard let startRange = source.range(of: start),
          let endRange = source[startRange.upperBound...].range(of: end) else {
        return ""
    }
    return String(source[startRange.lowerBound..<endRange.lowerBound])
}

let pdfSection = section(from: "static func savePDF", to: "static func saveLongImage")
let imageSection = section(from: "private static func makeRenderedMarkdownImage", to: "private static func nextPDFSliceHeight")

expect(!pdfSection.isEmpty, "test can locate the PDF export implementation")
expect(pdfSection.contains("makeRenderedMarkdownHostingView"), "PDF export measures one SwiftUI hosting view")
expect(!pdfSection.contains("makeRenderedMarkdownImage"), "PDF export does not build a full-height bitmap first")
expect(pdfSection.contains("renderSliceBitmap"), "PDF export renders bounded page slices")
expect(pdfSection.contains("nextPDFSliceHeight("), "PDF export still uses whitespace-aware page slicing")
expect(source.contains("private static func renderSliceBitmap"), "exporter has a dedicated slice renderer")
expect(source.contains("private static func viewRectFromTop"), "exporter maps top-origin page slices into NSView coordinates")
expect(source.contains("private static func makeRenderedMarkdownHostingView"), "exporter shares view measurement between PDF and PNG export")
expect(source.contains("private static func makeBitmapImageRepForExport"), "bitmap export uses an explicit 1x bitmap size")
expect(source.contains("pixelsWide: max(1, Int(size.width.rounded(.up)))"), "bitmap export preserves the selected pixel width")
expect(imageSection.contains("makeRenderedMarkdownHostingView"), "long-image export reuses the same measured hosting view")

if failures.isEmpty {
    print("All macOS PDF streaming checks passed.")
} else {
    print("\nFailures: \(failures.count)")
    exit(1)
}
