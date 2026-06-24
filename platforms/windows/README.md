# MarkGo for Windows

Windows build of **MarkGo**, the Markdown reader & presenter. Built with a
**Tauri (Rust)** shell hosting a **WebView2** renderer, so the binary stays
small and launches fast while keeping the warm editorial design language of the
macOS app.

The macOS app (`platforms/macos/MarkGo/`, SwiftUI) and this Windows app coexist:
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

- Frameless window with a fully custom title bar — no native Windows chrome
- Self-drawn menu bar (文件 / 编辑 / 视图 / 帮助) replacing the OS application menu
- Custom minimize / maximize / close controls, draggable title, recreated edge resize
- Five reading modes — 清读 · 纸页 · 报告 · 讲义 · 卡片 (width, spacing, tone)
- Live editor with split / source / preview layouts and a formatting toolbar
- Outline sidebar with scroll-sync + document stats
- Recent files, syntax highlighting (highlight.js), GFM tables, task lists, Mermaid diagrams
- Export to PDF (paginated), long image (PNG), HTML (self-contained), Markdown
- Adjustable reading font scale

## Window chrome architecture

The window is frameless (`decorations: false` in `tauri.conf.json`). The whole
top bar is HTML so it can stay on-brand and unified:

| Piece | Source |
| --- | --- |
| Menu bar model + renderer (文件/编辑/视图/帮助) | `src/menus.ts` |
| Window controls, drag, resize handles, external links | `src/window.ts` |
| Recent files (localStorage) | `src/recent.ts` |
| Title bar / menu / control styling | `src/styles/chrome.css` |
| Bar assembly + wiring + about modal | `src/main.ts` (`chromeHtml` / `wireChrome`) |

Native window permissions (minimize / maximize / start-dragging /
start-resize-dragging / close) are granted in `src-tauri/capabilities/default.json`.

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

## Auto-update & releasing

The app self-updates via the Tauri updater plugin: on launch (and from
帮助 ▸ 检查更新) it reads `latest.json` from the GitHub *latest* Release,
verifies the signature against the embedded public key
(`plugins.updater.pubkey` in `tauri.conf.json`), then downloads + installs the
signed package and relaunches.

**One-time setup (already done in this repo):**

1. A signing keypair was generated (`tauri signer generate`). The **public** key
   lives in `tauri.conf.json`; the **private** key is a repo secret.
2. Repo secret `TAURI_SIGNING_PRIVATE_KEY` holds the private key contents
   (`TAURI_SIGNING_PRIVATE_KEY_PASSWORD` too, only if the key has a password).
3. `bundle.createUpdaterArtifacts: true` makes `tauri build` emit the signed
   `*.sig` bundles + `latest.json`, which `tauri-action` attaches to the Release.

**Cutting a release** (bumps the version in package.json, tauri.conf.json,
Cargo.toml, Cargo.lock, then commits + tags):

```bash
node scripts/release-win.mjs 1.0.1 --push
```

Pushing the `win-v1.0.1` tag runs `.github/workflows/windows-release.yml`,
which builds the signed installers and publishes a GitHub Release. Installed
copies on an older version pick it up automatically. The new version must be
**higher** than what users have installed for the update to trigger.
