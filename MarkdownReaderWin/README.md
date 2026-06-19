# MarkGo for Windows

Windows build of **MarkGo**, the Markdown reader & presenter. Built with a
**Tauri (Rust)** shell hosting a **WebView2** renderer, so the binary stays
small and launches fast while keeping the warm editorial design language of the
macOS app.

The macOS app (`MarkdownReaderMac/`, SwiftUI) and this Windows app coexist:
they share the same design tokens, five reading modes, and export formats, but
each uses the native-best stack for its platform.

## Design parity with macOS

| Aspect | Source of truth | Port |
| --- | --- | --- |
| Palette / per-mode theming | `AppPalette.swift`, `ReadingMode.swift` | `src/styles/tokens.css` |
| Reader rendering | `MarkdownTheme+Custom.swift` | `src/styles/reader.css` |
| Markdown cleanup | `MarkdownAnalysis.swift` | `src/normalize.ts`, `src/analysis.ts` |
| HTML export | `ExportRunner.swift` (`writeHTML`) | `src/export.ts` |
| Outline / editor / export UI | `OutlineSidebar`, `EditorWorkspace`, `ExportPanel` | `src/main.ts` + styles |

## Features

- Five reading modes — 清读 · 纸页 · 报告 · 讲义 · 卡片 (width, spacing, tone)
- Live editor with split / source / preview layouts and a formatting toolbar
- Outline sidebar with scroll-sync + document stats
- Syntax highlighting (highlight.js), GFM tables, task lists, Mermaid diagrams
- Export to PDF (paginated), long image (PNG), HTML (self-contained), Markdown
- Adjustable reading font scale

## Develop

```bash
npm install

# Web UI only (runs in any browser; great for iterating on rendering)
npm run dev            # http://localhost:5179  (append ?demo for sample doc)

# Full Tauri app (requires Rust toolchain + WebView2 on Windows)
npm run tauri:dev
```

## Build

```bash
npm run build          # type-check + bundle the web UI into dist/
npm run tauri:build    # produce the Windows installer (.msi / NSIS .exe)
```

> **Icons:** `tauri build` needs `src-tauri/icons/`. Generate them once with
> `npm run tauri icon path/to/logo.png` (Tauri creates every required size,
> including `icon.ico`).
