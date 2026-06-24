// Sample document shown on first launch / browser preview so the five reading
// modes can be demonstrated without opening a file.

export const DEMO_MARKDOWN = `# MarkGo for Windows

一个为 Windows 打造的 Markdown 阅读与演示器，与 macOS 版共享同一套编辑设计语言：温暖的纸感画布、深墨文字、克制的宝石色强调。

> 同一篇 Markdown，可以在五种**阅读形态**之间切换——清读、纸页、报告、讲义、卡片。每一种都改变宽度、间距与排版气质。

## 为什么用 Tauri

- **极致启动** — Rust 外壳 + 系统 WebView2，安装包仅几 MB，冷启动通常在 1 秒内。
- **高度一致** — 渲染核心是 Web 技术，方便与导出的 HTML 完全对齐。
- **原生能力** — 文件读写、对话框、导出都走原生 Rust 命令。

### 行内排版

支持 **加粗**、*斜体*、~~删除线~~、\`行内代码\` 与 [链接](https://example.com)。中文与西文混排时保持舒适的行高与字距。

## 代码与高亮

\`\`\`typescript
function greet(name: string): string {
  return \`你好，\${name}！\`;
}

console.log(greet("MarkGo"));
\`\`\`

## 表格

| 特性 | macOS | Windows |
| --- | --- | --- |
| 阅读模式 | 5 种 | 5 种 |
| 实时编辑 | 支持 | 支持 |
| 导出 PDF / 长图 / HTML | 支持 | 支持 |

## 任务清单

- [x] 移植设计 token
- [x] 五种阅读模式
- [x] 导出管线
- [ ] 自定义主题编辑器

## 流程图

\`\`\`mermaid
flowchart LR
  A[打开 Markdown] --> B{选择模式}
  B --> C[阅读]
  B --> D[编辑]
  C --> E[导出]
  D --> E
\`\`\`

---

完成。试着在顶部切换阅读模式，或进入编辑模式实时预览。
`;
