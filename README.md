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


## 多样风格
<img width="2048" height="1360" alt="image" src="https://github.com/user-attachments/assets/4b8509ad-1e20-4869-90db-240acd1d9d78" />


### 清读风格
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/72dba7ee-cd6b-4a1d-9a2f-068d1f11fa82" />


### 纸页风格
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/ec28f345-9d39-43f4-a622-a82f5caf484f" />


### 报告风格
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/56e3f4bd-62f6-443d-a8a9-c7acc6f22c1e" />


### 讲义风格
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/1e99e83a-4052-4279-af27-4730f4245354" />


### 卡片风格
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/1779aad5-0da3-46ee-8984-5a014f8eb7ee" />

## 快速导出美观可视化的文件 - PDF、MD、长图、HTML

<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/6b457afd-a470-4350-85ea-c314f8478723" />


## 快速编辑
<img width="3352" height="2168" alt="image" src="https://github.com/user-attachments/assets/d8e0f1ff-34ea-413e-a7ff-aed5e7b9ee06" />


## 当前状态

- macOS：已可用（SwiftUI 原生）
- Windows：已可用（Tauri + WebView2，与 macOS 共享设计语言）
- iOS：开发中

## 安装

### macOS

[下载 MarkGo for macOS](https://github.com/Oreo992/MarkGO/releases/latest/download/MarkGo-1.0.0-mac.dmg)

打开 DMG 后，把左边的 `MarkGo.app` 拖到右边的 `Applications`。

如果 macOS 拦截首次打开，右键 `MarkGo`，选择“打开”。

### Windows

在 [Releases](https://github.com/Oreo992/MarkGO/releases) 里找到 `win-v*` 版本，下载安装程序：

- `MarkGo_*_x64-setup.exe` — NSIS 安装程序（推荐）
- `MarkGo_*_x64_en-US.msi` — MSI 安装程序

双击安装即可。首次运行若缺少 WebView2 运行时，安装程序会自动引导安装（Windows 10/11 通常已内置）。


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

### Windows（Tauri）

```bash
cd MarkdownReaderWin
npm install

# 仅 Web UI，可在任意浏览器中预览（追加 ?demo 加载示例文档）
npm run dev            # http://localhost:5179

# 完整 Tauri 应用（需要 Rust 工具链 + WebView2，在 Windows 上运行）
npm run tauri:dev
npm run tauri:build    # 生成 .msi / NSIS .exe 安装包
```

Windows 安装包也可由 CI 自动构建：推送 `win-v*` 标签会触发
[`.github/workflows/windows-release.yml`](.github/workflows/windows-release.yml)，
在 Windows runner 上打包并发布到 Releases。

## 项目结构

```text
MarkdownReaderMac/          macOS 应用源码（SwiftUI）
MarkdownReaderWin/          Windows 应用源码（Tauri + TypeScript）
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

## 持续更新中
各项细节正在优化迭代中，欢迎各位大佬提Issue和优化建议，感谢！

## License

MIT

基于 [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) 构建。
