# Contributing to MarkLens

Thanks for your interest in MarkLens. This project keeps a few practices that
make collaboration easier.

## Quick Start

```bash
git clone https://github.com/<your-fork>/MarkdownReaderApp.git
cd MarkdownReaderApp

# Build the macOS app
./scripts/build-mac.sh

# Or open in Xcode
open MarkdownReaderMac.xcodeproj
```

## Repository Layout

- `MarkdownReaderApp/` — iOS app
- `MarkdownReaderMac/` — macOS app
- `scripts/` — Build, sign, package
- `test-fixtures/` — Smoke tests and Markdown samples
- `Docs/` — Long-form product design notes

## Development

### macOS

```bash
xcodebuild \
  -project MarkdownReaderMac.xcodeproj \
  -scheme MarkLens \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

### iOS

```bash
xcodebuild \
  -workspace MarkdownReaderApp.xcworkspace \
  -scheme MarkdownReaderApp \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build
```

## Testing

```bash
# Headless integration tests for the macOS bundle
./test-fixtures/run-headless-tests.sh

# Markdown analyzer unit tests
swift test-fixtures/test-markdown-analysis.swift
```

A green run is required before opening a PR.

## Style

- Swift `5.0` syntax; Swift Concurrency where it improves clarity.
- 4-space indentation.
- File-private types are preferred over global ones for view-local helpers.
- Comments explain *why*, not *what*. The code itself is the *what*.
- Strings shown to users follow the iOS app's tone: short, declarative,
  Chinese where the iOS app uses Chinese.

## Pull Requests

- Keep PRs focused. One product change per PR.
- Update README.md if you change distribution flow or shortcut keys.
- Add a screenshot if you change UI surfaces.
- Run both test scripts above and paste the result in the PR description.

## Reporting Issues

Please include:

- macOS or iOS version
- Reproduction steps with a sample Markdown file when relevant
- Whether the app is launched from `/Applications/` or a built artifact
- Output from the headless test script if a build/launch issue is suspected
