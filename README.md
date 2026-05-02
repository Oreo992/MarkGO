# MarkLens

> 让别人发来的 `.md`，第一秒就变成一篇可阅读的成品；让 AI 输出的 Markdown，能被直接当作 PDF、长图、富文本发出去。

MarkLens 是一个开源的 Markdown 阅读与呈现工具。它有两个版本，共享同一套设计语言：

- **MarkLens for iOS** — 收到 `.md` 之后，在手机上立刻变成漂亮的阅读体验。
- **MarkLens for macOS** — 在 Mac 上提供更大的画布、更强的编辑器，并且**无需通过 App Store**，下载即可使用。

本仓库包含两个独立的 Xcode 工程，你可以单独构建任何一个。

---

## 它解决什么问题

Markdown 正在从「写作者主动使用的格式」变成「AI 和工具大量生成、普通用户被动接收的内容格式」。但是：

- 别人发来的 `.md` 在大多数系统里**没有默认打开体验**，要么显示原始文本，要么需要装一个开发者向的编辑器。
- AI 生成的 Markdown 想转发给老板/同事/读者时，对方往往**看不懂格式**或**复制后排版混乱**。

MarkLens 的产品定位是 **Markdown Reader & Presenter**：

```
打开 .md → 美观阅读 → 选择呈现形态 → 分享成 PDF / 长图 / HTML / 富文本
```

---

## 核心特性

### 五种阅读形态

同一份 Markdown，可以瞬间切换为五种「内容身份」：

| 形态 | 适合 | 视觉特征 |
| --- | --- | --- |
| **文章** | AI 回答、博客、说明文 | 网页文章质感，Teal 强调色 |
| **手册** | README、API 文档、技术方案 | 更宽内容区、稳重灰蓝 |
| **书本** | 长文、小说、教程 | 暖纸张背景、章节排版 |
| **报告** | 周报、调研、咨询材料 | 紫色调，封面式排版 |
| **卡片** | 社媒、知识卡、金句摘要 | 每节一张卡片 |

### 三层产品结构

- **打开层**：`.md` 文件类型注册、Finder 双击、拖拽、剪贴板、`open` 命令、URL handler
- **呈现层**：高级中文排版、目录侧栏、阅读进度、深色背景适配、字号调节
- **交付层**：PDF / 长图（750/1080/1440） / HTML / Markdown / 复制富文本 / 复制纯文本

### macOS 增强

相比 iOS 版，Mac 版利用更大的画布和键盘做了几件事：

- **三栏布局**：左侧大纲 + 工作模式切换 + 主区域
- **三模式编辑器**：源码 / 分屏 / 预览，基于 `NSTextView` 的原生编辑（撤销、查找、智能输入全部可用）
- **完整的菜单栏与快捷键**：所有阅读形态都有 `⌘⌥1..5`，导出都有 `⌘⇧P/I/H/R/C`
- **多窗口**：每份文档独立窗口，可并排
- **拖拽**：把 `.md` 直接拖到 Library 窗口任意位置即可打开
- **拖拽文本**：把任意 Markdown 文本片段拖入也能即刻预览

---

## 下载并运行（无需 App Store）

每次发版都会在 [Releases](https://github.com/) 页面提供两种文件：

- `MarkLens-x.y.z-mac.dmg` — 双击挂载，把 `MarkLens.app` 拖到 `/Applications/`
- `MarkLens-x.y.z-mac.zip` — 解压后直接得到 `MarkLens.app`

> ⚠️ 应用使用 **ad-hoc 签名**（开源项目，不通过 Apple Developer Program 公证），因此**首次启动需要绕过 Gatekeeper 提示**。任选一种方式：

### 方式 A：右键 → 打开（推荐）

1. 把 `MarkLens.app` 放到 `/Applications/`
2. 在 Finder 里**按住 Control 点击**它，选择 **打开**
3. 在弹出的提示中再点击 **打开**
4. 之后双击启动即可

### 方式 B：终端命令

```bash
xattr -dr com.apple.quarantine /Applications/MarkLens.app
open /Applications/MarkLens.app
```

> 这两种方式都是 macOS 标准的「绕过未公证应用」流程，与你下载任何开源 Mac 软件时的操作一致。

---

## 从源码构建

### 系统要求

- macOS 14 (Sonoma) 或更高
- Xcode 15.0+ / Swift 5.9+
- 其他依赖通过 Swift Package Manager 自动获取（[swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui)）

### 命令行构建

仓库提供了 `scripts/build-mac.sh`，一条命令完成构建、ad-hoc 签名、打包：

```bash
./scripts/build-mac.sh
```

产物：

```
dist/
  MarkLens-1.0.0-mac.dmg    # 拖拽安装包
  MarkLens-1.0.0-mac.zip    # 直接解压版本
```

构建结果是 **Universal Binary**（同时支持 Apple Silicon 与 Intel）。

```bash
./scripts/build-mac.sh --debug      # Debug 配置
./scripts/build-mac.sh --skip-dmg   # 只产 zip
./scripts/build-mac.sh --skip-zip   # 只产 dmg
```

### 在 Xcode 中开发

```bash
open MarkdownReaderMac.xcodeproj
```

选择 `MarkLens` scheme，目标 `My Mac`，按 ⌘R 运行。

---

## 测试

仓库内置两层非交互测试：

```bash
# 集成测试：构建产物完整性 + 启动 + 文档打开 + 持久化
./test-fixtures/run-headless-tests.sh

# Markdown 解析单元测试
swift test-fixtures/test-markdown-analysis.swift
```

预期输出：23 项全部通过。

---

## 项目结构

```
MarkdownReaderApp/
├── MarkdownReaderApp/             # iOS 应用源代码
├── MarkdownReaderApp.xcodeproj/
│
├── MarkdownReaderMac/             # macOS 应用源代码
│   ├── App/                       # 入口、菜单与命令
│   ├── Documents/                 # FileDocument
│   ├── Design/                    # 配色与 Markdown 主题
│   ├── Models/                    # 解析 / 阅读模式 / 最近文档
│   ├── Features/
│   │   ├── Library/               # 首页（最近 + 三大入口）
│   │   ├── Reader/                # 文档窗口（侧栏 + 阅读区）
│   │   ├── Editor/                # 源码 / 分屏 / 预览编辑
│   │   └── Export/                # PDF / 长图 / HTML 渲染
│   └── Resources/                 # Info.plist + entitlements
├── MarkdownReaderMac.xcodeproj/
│
├── scripts/build-mac.sh           # 一键构建 + 签名 + 打包
├── test-fixtures/                 # 集成与单元测试
├── Docs/design.md                 # 完整产品设计稿
└── dist/                          # 发布产物（被 .gitignore 忽略）
```

iOS 与 macOS 各自独立，但共享 5 种阅读形态、配色、主题、Markdown 解析的设计原则。

---

## 设计哲学

- **One second from file to finished work** — 打开 Markdown 就该立刻看到漂亮的阅读界面，不是源码。
- **Reader first, presenter second, editor later** — 先服务「打开 / 阅读 / 转交」，再考虑写作功能。
- **Content shape over skin** — 切换的是「文章 / 手册 / 书本 / 报告 / 卡片」这种**内容身份**，而不是配色主题。
- **Mobile Markdown needs craft** — 中文排版、标点挤压、中英文混排、代码块、表格、长文导航都是核心而非附加。
- **System-native, not generic** — 充分利用 iOS 与 macOS 的系统能力（DocumentGroup、文件类型、`NSTextView`、菜单栏、拖拽），不做又一个跨平台 Electron 壳。

完整的产品设计文稿请见 [Docs/design.md](Docs/design.md)。

---

## 路线图

- [x] 五种阅读形态
- [x] PDF / 长图 / HTML 导出
- [x] 中英文混排排版
- [x] 大纲侧栏 + 字号调节
- [x] 三模式编辑器
- [ ] Mermaid / LaTeX 渲染
- [ ] 代码块语法高亮
- [ ] 暗色模式
- [ ] 长图分页与卡片组模板
- [ ] 自动识别内容形态（文章 / 文档 / 报告 / …）
- [ ] AI Markdown 清洗

---

## 许可证

MIT License — 见 [LICENSE](LICENSE)。

第三方依赖：

- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — MIT
- [swift-cmark](https://github.com/swiftlang/swift-cmark) — BSD-2-Clause（cmark 上游同许可）

---

## 致谢

感谢 [@gonzalezreal](https://github.com/gonzalezreal) 提供高质量的 SwiftUI Markdown 渲染库。
