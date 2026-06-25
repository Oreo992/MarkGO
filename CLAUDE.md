# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

MarkGo 是一个轻量的 Markdown 阅读与呈现器（Reader & Presenter），把 `.md` 源码变成可阅读、可分享、可交付的漂亮成品。核心闭环：**打开 `.md` → 美观阅读 → 选择呈现形态 → 导出 PDF/长图/HTML/富文本**。

产品设计哲学见 `docs/design.md`：核心不是“渲染得好”，而是让用户“遇到 Markdown 时就用它”——服务的是接收/转发 Markdown 的普通用户，而不只是会写 Markdown 的人。

## 三个平台，各用最佳原生栈

同一套设计语言（design tokens、五种阅读形态、导出格式）在三个独立实现中并存：

| 平台 | 目录 | 技术栈 | 状态 |
| --- | --- | --- | --- |
| macOS | `platforms/macos/` | SwiftUI 原生 + swift-markdown-ui | 已可用 |
| Windows | `platforms/windows/` | Tauri (Rust) 外壳 + WebView2 + TypeScript/Vite | 已可用 |
| iOS | `platforms/ios/` | SwiftUI | 开发中 |

每个平台目录里：Apple 工程为 `MarkGo.xcodeproj` + 同级源码文件夹 `MarkGo/`（iOS 另含 `MarkGo.xcworkspace`）；Windows 是 Tauri 工程根（`src/`、`src-tauri/`、`package.json`）。

**macOS 是设计的事实来源（source of truth）。** Windows 是它的移植。修改任一平台的行为时，注意保持两端对齐——对应关系见下表（也记录在 `platforms/windows/README.md`）。下表 macOS 路径相对 `platforms/macos/MarkGo/`，Windows 路径相对 `platforms/windows/`：

| 关注点 | macOS（事实来源） | Windows（移植） |
| --- | --- | --- |
| 调色板 / 各模式主题 | `Design/AppPalette.swift`、`Models/ReadingMode.swift` | `src/styles/tokens.css` |
| 阅读器渲染 | `Design/MarkdownTheme+Custom.swift` | `src/styles/reader.css` |
| Markdown 清洗 | `Models/MarkdownAnalysis.swift` | `src/normalize.ts`、`src/analysis.ts` |
| HTML 导出 | `Features/Export/ExportRunner.swift`（`writeHTML`） | `src/export.ts` |
| 大纲 / 编辑器 / 导出 UI | `OutlineSidebar`、`EditorWorkspace`、`ExportPanel` | `src/main.ts` + styles |

## 五种阅读形态（ReadingMode）

不是配色皮肤，而是**内容形态**——每种改变宽度、间距、表面结构和排版语气，让同一份 Markdown 成为不同种类的成品：`清读 (clear)` · `纸页 (paper)` · `报告 (report)` · `讲义 (lesson)` · `卡片 (cards)`。macOS 定义在 `Models/ReadingMode.swift`，Windows 在 `src/modes.ts`。修改形态语义时两端都要改。

## 关键约定

- **Markdown 清洗优先。** 输入常来自 LLM 输出或剪贴板，格式很脏。`normalize`（normalizeLine、pipe-table 修复）会在渲染前修复，但**保持代码围栏内容不动**。任何渲染前处理都遵循这个原则。
- **macOS 是双场景应用**：`MarkdownReaderMacApp.swift` 中一个 `WindowGroup`（Library 入口窗口）+ 一个 `DocumentGroup`（文档阅读窗口，注册 `.md` 文件关联）。窗口强制浅色、隐藏标题栏。
- **macOS 强制浅色模式**（`.preferredColorScheme(.light)`）。
- macOS 发行版用 **ad-hoc 签名**（非 App Store、未公证），首次打开需右键→打开或 `xattr -dr com.apple.quarantine`。
- **Windows 是无边框窗口**（`tauri.conf.json` 里 `decorations: false`），整条顶栏（菜单栏 文件/编辑/视图/帮助 + 窗口控制 + 拖拽 + 边缘缩放手柄）全部自绘。菜单模型在 `src/menus.ts`，窗口原生桥接在 `src/window.ts`，样式在 `src/styles/chrome.css`，在 `src/main.ts` 的 `chromeHtml`/`wireChrome` 组装。新增的窗口权限在 `capabilities/default.json`。

## 常用命令

### macOS
```bash
open platforms/macos/MarkGo.xcodeproj   # 打开项目，选 MarkGo scheme，My Mac 运行
./scripts/build-mac.sh             # 构建 + ad-hoc 签名 + 打包 zip/dmg/本地安装器 → dist/
./scripts/build-mac.sh --debug     # debug 构建
./scripts/build-mac.sh --skip-dmg  # 跳过 dmg
```
构建 scheme 名为 `MarkGo`，产物为 Universal（arm64 + x86_64），输出到 `dist/`（不入库）。

### Windows（在 `platforms/windows/` 下）
```bash
npm install
npm run dev          # 仅 Web UI，任意浏览器预览 http://localhost:5179（加 ?demo 载入示例文档）
npm run build        # tsc --noEmit 类型检查 + vite 打包到 dist/
npm run tauri:dev    # 完整 Tauri 应用（需 Rust 工具链 + Windows + WebView2）
npm run tauri:build  # 生成 .msi / NSIS .exe 安装包
```
`npm run dev` 的纯浏览器模式是迭代渲染逻辑最快的方式，无需 Rust/Tauri。`src/platform.ts` 负责在浏览器与 Tauri 运行时之间抽象。

### 测试（macOS，需先 `build-mac.sh` 产出 `.build/export/MarkGo.app`）
```bash
./tests/run-headless-tests.sh         # 无头冒烟测试：启动、文件打开、签名、quarantine 流程
swift tests/test-markdown-analysis.swift   # 单个独立 Swift 测试脚本
```
`tests/` 下每个 `test-*.swift` 是独立可执行脚本，从仓库根运行 `swift tests/<文件>`（导出保真、PDF 流式、图片缓存、Mermaid、编辑器输入性能等）。

## CI

推送 `win-v*` 标签触发 `.github/workflows/windows-release.yml`，在 Windows runner 上构建 Windows 安装包并发布到 Releases。`workflow_dispatch` 手动运行则只上传 artifact 不发版。macOS 包目前由本地 `build-mac.sh` 手工构建。

## 注意

- 仓库里有两个 Xcode 工程：`platforms/macos/MarkGo.xcodeproj`（macOS，开发主入口，scheme `MarkGo`）和 `platforms/ios/MarkGo.xcodeproj`（iOS，开发中，scheme 仍为 `MarkdownReaderApp`）。日常 macOS 开发用前者。
- Tauri Rust 外壳（`src-tauri/src/lib.rs`）很薄，只暴露 `read_markdown` 命令供“打开方式”/拖放启动，其余逻辑都在 TS 前端。
- 较大改动需与本 CLAUDE.md 对齐更新。
