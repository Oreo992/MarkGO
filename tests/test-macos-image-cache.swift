// Headless source-level check for macOS local image loading performance.
//
// The reader and export paths should share one bounded image cache and
// downsample large local images before handing them to SwiftUI. Regressing
// to scattered NSImage(contentsOf:) calls is easy to miss manually because
// it only hurts with long, image-heavy documents.

import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let cacheURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Models/MarkdownImageCache.swift")
let readerURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Reader/ReaderSurface.swift")
let exportURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo/Features/Export/ExportRunner.swift")
let projectURL = repoRoot.appendingPathComponent("platforms/macos/MarkGo.xcodeproj/project.pbxproj")

var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("✔ \(message)")
    } else {
        print("✘ \(message)")
        failures.append(message)
    }
}

let cacheSource = (try? String(contentsOf: cacheURL, encoding: .utf8)) ?? ""
let readerSource = try String(contentsOf: readerURL, encoding: .utf8)
let exportSource = try String(contentsOf: exportURL, encoding: .utf8)
let projectSource = try String(contentsOf: projectURL, encoding: .utf8)

expect(!cacheSource.isEmpty, "macOS has a shared MarkdownImageCache source file")
expect(cacheSource.contains("final class MarkdownImageCache"), "image cache has one concrete shared loader")
expect(cacheSource.contains("static let shared"), "image cache exposes a shared instance")
expect(cacheSource.contains("NSCache<NSURL, NSImage>"), "image cache keeps decoded images in a bounded NSCache")
expect(cacheSource.contains("countLimit"), "image cache limits retained image count")
expect(cacheSource.contains("totalCostLimit"), "image cache limits retained memory cost")
expect(cacheSource.contains("CGImageSourceCreateThumbnailAtIndex"), "image cache downsamples oversized local images")
expect(cacheSource.contains("kCGImageSourceCreateThumbnailFromImageAlways"), "image cache creates thumbnails instead of decoding full-size originals")
expect(cacheSource.contains("maxPixelSize"), "image cache caps exported and reader image dimensions")

expect(readerSource.contains("MarkdownImageCache.shared.image"), "reader image provider uses the shared cache")
expect(exportSource.contains("MarkdownImageCache.shared.image"), "export image providers use the shared cache")
expect(!readerSource.contains("NSImage(contentsOf:"), "reader no longer decodes local images inline")
expect(!exportSource.contains("NSImage(contentsOf:"), "export no longer decodes local images inline")
expect(projectSource.contains("MarkdownImageCache.swift in Sources"), "macOS target compiles the shared image cache")

if failures.isEmpty {
    print("All macOS image cache checks passed.")
} else {
    print("\nFailures: \(failures.count)")
    exit(1)
}
