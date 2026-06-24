// Headless source-level check for the hidden macOS export smoke runner.
// The app binary should be able to render real PDF/PNG/HTML artifacts without
// driving save panels, so export changes can be tested against production code.

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appURL = repoRoot.appendingPathComponent("MarkdownReaderMac/App/MarkdownReaderMacApp.swift")
let exportURL = repoRoot.appendingPathComponent("MarkdownReaderMac/Features/Export/ExportRunner.swift")

let appSource = try String(contentsOf: appURL, encoding: .utf8)
let exportSource = try String(contentsOf: exportURL, encoding: .utf8)

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        failures.append(message)
    }
}

expect(exportSource.contains("static func writePDF("), "ExportRunner exposes a noninteractive PDF writer")
expect(exportSource.contains("static func writeLongImage("), "ExportRunner exposes a noninteractive PNG writer")
expect(exportSource.contains("static func writeHTML("), "ExportRunner exposes a noninteractive HTML writer")
expect(exportSource.contains("savePDF") && exportSource.contains("writePDF("), "save panel path uses the same PDF writer")
expect(exportSource.contains("saveLongImage") && exportSource.contains("writeLongImage("), "save panel path uses the same PNG writer")
expect(exportSource.contains("saveHTML") && exportSource.contains("writeHTML("), "save panel path uses the same HTML writer")
expect(appSource.contains("ExportSmokeRunner.runIfRequested()"), "app launch checks for the hidden smoke runner")
expect(appSource.contains("--markgo-export-smoke"), "smoke runner is gated behind an explicit argument")
expect(appSource.contains("ExportRunner.writePDF"), "smoke runner renders PDF through production ExportRunner")
expect(appSource.contains("ExportRunner.writeLongImage"), "smoke runner renders PNG through production ExportRunner")
expect(appSource.contains("ExportRunner.writeHTML"), "smoke runner renders HTML through production ExportRunner")
expect(appSource.contains("PDFDocument(url:"), "smoke runner verifies generated PDF page count")
expect(appSource.contains("NSBitmapImageRep(data:"), "smoke runner verifies generated PNG dimensions")
expect(appSource.contains("data:image/png;base64"), "smoke runner verifies HTML embedded images")

if failures.isEmpty {
    print("All macOS export smoke CLI checks passed.")
} else {
    print("\nFailures: \(failures.count)")
    exit(1)
}
