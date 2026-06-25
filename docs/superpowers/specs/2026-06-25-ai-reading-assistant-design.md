# MarkGo AI 阅读助手 — 设计文档

- 日期：2026-06-25
- 平台：Windows（Tauri + WebView2 + TypeScript）；macOS 暂不做
- 状态：已通过 brainstorming，待写实现计划

## 1. 目标与范围

给 MarkGo（Windows）加一个 **AI 阅读助手**，定位贴合产品「别人发我一个 `.md`，我要快速读懂」的头号场景。

v1 能力（全部**手动触发**，绝不在打开文档时自动调用，避免偷烧 BYOK token）：

- **一键摘要** — 把整篇文档压缩成 2–4 段概要
- **提炼要点 / 行动项** — 输出项目符号要点；含任务的另列「行动项」
- **自由问答（对话）** — 就当前文档多轮提问，回答基于文档内容接地

**不在 v1**（YAGNI，可后续加）：翻译、选区浮出菜单、写作/续写、分块检索（RAG）、本地模型、跨平台移植。

成功标准：用户配好自己的 API key 后，能在右侧面板对当前文档一键摘要 / 提要点 / 多轮问答，输出以 Markdown 渲染、流式逐字呈现，整体观感与 app 现有暖色编辑风一致。

## 2. 关键决策（已确认）

| 决策 | 选择 |
| --- | --- |
| v1 定位 | 阅读助手（摘要 / 要点 / 问答） |
| 平台 | 先只做 Windows |
| 接入方式 | BYOK（用户自备 API key） |
| 提供方 | 同时支持 Anthropic + OpenAI（provider 抽象 + 两适配器） |
| UI 形态 | 右侧可开关 AI 面板 |
| 网络调用 | **方案 A**：Rust 侧 reqwest 流式请求 → 事件回传 WebView |
| 触发方式 | 全部手动（点按钮 / 主动提问），无自动调用 |
| 密钥存放 | Rust 侧本地配置文件，网页层永不持有 key |

## 3. 架构

新增模块，不改动现有阅读 / 导出 / 窗口逻辑：

```
platforms/windows/
  src/ai/
    client.ts      调 Rust 命令 + 监听流式事件；暴露 streamChat({onDelta,onDone,onError}) → {cancel}
    prompts.ts     系统提示 + 文档接地 + 三种动作指令（纯函数，可单测）
    panel.ts       右侧 AI 面板渲染与交互（对话状态、快捷动作、输入框、流式追加）
    settings.ts    AI 设置弹窗（provider / model / baseURL / key）
    types.ts       共享类型（Message、Provider、AiStatus 等）
    styles/ai.css  面板与设置样式（沿用暖色 token + 玻璃材质）
  src-tauri/src/
    ai.rs          provider 抽象 + 4 个命令 + SSE 解析 + 事件
```

`main.ts` 仅做接线：渲染面板容器、顶栏 AI 开关、菜单项，把面板挂到 workspace 右列。

### 3.1 密钥安全（核心约束）

API key **只存在 Rust 侧**（`appConfigDir/ai-config.json`），WebView 永远拿不到 key。

- 保存：设置弹窗 → `ai_set_config(provider, model, base_url, key)` → Rust 写盘
- 状态：`ai_get_status()` 只回 `{provider, model, has_key}`，**不回 key**
- 请求：`ai_stream(...)` 时 Rust 自己从配置读 key，网页只传「对话内容」

### 3.2 数据流（以「一键摘要」为例）

```
点[摘要] → panel 组装 messages（系统提示含整篇文档）→ client.streamChat
  → invoke ai_stream(requestId, messages, system, maxTokens)
     → Rust 读 key → reqwest 流式 POST Anthropic/OpenAI → 逐行解析 SSE
        → emit "ai://chunk" {requestId, delta}
  → panel 把 delta 实时追加到 AI 气泡（用现有 markdown 渲染美化）
  → emit "ai://done" {requestId} 收尾 / "ai://error" {requestId, message} 显示错误 + 重试
取消：ai_cancel(requestId)
```

### 3.3 布局

阅读区右侧新增可开关一列：`左侧目录 | 阅读内容 | AI 面板`。内容区宽度自适应收窄。开关在顶栏右区（一个「✦ AI」按钮，有对话时点亮）+ 视图菜单「AI 助手」。

## 4. Rust 侧（`ai.rs`）

**依赖**：`reqwest`（`stream` + `rustls-tls`）、`tokio`、`futures-util`。

**配置**：

```rust
struct AiConfig { provider: String, model: String, base_url: Option<String>, api_key: String }
// 持久化到 appConfigDir/ai-config.json；api_key 只进不出
```

**命令**：

| 命令 | 作用 |
| --- | --- |
| `ai_set_config(provider, model, base_url, key)` | 写配置到盘 |
| `ai_get_status() -> {provider, model, has_key}` | 状态查询，无 key |
| `ai_stream(request_id, messages, system, max_tokens)` | 起异步任务，流式调用，emit 事件 |
| `ai_cancel(request_id)` | 取消进行中的请求 |

**Provider 抽象**（两家差异收敛一处）：

```rust
trait Provider {
  fn endpoint(&self, base: Option<&str>) -> String;      // anthropic: https://api.anthropic.com/v1/messages
                                                          // openai: {base|https://api.openai.com}/v1/chat/completions
  fn headers(&self, key: &str) -> HeaderMap;             // anthropic: x-api-key + anthropic-version
                                                          // openai: Authorization: Bearer
  fn body(&self, messages, system, max_tokens) -> Value; // 两家 JSON 形状不同
  fn parse_sse(&self, line: &str) -> Option<String>;     // anthropic: content_block_delta.delta.text
                                                          // openai: choices[0].delta.content
}
```

**流式 + 事件**：异步任务里 `while let Some(chunk) = stream.next()` → 按 `\n` 累积解析 SSE `data:` 行 → 每个文本 delta `window.emit("ai://chunk", {request_id, delta})`；流结束 emit `ai://done`；任何错误 emit `ai://error {request_id, message}`。

**取消**：`Mutex<HashMap<String, AbortHandle>>`（或 `tokio_util::CancellationToken`）存活跃请求；`ai_cancel` 触发中止并清理。

**权限**：`capabilities/default.json` 加 `core:event:default`（emit/listen）。因 Rust 出网、WebView 不直连 API，**CSP `connect-src` 无需**为 API 域名放开。

**注册**：4 个命令加入 `invoke_handler`，沿用现有 builder。

## 5. TS 面板（交互 + 外观）

**结构**：

```
┌─ AI 助手 ──────────── ⚙ ✕ ┐   头部：标题 + 设置 + 关闭
│ [✦ 摘要] [☰ 要点 / 行动项]  │   快捷动作 chip（accent 描边）
├──────────────────────────┤
│  对话区（可滚）             │   用户气泡（右，实色）/ AI 气泡（左，暖纸，markdown 渲染）
├──────────────────────────┤
│ [输入问题…        ] [发送] │   Enter 发送；流式时「发送」变「停止」
└──────────────────────────┘
```

**交互**：

- 快捷动作即点即答：点[摘要]自动塞一条用户消息并流式回答；[要点/行动项]同理。
- 流式：AI 气泡逐字追加，带闪烁光标；输出中按钮变「停止」（`ai_cancel`）。
- **AI 输出复用现有 `markdown.ts` 渲染**，所以摘要 / 要点是带层级、加粗、列表的漂亮排版，而非纯文本——直接达到「和 app 一样好看」。
- 空状态：未配置 key → 面板中央「先配置 AI」+「打开设置」；已配置无对话 → 两个快捷动作 + 一句引导。
- 会话绑定当前文档：切换 / 重开文档清空对话，避免串文档。

**外观**：面板宽 ~320px；chip / 气泡 / 输入框全用 `--accent`、`--paper`、`--line` 与玻璃 token，圆角阴影对齐现有面板。

## 6. 设置弹窗（`settings.ts`）

复用 about 弹窗玻璃样式：

- 提供方：Anthropic / OpenAI（单选）
- 模型：文本框带默认值（如 `claude-opus-4-...` / `gpt-4o`），可改
- Base URL：可选（OpenAI 兼容 / 代理留口子）
- API Key：密码框；保存 → `ai_set_config`；已配置显示「已配置 ✓」，不回显
- 入口：面板头部 ⚙ + 菜单「AI 设置…」

## 7. 提示词（`prompts.ts`，纯函数）

- 系统提示统一接地：「你是阅读助手。仅依据下面这篇文档作答，中文回答，不编造文档外内容。」+ 文档全文
- 摘要：「用 2–4 段简洁概括要点。」
- 要点 / 行动项：「提炼关键要点为项目符号；若含任务 / 待办，另列『行动项』。」
- 问答：用户原始问题

## 8. 超长文档

v1 整篇随系统提示发送（现代模型上下文足够装多数 `.md`）。超过软上限（约 12 万字符）→ 截断并在面板提示「文档较长，已截取前部分」。不做分块检索（YAGNI）。

## 9. 隐私

首次使用 AI 弹一次性提示：「AI 会把当前文档内容发送给你配置的服务商（Anthropic / OpenAI）处理。」+ 确认。记 consent 标记，之后不再弹。

## 10. 错误处理

- 未配置 key → 空状态引导去设置
- 401 / 网络 / 限流 → AI 气泡显示友好错误 + 「重试」
- 流式中途取消 → 干净结束，保留已生成部分

## 11. 测试

- 纯 TS 单测：`prompts.ts`（提示词组装）、SSE delta 的 TS 侧映射
- Rust 单测：两家 provider 的 `body` 形状、`parse_sse` 各自格式（`#[cfg(test)]`）
- 放 `tests/`，沿用项目「独立脚本」风格（node `.mjs` + Rust 单测）

## 12. 不做（v1 明确排除）

翻译、选区浮出菜单、写作 / 续写、RAG 分块检索、本地模型、跨平台移植、AI 配额 / 付费墙、对话历史持久化（关闭即清）。

## 13. 涉及改动文件一览

- 新增：`src/ai/{client,prompts,panel,settings,types}.ts`、`src/ai/styles/ai.css`、`src-tauri/src/ai.rs`
- 修改：`src/main.ts`（接线面板 / 开关 / 菜单）、`src/menus.ts`（AI 助手 + AI 设置项）、`src-tauri/src/lib.rs`（注册命令 + mod ai）、`src-tauri/Cargo.toml`（reqwest 等依赖）、`capabilities/default.json`（event 权限）、`tests/`（新增单测）
