# MarkGo

<img src="../platforms/macos/MarkGo/Resources/Assets.xcassets/MarkGoLogo.imageset/markgo-logo.png" width="96" alt="MarkGo logo">

MarkGo is a lightweight Markdown previewer for macOS.

It turns raw `.md` files into clean, readable pages. Use it for AI-generated content, README files, notes, briefs, reports, and any Markdown document you need to read quickly.

## Why MarkGo

Markdown is everywhere now.

AI tools often use Markdown to return answers, organize research, and generate documents. People are also sharing more `.md` files directly. The problem: Markdown is friendly to machines and text editors, but not always friendly to fast human reading. Headings, tables, code, quotes, and images are mixed into source text.

MarkGo sits between Markdown source and human readability. Open a file, get a readable page.

## What You Can Do

- Open `.md` files from Finder or drag and drop
- Switch between source, split, and preview modes
- Read headings, quotes, tables, code blocks, task lists, and local images
- Navigate long documents with an outline
- Adjust font size and reading style
- Export PDF, long image, HTML, rich text, plain text, and Markdown

## Status

- macOS: available
- iOS: in development

## Install

[Download MarkGo for macOS](https://github.com/Oreo992/MarkGO/releases/latest/download/MarkGo-1.0.0-mac.dmg)

Open the DMG, then drag `MarkGo.app` into `Applications`.

If macOS blocks the first launch, right-click `MarkGo` and choose Open.

## Development

Open the project:

```bash
open platforms/macos/MarkGo.xcodeproj
```

Select the `MarkGo` scheme and run on `My Mac`.

Build a local installer:

```bash
./scripts/build-mac.sh
```

Build outputs are generated in `dist/`, which is not committed to the source repository.

## Project Layout

```text
platforms/macos/            macOS app source (SwiftUI)
platforms/ios/              iOS app source, in development
platforms/windows/          Windows app source (Tauri + TypeScript)
brand/                      brand icon source assets
docs/                       design notes and English README
scripts/                    local build and packaging scripts
tests/                      smoke tests and sample documents
```

## Test

```bash
./tests/run-headless-tests.sh
swift tests/test-markdown-analysis.swift
```

## License

MIT

Built with [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui).
