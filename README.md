# MarkGo

<img src="MarkdownReaderMac/Resources/Assets.xcassets/MarkGoLogo.imageset/markgo-logo.png" width="96" alt="MarkGo logo">

[English](Docs/README.en.md)

MarkGo 是一个轻量的 Markdown 预览器。

它把 `.md` 源码变成干净、好读、可分享的页面。适合阅读 AI 生成的内容、README、笔记、方案、报告和任何 Markdown 文件。

## 为什么需要 MarkGo

Markdown 正在变多。

在 AI 时代，模型经常用 Markdown 输出答案、整理资料、生成文档。人和人之间传文件，也越来越常见 `.md`。问题是：Markdown 很适合机器和文本编辑器处理，却不适合人快速阅读。标题、表格、代码、引用、图片混在源码里，扫一眼很难抓住重点。

MarkGo 做的事很简单：站在 Markdown 源码和人的阅读之间，把文件快速变成可看的页面。

## 你可以用它做什么

- 双击或拖入 `.md` 文件，立即预览
- 在源码、分屏、预览之间切换
- 阅读标题、引用、表格、代码块、任务列表和本地图片
- 用大纲快速跳转长文档
- 调整字号和阅读样式
- 导出 PDF、长图、HTML、富文本、纯文本和 Markdown

## 当前状态

- macOS：已可用
- iOS：开发中

## 安装

[下载 MarkGo for macOS](https://github.com/Oreo992/mark-go/releases/latest/download/MarkGo-1.0.0-mac.dmg)

打开 DMG 后，把左边的 `MarkGo.app` 拖到右边的 `Applications`。

如果 macOS 拦截首次打开，右键 `MarkGo`，选择“打开”。

## 开发

打开项目：

```bash
open MarkdownReaderMac.xcodeproj
```

选择 `MarkGo` scheme，在 `My Mac` 上运行。

本地构建安装包：

```bash
./scripts/build-mac.sh
```

构建产物会生成到 `dist/`，该目录不进入源码仓库。

## 项目结构

```text
MarkdownReaderMac/          macOS 应用源码
MarkdownReaderApp/          iOS 应用源码，开发中
Brand/                      品牌图标源素材
Docs/                       设计说明和英文 README
scripts/                    本地构建和打包脚本
test-fixtures/              轻量测试和样本文档
```

## 测试

```bash
./test-fixtures/run-headless-tests.sh
swift test-fixtures/test-markdown-analysis.swift
```

## License

MIT

基于 [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) 构建。
