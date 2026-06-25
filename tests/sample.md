# MarkGo 功能验证文档

这是一份用于功能测试的 Markdown，覆盖标题层级、段落、列表、引用、代码、表格、链接等核心元素。

**## 一、典型产品文档**

> MarkGo 的目标：让别人发来的 .md，第一秒就变成一篇可阅读的成品；让 AI 输出的 Markdown，能被直接当作 PDF、长图、富文本发出去。

### 1. 五种阅读形态

- **文章** · 网页文章质感，默认模式
- **手册** · 技术文档手册，更宽内容区与代码块
- **书本** · 电子书排版，纸张感更强
- **报告** · 正式报告封面，紫色调
- **卡片** · 可分享卡片组，每节一张

### 2. 三层架构

| 层级 | 职责 | 关键体验 |
| --- | --- | --- |
| 打开层 | 让 .md 在 macOS 有可靠入口 | Finder 双击、拖拽、剪贴板 |
| 呈现层 | 让 Markdown 看起来不像源代码 | 五种阅读形态 + 中文排版 |
| 交付层 | 让用户把它发出去 | PDF / 长图 / HTML / 复制 |

## 二、代码示例

下面是一段 Swift 代码，用于展示代码块渲染：

```swift
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.markdown, .plainText, .text]
    }

    var text: String

    init(text: String = "") {
        self.text = text
    }
}
```

行内代码示例：通过 `Cmd+E` 在阅读和编辑模式之间切换，通过 `Cmd+Option+1...5` 切换阅读形态。

## 三、列表与任务

普通列表：

1. 打开 .md（File → Open 或 ⌘O）
2. 选择阅读形态（顶部胶囊或 ⌘⌥1-5）
3. 切换到编辑模式调整内容（⌘E）
4. 导出 PDF / 长图 / HTML（⌘⇧P / ⌘⇧I / ⌘⇧H）

任务列表：

- [x] 五种阅读形态
- [x] 增强的编辑器（源码 / 分屏 / 预览）
- [x] PDF / 长图 / HTML / Markdown 导出
- [x] 中文排版优化
- [x] 拖拽与文件类型注册

## 四、长引用

> 内容的呈现形式会改变用户对内容价值的感知。同一段文字，放在纯文本里像草稿，放在书本样式里像作品，放在报告样式里像正式材料，放在卡片样式里像可传播内容。

## 五、链接与分隔

更多信息请参见 [设计文档](https://example.com/design)。

---

## 六、中英文混排

This is a paragraph mixing 中文和英文 with some `inline code` to verify spacing rules. 长篇 AI generated content often contains 中英混排, 数字 1234, 专有名词 like ChatGPT、Claude、GitHub，should all read comfortably.

## 总结

MarkGo 把 .md 从源文件变成可阅读、可分享、可交付的成品。下载即用，开源免费，无需 App Store。
