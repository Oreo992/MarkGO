# AI Reading Assistant Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a manual, streaming AI reading assistant (summary · key points · chat-over-document) to MarkGo for Windows, with BYOK keys, an on-brand right-side panel, and LLM calls made from Rust.

**Architecture:** A right-side panel (TypeScript) collects the user's intent and the current document, calls a Rust `ai_stream` command, and renders streamed tokens (emitted as `ai://chunk` events) as Markdown. The API key lives only in a Rust-side config file; the WebView never holds it. Two providers (Anthropic, OpenAI) are abstracted behind one Rust trait.

**Tech Stack:** Tauri v2 (Rust), `reqwest` (streaming HTTP), `tokio`/`futures-util`, TypeScript + Vite, `vitest` (TS unit tests), the existing `markdown.ts` renderer.

## Global Constraints

- Platform: Windows only (Tauri + WebView2). Do not touch macOS/iOS code.
- All AI calls are **user-initiated**. Never call the model automatically (e.g. on document open) — BYOK users pay per call.
- The API key is **written to and read from Rust only** (`appConfigDir/ai-config.json`). The WebView may send a key to `ai_set_config` to save it, but never reads it back; `ai_get_status` returns `has_key: bool`, never the key.
- LLM HTTP requests are made from Rust (`reqwest`), not the WebView. Do not add API domains to the CSP `connect-src`.
- Providers supported in v1: `"anthropic"` and `"openai"` only.
- Follow existing code style: vanilla TS with `innerHTML` templates + wire functions, warm editorial CSS tokens (`--accent`, `--paper`, `--line`, glass vars). Escape all dynamic text with the existing `escapeText`/equivalent before inserting into HTML.
- TS must pass `npx tsc --noEmit` (strict, `noUnusedLocals`/`noUnusedParameters` on) and `npm run build`.
- Commit after every task. Work on the current branch.
- **Local build note:** Rust may not compile on the maintainer's machine (AV blocks executing freshly-built binaries). `cargo test`/`cargo build` and the full app run are verified via the GitHub Actions Windows runner (`.github/workflows/windows-release.yml`, `workflow_dispatch`). Where a step says "run cargo", an engineer on a normal machine runs it locally; otherwise push and let CI compile.

All work happens under `platforms/windows/`. Paths below are relative to that directory unless noted.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `src/ai/types.ts` | Shared TS types (`ProviderId`, `ChatMessage`, `AiStatus`, stream handlers, `QuickAction`). |
| `src/ai/prompts.ts` | Pure functions: doc clamping, system prompt (grounding), quick-action instructions, request assembly. |
| `src/ai/client.ts` | Thin bridge to Rust: `getAiStatus`, `saveAiConfig`, `streamChat` (invoke + event listeners), request-id generation. |
| `src/ai/settings.ts` | AI settings modal (provider/model/baseURL/key) markup + wiring. |
| `src/ai/panel.ts` | Right-side panel: conversation state, quick actions, input, streaming render, empty/consent states. |
| `src/ai/styles/ai.css` | Panel + settings styling (warm tokens + glass). |
| `src-tauri/src/ai.rs` | Provider trait + Anthropic/OpenAI adapters, config load/save, `ai_set_config`/`ai_get_status`/`ai_stream`/`ai_cancel`, SSE parsing, event emit, cancellation registry. |
| `src/main.ts` (modify) | Mount panel column, AI toggle button, open settings, privacy consent gate. |
| `src/menus.ts` (modify) | Add "AI 助手" (toggle) and "AI 设置…" menu items + context handlers. |
| `src-tauri/src/lib.rs` (modify) | `mod ai;` register the 4 commands + managed `AiState`. |
| `src-tauri/Cargo.toml` (modify) | Add `reqwest`, `tokio`, `futures-util`, `tokio-util` deps. |
| `src-tauri/capabilities/default.json` (modify) | Add `core:event:default`. |
| `package.json` (modify) | Add `vitest` devDep + `test` script. |
| `tests/ai/prompts.test.ts` | Vitest unit tests for `prompts.ts`. |
| `tests/ai/client.test.ts` | Vitest unit test for request-id generation. |

---

## Task 1: Prompt building (pure TS) + test harness

**Files:**
- Create: `src/ai/types.ts`
- Create: `src/ai/prompts.ts`
- Create: `tests/ai/prompts.test.ts`
- Modify: `package.json` (add `vitest` devDep + `"test"` script)

**Interfaces:**
- Produces:
  - `type ProviderId = "anthropic" | "openai"`
  - `interface ChatMessage { role: "user" | "assistant"; content: string }`
  - `interface AiStatus { provider: ProviderId; model: string; hasKey: boolean }`
  - `interface StreamHandlers { onDelta(t: string): void; onDone(): void; onError(m: string): void }`
  - `interface StreamHandle { cancel(): void }`
  - `type QuickAction = "summary" | "keypoints"`
  - `const MAX_DOC_CHARS = 120000`
  - `function clampDoc(doc: string): { text: string; truncated: boolean }`
  - `function systemPrompt(doc: string): { system: string; truncated: boolean }`
  - `function actionUserMessage(action: QuickAction): string`

- [ ] **Step 1: Add vitest and a test script**

In `package.json`, add to `devDependencies`: `"vitest": "^2.1.0"`. Add to `scripts`: `"test": "vitest run"`. Then install:

```bash
cd platforms/windows
npm install --no-audit --no-fund
```

- [ ] **Step 2: Write `src/ai/types.ts`**

```ts
// Shared types for the AI reading assistant.

export type ProviderId = "anthropic" | "openai";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface AiStatus {
  provider: ProviderId;
  model: string;
  hasKey: boolean;
}

export interface StreamHandlers {
  onDelta: (text: string) => void;
  onDone: () => void;
  onError: (message: string) => void;
}

export interface StreamHandle {
  cancel: () => void;
}

export type QuickAction = "summary" | "keypoints";
```

- [ ] **Step 3: Write the failing test `tests/ai/prompts.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import {
  MAX_DOC_CHARS,
  clampDoc,
  systemPrompt,
  actionUserMessage,
} from "../../src/ai/prompts";

describe("clampDoc", () => {
  it("keeps short docs intact", () => {
    const r = clampDoc("hello");
    expect(r.text).toBe("hello");
    expect(r.truncated).toBe(false);
  });

  it("truncates docs over the cap and flags it", () => {
    const big = "x".repeat(MAX_DOC_CHARS + 100);
    const r = clampDoc(big);
    expect(r.text.length).toBe(MAX_DOC_CHARS);
    expect(r.truncated).toBe(true);
  });
});

describe("systemPrompt", () => {
  it("grounds on the document and includes its text", () => {
    const { system, truncated } = systemPrompt("MY DOC BODY");
    expect(system).toContain("阅读助手");
    expect(system).toContain("MY DOC BODY");
    expect(truncated).toBe(false);
  });
});

describe("actionUserMessage", () => {
  it("returns the summary instruction", () => {
    expect(actionUserMessage("summary")).toContain("概括");
  });
  it("returns the key-points instruction", () => {
    expect(actionUserMessage("keypoints")).toContain("要点");
  });
});
```

- [ ] **Step 4: Run the test, verify it fails**

Run: `npx vitest run tests/ai/prompts.test.ts`
Expected: FAIL — cannot resolve `../../src/ai/prompts`.

- [ ] **Step 5: Write `src/ai/prompts.ts`**

```ts
// Pure prompt assembly for the AI reading assistant. No I/O — unit-tested.

import type { ChatMessage, QuickAction } from "./types";

export const MAX_DOC_CHARS = 120000;

export function clampDoc(doc: string): { text: string; truncated: boolean } {
  if (doc.length <= MAX_DOC_CHARS) return { text: doc, truncated: false };
  return { text: doc.slice(0, MAX_DOC_CHARS), truncated: true };
}

export function systemPrompt(doc: string): { system: string; truncated: boolean } {
  const { text, truncated } = clampDoc(doc);
  const system =
    "你是 MarkGo 的阅读助手。仅依据下面这篇文档作答，用简体中文回答，" +
    "不要编造文档之外的内容；文档没有提到的，就说文档未提及。\n\n" +
    "===== 文档开始 =====\n" +
    text +
    "\n===== 文档结束 =====";
  return { system, truncated };
}

export function actionUserMessage(action: QuickAction): string {
  switch (action) {
    case "summary":
      return "请用 2–4 段简洁的中文概括这篇文档的要点。";
    case "keypoints":
      return "请提炼这篇文档的关键要点，用项目符号列出；若文档包含任务或待办，另起一节列出「行动项」。";
  }
}

// Convenience: a conversation always carries the document via the system prompt;
// `history` is the visible user/assistant turns.
export function buildRequest(
  doc: string,
  history: ChatMessage[]
): { system: string; messages: ChatMessage[]; truncated: boolean } {
  const { system, truncated } = systemPrompt(doc);
  return { system, messages: history, truncated };
}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `npx vitest run tests/ai/prompts.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 7: Commit**

```bash
git add platforms/windows/package.json platforms/windows/package-lock.json \
  platforms/windows/src/ai/types.ts platforms/windows/src/ai/prompts.ts \
  platforms/windows/tests/ai/prompts.test.ts
git commit -m "feat(ai): pure prompt builder + vitest harness"
```

---

## Task 2: Rust provider adapters + SSE parsing (pure, unit-tested)

**Files:**
- Create: `src-tauri/src/ai.rs`
- Modify: `src-tauri/Cargo.toml`

**Interfaces:**
- Produces (used by Task 3):
  - `enum Provider { Anthropic, OpenAi }`, `Provider::from_id(&str) -> Option<Provider>`
  - `struct ChatMessage { role: String, content: String }` (serde `Deserialize`)
  - `fn build_body(p: Provider, model: &str, system: &str, messages: &[ChatMessage], max_tokens: u32) -> serde_json::Value`
  - `fn endpoint(p: Provider, base_url: Option<&str>) -> String`
  - `fn parse_sse_data(p: Provider, data: &str) -> Option<String>` (returns the text delta, or `None` for non-text/`[DONE]`)

- [ ] **Step 1: Add Rust dependencies**

In `src-tauri/Cargo.toml`, under `[dependencies]` add:

```toml
reqwest = { version = "0.12", default-features = false, features = ["rustls-tls", "stream", "json"] }
tokio = { version = "1", features = ["rt-multi-thread", "macros"] }
futures-util = "0.3"
tokio-util = "0.7"
```

- [ ] **Step 2: Write `src-tauri/src/ai.rs` with provider logic + failing tests**

```rust
// AI provider adapters (Anthropic / OpenAI), config, and the streaming command.

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Provider {
    Anthropic,
    OpenAi,
}

impl Provider {
    pub fn from_id(id: &str) -> Option<Provider> {
        match id {
            "anthropic" => Some(Provider::Anthropic),
            "openai" => Some(Provider::OpenAi),
            _ => None,
        }
    }
}

#[derive(Clone, Deserialize, Serialize, Debug)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

pub fn endpoint(p: Provider, base_url: Option<&str>) -> String {
    match p {
        Provider::Anthropic => "https://api.anthropic.com/v1/messages".to_string(),
        Provider::OpenAi => {
            let base = base_url
                .map(|b| b.trim_end_matches('/').to_string())
                .unwrap_or_else(|| "https://api.openai.com".to_string());
            format!("{base}/v1/chat/completions")
        }
    }
}

pub fn build_body(
    p: Provider,
    model: &str,
    system: &str,
    messages: &[ChatMessage],
    max_tokens: u32,
) -> Value {
    let msgs: Vec<Value> = messages
        .iter()
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();
    match p {
        Provider::Anthropic => json!({
            "model": model,
            "max_tokens": max_tokens,
            "system": system,
            "stream": true,
            "messages": msgs,
        }),
        Provider::OpenAi => {
            let mut all = vec![json!({ "role": "system", "content": system })];
            all.extend(msgs);
            json!({
                "model": model,
                "max_tokens": max_tokens,
                "stream": true,
                "messages": all,
            })
        }
    }
}

/// Extract a text delta from one SSE `data:` payload, or `None`.
pub fn parse_sse_data(p: Provider, data: &str) -> Option<String> {
    let data = data.trim();
    if data.is_empty() || data == "[DONE]" {
        return None;
    }
    let v: Value = serde_json::from_str(data).ok()?;
    match p {
        Provider::Anthropic => {
            if v.get("type")?.as_str()? == "content_block_delta" {
                v.get("delta")?.get("text")?.as_str().map(str::to_string)
            } else {
                None
            }
        }
        Provider::OpenAi => v
            .get("choices")?
            .get(0)?
            .get("delta")?
            .get("content")?
            .as_str()
            .map(str::to_string),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anthropic_endpoint_is_fixed() {
        assert_eq!(
            endpoint(Provider::Anthropic, None),
            "https://api.anthropic.com/v1/messages"
        );
    }

    #[test]
    fn openai_endpoint_uses_base_url() {
        assert_eq!(
            endpoint(Provider::OpenAi, Some("https://proxy.test/")),
            "https://proxy.test/v1/chat/completions"
        );
        assert_eq!(
            endpoint(Provider::OpenAi, None),
            "https://api.openai.com/v1/chat/completions"
        );
    }

    #[test]
    fn anthropic_body_has_top_level_system() {
        let msgs = vec![ChatMessage { role: "user".into(), content: "hi".into() }];
        let b = build_body(Provider::Anthropic, "m", "SYS", &msgs, 100);
        assert_eq!(b["system"], "SYS");
        assert_eq!(b["messages"][0]["content"], "hi");
        assert_eq!(b["stream"], true);
    }

    #[test]
    fn openai_body_prepends_system_message() {
        let msgs = vec![ChatMessage { role: "user".into(), content: "hi".into() }];
        let b = build_body(Provider::OpenAi, "m", "SYS", &msgs, 100);
        assert_eq!(b["messages"][0]["role"], "system");
        assert_eq!(b["messages"][0]["content"], "SYS");
        assert_eq!(b["messages"][1]["content"], "hi");
    }

    #[test]
    fn parses_anthropic_text_delta() {
        let line = r#"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#;
        assert_eq!(parse_sse_data(Provider::Anthropic, line), Some("Hello".into()));
    }

    #[test]
    fn parses_openai_text_delta() {
        let line = r#"{"choices":[{"delta":{"content":"Hi"}}]}"#;
        assert_eq!(parse_sse_data(Provider::OpenAi, line), Some("Hi".into()));
    }

    #[test]
    fn ignores_done_and_non_text() {
        assert_eq!(parse_sse_data(Provider::OpenAi, "[DONE]"), None);
        assert_eq!(
            parse_sse_data(Provider::Anthropic, r#"{"type":"message_start"}"#),
            None
        );
    }
}
```

- [ ] **Step 3: Run the provider tests, verify they pass**

Run: `cd platforms/windows/src-tauri && cargo test ai::tests`
Expected: PASS (7 tests). (If local Rust is blocked, push and confirm via CI in Task 3's commit; note it in the commit body.)

- [ ] **Step 4: Commit**

```bash
git add platforms/windows/src-tauri/Cargo.toml platforms/windows/src-tauri/src/ai.rs
git commit -m "feat(ai): rust provider adapters + SSE parsing with unit tests"
```

---

## Task 3: Rust config + streaming commands + registration

**Files:**
- Modify: `src-tauri/src/ai.rs` (append config + commands + state)
- Modify: `src-tauri/src/lib.rs`
- Modify: `src-tauri/capabilities/default.json`

**Interfaces:**
- Consumes: `Provider`, `ChatMessage`, `endpoint`, `build_body`, `parse_sse_data` (Task 2).
- Produces (Tauri commands, called by Task 4):
  - `ai_set_config(provider: String, model: String, base_url: Option<String>, api_key: String)`
  - `ai_get_status() -> AiStatus` where `AiStatus { provider: String, model: String, has_key: bool }`
  - `ai_stream(window, state, request_id: String, system: String, messages: Vec<ChatMessage>, max_tokens: u32)`
  - `ai_cancel(state, request_id: String)`
  - Events: `ai://chunk` `{ requestId, delta }`, `ai://done` `{ requestId }`, `ai://error` `{ requestId, message }`.

- [ ] **Step 1: Append config + state + commands to `src-tauri/src/ai.rs`**

```rust
use std::collections::HashMap;
use std::sync::Mutex;

use futures_util::StreamExt;
use tauri::{AppHandle, Emitter, Manager, State};
use tokio_util::sync::CancellationToken;

#[derive(Clone, Deserialize, Serialize, Default)]
pub struct AiConfig {
    pub provider: String,
    pub model: String,
    pub base_url: Option<String>,
    pub api_key: String,
}

#[derive(Serialize)]
pub struct AiStatus {
    pub provider: String,
    pub model: String,
    pub has_key: bool,
}

#[derive(Default)]
pub struct AiState {
    pub active: Mutex<HashMap<String, CancellationToken>>,
}

fn config_path(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("ai-config.json"))
}

fn load_config(app: &AppHandle) -> AiConfig {
    config_path(app)
        .ok()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

#[tauri::command]
pub fn ai_set_config(
    app: AppHandle,
    provider: String,
    model: String,
    base_url: Option<String>,
    api_key: String,
) -> Result<(), String> {
    let cfg = AiConfig { provider, model, base_url, api_key };
    let path = config_path(&app)?;
    std::fs::write(path, serde_json::to_string_pretty(&cfg).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub fn ai_get_status(app: AppHandle) -> AiStatus {
    let cfg = load_config(&app);
    AiStatus {
        has_key: !cfg.api_key.is_empty(),
        provider: cfg.provider,
        model: cfg.model,
    }
}

#[tauri::command]
pub fn ai_cancel(state: State<'_, AiState>, request_id: String) {
    if let Some(token) = state.active.lock().unwrap().remove(&request_id) {
        token.cancel();
    }
}

#[tauri::command]
pub async fn ai_stream(
    app: AppHandle,
    window: tauri::Window,
    state: State<'_, AiState>,
    request_id: String,
    system: String,
    messages: Vec<ChatMessage>,
    max_tokens: u32,
) -> Result<(), String> {
    let cfg = load_config(&app);
    let provider = Provider::from_id(&cfg.provider)
        .ok_or_else(|| "未配置 AI 提供方".to_string())?;
    if cfg.api_key.is_empty() {
        return Err("未配置 API key".to_string());
    }

    let token = CancellationToken::new();
    state
        .active
        .lock()
        .unwrap()
        .insert(request_id.clone(), token.clone());

    let body = build_body(provider, &cfg.model, &system, &messages, max_tokens);
    let url = endpoint(provider, cfg.base_url.as_deref());

    let client = reqwest::Client::new();
    let mut req = client.post(&url).json(&body);
    req = match provider {
        Provider::Anthropic => req
            .header("x-api-key", &cfg.api_key)
            .header("anthropic-version", "2023-06-01"),
        Provider::OpenAi => req.header("authorization", format!("Bearer {}", cfg.api_key)),
    };

    let emit_err = |msg: String| {
        let _ = window.emit("ai://error", json!({ "requestId": request_id, "message": msg }));
    };

    let resp = match req.send().await {
        Ok(r) => r,
        Err(e) => {
            state.active.lock().unwrap().remove(&request_id);
            emit_err(format!("请求失败：{e}"));
            return Ok(());
        }
    };
    if !resp.status().is_success() {
        let code = resp.status();
        let text = resp.text().await.unwrap_or_default();
        state.active.lock().unwrap().remove(&request_id);
        emit_err(format!("{code}: {}", text.chars().take(300).collect::<String>()));
        return Ok(());
    }

    let mut stream = resp.bytes_stream();
    let mut buf = String::new();
    loop {
        tokio::select! {
            _ = token.cancelled() => break,
            chunk = stream.next() => {
                match chunk {
                    Some(Ok(bytes)) => {
                        buf.push_str(&String::from_utf8_lossy(&bytes));
                        // Process complete SSE lines.
                        while let Some(nl) = buf.find('\n') {
                            let line = buf[..nl].trim().to_string();
                            buf.drain(..=nl);
                            if let Some(data) = line.strip_prefix("data:") {
                                if let Some(delta) = parse_sse_data(provider, data) {
                                    let _ = window.emit(
                                        "ai://chunk",
                                        json!({ "requestId": request_id, "delta": delta }),
                                    );
                                }
                            }
                        }
                    }
                    Some(Err(e)) => { emit_err(format!("流式中断：{e}")); break; }
                    None => break,
                }
            }
        }
    }

    state.active.lock().unwrap().remove(&request_id);
    let _ = window.emit("ai://done", json!({ "requestId": request_id }));
    Ok(())
}
```

- [ ] **Step 2: Add a config round-trip test to the `tests` module in `ai.rs`**

Inside the existing `#[cfg(test)] mod tests`, add:

```rust
#[test]
fn config_serializes_round_trip() {
    let cfg = AiConfig {
        provider: "anthropic".into(),
        model: "m".into(),
        base_url: None,
        api_key: "secret".into(),
    };
    let s = serde_json::to_string(&cfg).unwrap();
    let back: AiConfig = serde_json::from_str(&s).unwrap();
    assert_eq!(back.api_key, "secret");
    assert_eq!(back.provider, "anthropic");
}
```

- [ ] **Step 3: Register the module + commands + state in `src-tauri/src/lib.rs`**

At the top of `lib.rs` add `mod ai;`. In `run()`, on the builder chain, add `.manage(ai::AiState::default())` and extend the `invoke_handler` to include the AI commands alongside `read_markdown`:

```rust
        .manage(ai::AiState::default())
        // ...existing plugins...
        .invoke_handler(tauri::generate_handler![
            read_markdown,
            ai::ai_set_config,
            ai::ai_get_status,
            ai::ai_stream,
            ai::ai_cancel
        ])
```

- [ ] **Step 4: Grant event permission in `src-tauri/capabilities/default.json`**

Add `"core:event:default"` to the `permissions` array (after `"core:default"`).

- [ ] **Step 5: Verify Rust compiles + tests pass**

Run: `cd platforms/windows/src-tauri && cargo test`
Expected: PASS (8 tests). If local Rust is blocked, push and trigger CI (`gh workflow run windows-release.yml --ref <branch>`) and confirm the build is green.

- [ ] **Step 6: Commit**

```bash
git add platforms/windows/src-tauri/src/ai.rs platforms/windows/src-tauri/src/lib.rs \
  platforms/windows/src-tauri/capabilities/default.json
git commit -m "feat(ai): rust config + streaming ai_stream/ai_cancel commands"
```

---

## Task 4: TS client bridge

**Files:**
- Create: `src/ai/client.ts`
- Create: `tests/ai/client.test.ts`

**Interfaces:**
- Consumes: `ai_get_status`, `ai_set_config`, `ai_stream`, `ai_cancel` commands; `ai://chunk|done|error` events (Task 3); types from Task 1.
- Produces (used by Tasks 5–6):
  - `function nextRequestId(): string`
  - `async function getAiStatus(): Promise<AiStatus>`
  - `async function saveAiConfig(p: ProviderId, model: string, baseUrl: string | null, apiKey: string): Promise<void>`
  - `function streamChat(req: { system: string; messages: ChatMessage[]; maxTokens?: number }, h: StreamHandlers): StreamHandle`

- [ ] **Step 1: Write the failing test `tests/ai/client.test.ts`**

```ts
import { describe, it, expect } from "vitest";
import { nextRequestId } from "../../src/ai/client";

describe("nextRequestId", () => {
  it("produces unique, prefixed ids", () => {
    const a = nextRequestId();
    const b = nextRequestId();
    expect(a).toMatch(/^ai-\d+$/);
    expect(a).not.toBe(b);
  });
});
```

- [ ] **Step 2: Run it, verify it fails**

Run: `npx vitest run tests/ai/client.test.ts`
Expected: FAIL — cannot resolve `../../src/ai/client`.

- [ ] **Step 3: Write `src/ai/client.ts`**

```ts
// Bridge between the AI UI and the Rust commands/events. No key ever returns
// to the WebView; we only send one to ai_set_config.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  AiStatus,
  ChatMessage,
  ProviderId,
  StreamHandle,
  StreamHandlers,
} from "./types";

let counter = 0;
export function nextRequestId(): string {
  return `ai-${++counter}`;
}

export async function getAiStatus(): Promise<AiStatus> {
  return invoke<AiStatus>("ai_get_status");
}

export async function saveAiConfig(
  provider: ProviderId,
  model: string,
  baseUrl: string | null,
  apiKey: string
): Promise<void> {
  await invoke("ai_set_config", {
    provider,
    model,
    baseUrl: baseUrl || null,
    apiKey,
  });
}

interface ChunkPayload { requestId: string; delta: string }
interface DonePayload { requestId: string }
interface ErrorPayload { requestId: string; message: string }

export function streamChat(
  req: { system: string; messages: ChatMessage[]; maxTokens?: number },
  h: StreamHandlers
): StreamHandle {
  const requestId = nextRequestId();
  const unlisten: UnlistenFn[] = [];
  let finished = false;

  const cleanup = () => {
    finished = true;
    unlisten.forEach((u) => u());
    unlisten.length = 0;
  };

  void (async () => {
    unlisten.push(
      await listen<ChunkPayload>("ai://chunk", (e) => {
        if (e.payload.requestId === requestId) h.onDelta(e.payload.delta);
      })
    );
    unlisten.push(
      await listen<DonePayload>("ai://done", (e) => {
        if (e.payload.requestId === requestId) {
          h.onDone();
          cleanup();
        }
      })
    );
    unlisten.push(
      await listen<ErrorPayload>("ai://error", (e) => {
        if (e.payload.requestId === requestId) {
          h.onError(e.payload.message);
          cleanup();
        }
      })
    );
    if (finished) {
      unlisten.forEach((u) => u());
      return;
    }
    try {
      await invoke("ai_stream", {
        requestId,
        system: req.system,
        messages: req.messages,
        maxTokens: req.maxTokens ?? 1024,
      });
    } catch (err) {
      if (!finished) {
        h.onError(String(err));
        cleanup();
      }
    }
  })();

  return {
    cancel: () => {
      if (finished) return;
      void invoke("ai_cancel", { requestId });
      cleanup();
    },
  };
}
```

- [ ] **Step 4: Run the test, verify it passes**

Run: `npx vitest run tests/ai/client.test.ts`
Expected: PASS.

- [ ] **Step 5: Verify the whole project still type-checks**

Run: `cd platforms/windows && npx tsc --noEmit`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add platforms/windows/src/ai/client.ts platforms/windows/tests/ai/client.test.ts
git commit -m "feat(ai): TS client bridge (status/save/streamChat)"
```

---

## Task 5: Settings modal

**Files:**
- Create: `src/ai/settings.ts`
- Create: `src/ai/styles/ai.css` (settings section now; panel section added in Task 6)
- Modify: `src/main.ts` (import `ai.css`; nothing else yet)

**Interfaces:**
- Consumes: `getAiStatus`, `saveAiConfig` (Task 4); `ProviderId` (Task 1).
- Produces (used by Tasks 6–7):
  - `function settingsModalHtml(): string` — returns the backdrop+modal markup (hidden by default).
  - `function wireSettings(root: HTMLElement, onSaved: () => void): void` — wires inputs, save, close; reads current status to prefill provider/model and show "已配置 ✓".
  - `function openSettings(root: HTMLElement): void` / `function closeSettings(root: HTMLElement): void`.

- [ ] **Step 1: Write `src/ai/settings.ts`**

```ts
// AI settings modal: choose provider, model, optional base URL, and API key.
// The key is written to Rust (ai_set_config) and never read back.

import { getAiStatus, saveAiConfig } from "./client";
import type { ProviderId } from "./types";

const DEFAULT_MODEL: Record<ProviderId, string> = {
  anthropic: "claude-sonnet-4-6",
  openai: "gpt-4o",
};

export function settingsModalHtml(): string {
  return `
  <div class="ai-modal-backdrop" id="ai-settings-backdrop">
    <div class="ai-modal">
      <div class="ai-modal__head">
        <h2 class="ai-modal__title">AI 设置</h2>
        <button class="ai-modal__close" id="ai-settings-close" aria-label="关闭">&times;</button>
      </div>
      <label class="ai-field">
        <span class="ai-field__label">提供方</span>
        <select id="ai-provider">
          <option value="anthropic">Anthropic（Claude）</option>
          <option value="openai">OpenAI</option>
        </select>
      </label>
      <label class="ai-field">
        <span class="ai-field__label">模型</span>
        <input id="ai-model" type="text" spellcheck="false" />
      </label>
      <label class="ai-field">
        <span class="ai-field__label">Base URL（可选，OpenAI 兼容/代理）</span>
        <input id="ai-base-url" type="text" spellcheck="false" placeholder="https://api.openai.com" />
      </label>
      <label class="ai-field">
        <span class="ai-field__label">API Key <span id="ai-key-status" class="ai-key-status"></span></span>
        <input id="ai-key" type="password" spellcheck="false" placeholder="sk-..." />
      </label>
      <div class="ai-modal__foot">
        <span class="ai-modal__msg" id="ai-settings-msg"></span>
        <button class="ai-btn" id="ai-settings-cancel">取消</button>
        <button class="ai-btn ai-btn--primary" id="ai-settings-save">保存</button>
      </div>
    </div>
  </div>`;
}

export function openSettings(root: HTMLElement): void {
  root.querySelector("#ai-settings-backdrop")?.classList.add("open");
}
export function closeSettings(root: HTMLElement): void {
  root.querySelector("#ai-settings-backdrop")?.classList.remove("open");
}

export function wireSettings(root: HTMLElement, onSaved: () => void): void {
  const providerEl = root.querySelector<HTMLSelectElement>("#ai-provider")!;
  const modelEl = root.querySelector<HTMLInputElement>("#ai-model")!;
  const baseEl = root.querySelector<HTMLInputElement>("#ai-base-url")!;
  const keyEl = root.querySelector<HTMLInputElement>("#ai-key")!;
  const keyStatus = root.querySelector<HTMLElement>("#ai-key-status")!;
  const msg = root.querySelector<HTMLElement>("#ai-settings-msg")!;

  void getAiStatus().then((s) => {
    if (s.provider) providerEl.value = s.provider;
    modelEl.value = s.model || DEFAULT_MODEL[(s.provider as ProviderId) || "anthropic"];
    keyStatus.textContent = s.hasKey ? "已配置 ✓" : "";
  });

  providerEl.addEventListener("change", () => {
    if (!modelEl.value.trim()) modelEl.value = DEFAULT_MODEL[providerEl.value as ProviderId];
  });

  const close = () => closeSettings(root);
  root.querySelector("#ai-settings-close")!.addEventListener("click", close);
  root.querySelector("#ai-settings-cancel")!.addEventListener("click", close);
  root.querySelector("#ai-settings-backdrop")!.addEventListener("click", (e) => {
    if (e.target === e.currentTarget) close();
  });

  root.querySelector("#ai-settings-save")!.addEventListener("click", async () => {
    const provider = providerEl.value as ProviderId;
    const model = modelEl.value.trim() || DEFAULT_MODEL[provider];
    const key = keyEl.value.trim();
    if (!key) {
      msg.textContent = "请填写 API Key";
      return;
    }
    msg.textContent = "保存中…";
    try {
      await saveAiConfig(provider, model, baseEl.value.trim() || null, key);
      keyEl.value = "";
      keyStatus.textContent = "已配置 ✓";
      msg.textContent = "已保存";
      onSaved();
      setTimeout(close, 500);
    } catch (e) {
      msg.textContent = `保存失败：${String(e)}`;
    }
  });
}
```

- [ ] **Step 2: Write `src/ai/styles/ai.css` (settings styles)**

```css
/* AI settings modal + (Task 6 appends) the assistant panel. Warm glass tokens. */
.ai-modal-backdrop {
  position: fixed; inset: 0; z-index: 85; display: none;
  align-items: center; justify-content: center;
  background: rgba(30, 26, 18, 0.32);
  -webkit-backdrop-filter: blur(3px); backdrop-filter: blur(3px);
}
.ai-modal-backdrop.open { display: flex; }
.ai-modal {
  width: 420px; max-width: calc(100vw - 48px); padding: 22px 24px 18px;
  border-radius: 20px; background: color-mix(in srgb, var(--paper) 97%, transparent);
  border: 1px solid var(--line);
  box-shadow: 0 18px 50px rgba(40, 34, 22, 0.26), inset 0 1px 0 rgba(255,255,255,0.8);
}
.ai-modal__head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 14px; }
.ai-modal__title { font: 800 18px var(--font-sans); color: var(--ink); margin: 0; }
.ai-modal__close { border: none; background: transparent; font-size: 22px; line-height: 1; color: var(--muted-ink); cursor: pointer; }
.ai-field { display: block; margin-bottom: 12px; }
.ai-field__label { display: block; font: 600 12px var(--font-sans); color: var(--muted-ink); margin-bottom: 5px; }
.ai-field input, .ai-field select {
  width: 100%; height: 34px; padding: 0 10px; border-radius: 9px;
  border: 1px solid var(--line); background: var(--paper); color: var(--ink);
  font: 500 13px var(--font-sans);
}
.ai-key-status { color: var(--accent); font-weight: 700; }
.ai-modal__foot { display: flex; align-items: center; gap: 10px; margin-top: 16px; }
.ai-modal__msg { flex: 1; font: 600 12px var(--font-sans); color: var(--muted-ink); }
.ai-btn {
  height: 34px; padding: 0 16px; border-radius: 9px; border: 1px solid var(--line);
  background: var(--paper); color: var(--ink); font: 600 13px var(--font-sans); cursor: pointer;
}
.ai-btn--primary { background: var(--accent); border-color: transparent; color: #fff; }
```

- [ ] **Step 3: Import the stylesheet in `src/main.ts`**

Add next to the other style imports (after `import "./styles/chrome.css";`):

```ts
import "./ai/styles/ai.css";
```

- [ ] **Step 4: Verify type-check + build**

Run: `cd platforms/windows && npx tsc --noEmit && npm run build`
Expected: exit 0 for both.

- [ ] **Step 5: Commit**

```bash
git add platforms/windows/src/ai/settings.ts platforms/windows/src/ai/styles/ai.css \
  platforms/windows/src/main.ts
git commit -m "feat(ai): settings modal (provider/model/baseURL/key)"
```

---

## Task 6: AI panel (conversation, quick actions, streaming render)

**Files:**
- Create: `src/ai/panel.ts`
- Modify: `src/ai/styles/ai.css` (append panel styles)

**Interfaces:**
- Consumes: `streamChat` (Task 4); `buildRequest`, `actionUserMessage` (Task 1); `openSettings` (Task 5); the existing renderer `renderMarkdown` from `../markdown` (confirm its exported name; in this codebase the reader uses `renderReader`/markdown utilities — use the module's existing export to turn a Markdown string into HTML). Status via `getAiStatus`.
- Produces (used by Task 7):
  - `interface AiPanelDeps { getDoc(): string; getStatus(): { hasKey: boolean }; openSettings(): void }`
  - `function aiPanelHtml(): string` — the panel column markup.
  - `function createAiPanel(root: HTMLElement, deps: AiPanelDeps): { reset(): void; refreshState(): void }`
  - `function renderAiMarkdown(md: string): string` — small helper wrapping the existing markdown renderer; used for assistant bubbles.

- [ ] **Step 1: Confirm the Markdown helper to reuse**

Open `src/markdown.ts` and note the function that converts a Markdown string to sanitized HTML (e.g. used by `reader.ts`). Use it in `renderAiMarkdown`. If it renders into a DOM node rather than returning a string, wrap accordingly. Do not introduce a second Markdown library.

- [ ] **Step 2: Write `src/ai/panel.ts`**

```ts
// Right-side AI reading-assistant panel: quick actions + chat, streamed.

import { streamChat } from "./client";
import { buildRequest, actionUserMessage } from "./prompts";
import type { ChatMessage, QuickAction, StreamHandle } from "./types";
import { renderMarkdown } from "../markdown"; // adjust to the real export name

export interface AiPanelDeps {
  getDoc: () => string;
  getStatus: () => { hasKey: boolean };
  openSettings: () => void;
}

export function renderAiMarkdown(md: string): string {
  return renderMarkdown(md);
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

export function aiPanelHtml(): string {
  return `
  <aside class="ai-panel" id="ai-panel">
    <div class="ai-panel__head">
      <span class="ai-panel__title">✦ AI 助手</span>
      <div class="ai-panel__head-actions">
        <button class="ai-icon-btn" id="ai-open-settings" title="AI 设置">⚙</button>
        <button class="ai-icon-btn" id="ai-panel-close" title="关闭面板">✕</button>
      </div>
    </div>
    <div class="ai-panel__actions">
      <button class="ai-chip" data-action="summary">✦ 摘要</button>
      <button class="ai-chip" data-action="keypoints">☰ 要点 / 行动项</button>
    </div>
    <div class="ai-panel__transcript" id="ai-transcript"></div>
    <form class="ai-panel__compose" id="ai-compose">
      <textarea id="ai-input" rows="1" placeholder="就这篇文档提问…" spellcheck="false"></textarea>
      <button type="submit" class="ai-send" id="ai-send">发送</button>
    </form>
  </aside>`;
}

export function createAiPanel(root: HTMLElement, deps: AiPanelDeps) {
  const transcript = root.querySelector<HTMLElement>("#ai-transcript")!;
  const input = root.querySelector<HTMLTextAreaElement>("#ai-input")!;
  const sendBtn = root.querySelector<HTMLButtonElement>("#ai-send")!;
  const form = root.querySelector<HTMLFormElement>("#ai-compose")!;
  const history: ChatMessage[] = [];
  let active: StreamHandle | null = null;

  function renderEmpty(): void {
    if (history.length) return;
    if (!deps.getStatus().hasKey) {
      transcript.innerHTML = `
        <div class="ai-empty">
          <p class="ai-empty__title">先配置 AI</p>
          <p class="ai-empty__sub">填入你的 API key 即可开始。</p>
          <button class="ai-btn ai-btn--primary" id="ai-empty-settings">打开设置</button>
        </div>`;
      transcript.querySelector("#ai-empty-settings")!.addEventListener("click", deps.openSettings);
    } else {
      transcript.innerHTML = `
        <div class="ai-empty">
          <p class="ai-empty__title">就这篇文档问我点什么</p>
          <p class="ai-empty__sub">点上方「摘要 / 要点」，或直接提问。</p>
        </div>`;
    }
  }

  function bubble(role: "user" | "assistant"): HTMLElement {
    const el = document.createElement("div");
    el.className = `ai-msg ai-msg--${role}`;
    transcript.appendChild(el);
    transcript.scrollTop = transcript.scrollHeight;
    return el;
  }

  function setBusy(busy: boolean): void {
    sendBtn.textContent = busy ? "停止" : "发送";
    sendBtn.dataset.busy = busy ? "1" : "";
  }

  function send(userText: string): void {
    if (active) return;
    if (!deps.getStatus().hasKey) {
      deps.openSettings();
      return;
    }
    if (!history.length) transcript.innerHTML = "";
    history.push({ role: "user", content: userText });
    const userEl = bubble("user");
    userEl.textContent = userText;

    const aiEl = bubble("assistant");
    aiEl.innerHTML = `<span class="ai-cursor"></span>`;
    let acc = "";

    const { system, messages, truncated } = buildRequest(deps.getDoc(), history);
    if (truncated) {
      const note = document.createElement("div");
      note.className = "ai-note";
      note.textContent = "文档较长，已截取前部分用于分析。";
      transcript.insertBefore(note, aiEl);
    }

    setBusy(true);
    active = streamChat(
      { system, messages },
      {
        onDelta: (t) => {
          acc += t;
          aiEl.innerHTML = renderAiMarkdown(acc) + `<span class="ai-cursor"></span>`;
          transcript.scrollTop = transcript.scrollHeight;
        },
        onDone: () => {
          aiEl.innerHTML = renderAiMarkdown(acc);
          history.push({ role: "assistant", content: acc });
          active = null;
          setBusy(false);
        },
        onError: (m) => {
          aiEl.innerHTML = `<div class="ai-error">出错了：${esc(m)} <button class="ai-retry" id="ai-retry">重试</button></div>`;
          aiEl.querySelector("#ai-retry")!.addEventListener("click", () => {
            history.pop(); // drop the failed user turn we re-send
            aiEl.remove();
            userEl.remove();
            send(userText);
          });
          active = null;
          setBusy(false);
        },
      }
    );
  }

  root.querySelectorAll<HTMLButtonElement>(".ai-chip").forEach((chip) =>
    chip.addEventListener("click", () => send(actionUserMessage(chip.dataset.action as QuickAction)))
  );

  form.addEventListener("submit", (e) => {
    e.preventDefault();
    if (active) {
      active.cancel();
      active = null;
      setBusy(false);
      return;
    }
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    send(text);
  });

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      form.requestSubmit();
    }
  });

  renderEmpty();

  return {
    reset(): void {
      active?.cancel();
      active = null;
      history.length = 0;
      setBusy(false);
      renderEmpty();
    },
    refreshState(): void {
      renderEmpty();
    },
  };
}
```

- [ ] **Step 3: Append panel styles to `src/ai/styles/ai.css`**

```css
/* ---- AI panel column ---- */
.ai-panel {
  width: 340px; flex-shrink: 0; display: flex; flex-direction: column;
  background: color-mix(in srgb, var(--sidebar-bg) 64%, rgba(255,255,255,0.5));
  -webkit-backdrop-filter: blur(28px) saturate(150%); backdrop-filter: blur(28px) saturate(150%);
  border-left: 1px solid var(--line);
}
.ai-panel__head { display: flex; align-items: center; justify-content: space-between; padding: 12px 14px; border-bottom: 1px solid var(--line); }
.ai-panel__title { font: 800 14px var(--font-sans); color: var(--ink); }
.ai-panel__head-actions { display: flex; gap: 4px; }
.ai-icon-btn { width: 28px; height: 28px; border: none; background: transparent; border-radius: 7px; color: var(--muted-ink); cursor: pointer; }
.ai-icon-btn:hover { background: rgba(255,255,255,0.5); color: var(--ink); }
.ai-panel__actions { display: flex; gap: 8px; padding: 12px 14px; }
.ai-chip {
  display: inline-flex; align-items: center; gap: 5px; padding: 7px 12px; border-radius: 999px;
  border: 1px solid color-mix(in srgb, var(--accent) 40%, var(--line));
  background: color-mix(in srgb, var(--accent) 8%, transparent); color: var(--accent);
  font: 700 12px var(--font-sans); cursor: pointer;
}
.ai-chip:hover { background: color-mix(in srgb, var(--accent) 16%, transparent); }
.ai-panel__transcript { flex: 1; overflow-y: auto; padding: 6px 14px 14px; display: flex; flex-direction: column; gap: 12px; }
.ai-msg { max-width: 100%; border-radius: 14px; padding: 10px 13px; font: 500 13.5px var(--font-sans); line-height: 1.6; }
.ai-msg--user { align-self: flex-end; background: var(--accent); color: #fff; white-space: pre-wrap; }
.ai-msg--assistant { align-self: flex-start; background: color-mix(in srgb, var(--paper) 80%, transparent); border: 1px solid var(--line); color: var(--ink); }
.ai-msg--assistant :where(h1,h2,h3) { font-size: 15px; margin: 8px 0 4px; }
.ai-msg--assistant :where(p,ul,ol) { margin: 0 0 8px; }
.ai-msg--assistant ul, .ai-msg--assistant ol { padding-left: 20px; }
.ai-cursor { display: inline-block; width: 7px; height: 14px; background: var(--accent); border-radius: 1px; animation: ai-blink 1s steps(2) infinite; vertical-align: text-bottom; }
@keyframes ai-blink { 0%,50% { opacity: 1; } 50.01%,100% { opacity: 0; } }
.ai-note { align-self: center; font: 600 11px var(--font-sans); color: var(--muted-ink); }
.ai-error { color: var(--rust); font: 600 12.5px var(--font-sans); }
.ai-retry { margin-left: 6px; border: 1px solid var(--line); background: var(--paper); border-radius: 7px; padding: 2px 8px; cursor: pointer; }
.ai-empty { margin: auto; text-align: center; color: var(--muted-ink); display: flex; flex-direction: column; gap: 6px; align-items: center; }
.ai-empty__title { font: 800 15px var(--font-sans); color: var(--ink); margin: 0; }
.ai-empty__sub { font: 500 12.5px var(--font-sans); margin: 0; }
.ai-panel__compose { display: flex; gap: 8px; padding: 12px 14px; border-top: 1px solid var(--line); }
.ai-panel__compose textarea {
  flex: 1; resize: none; max-height: 120px; padding: 8px 10px; border-radius: 10px;
  border: 1px solid var(--line); background: var(--paper); color: var(--ink);
  font: 500 13px var(--font-sans); line-height: 1.5;
}
.ai-send { align-self: flex-end; height: 34px; padding: 0 14px; border-radius: 9px; border: none; background: var(--accent); color: #fff; font: 700 13px var(--font-sans); cursor: pointer; }
.ai-send[data-busy="1"] { background: var(--rust); }
```

- [ ] **Step 4: Verify type-check + build**

Run: `cd platforms/windows && npx tsc --noEmit && npm run build`
Expected: exit 0. (If `renderMarkdown` is not the real export name, fix the import to match `src/markdown.ts` and re-run.)

- [ ] **Step 5: Commit**

```bash
git add platforms/windows/src/ai/panel.ts platforms/windows/src/ai/styles/ai.css
git commit -m "feat(ai): streaming assistant panel (quick actions + chat)"
```

---

## Task 7: Wire panel + toggle + menu + consent into the app

**Files:**
- Modify: `src/main.ts`
- Modify: `src/menus.ts`

**Interfaces:**
- Consumes: `aiPanelHtml`, `createAiPanel` (Task 6); `settingsModalHtml`, `wireSettings`, `openSettings` (Task 5); `getAiStatus` (Task 4).
- Produces: a working AI column toggled from the title bar + 视图 menu, settings reachable from the menu, and a one-time privacy consent before the first send.

- [ ] **Step 1: Add an AI panel state flag + status cache in `src/main.ts`**

Near the top-level `state` object area, add module-level vars:

```ts
let aiOpen = false;
let aiStatus = { hasKey: false };
let aiPanel: { reset: () => void; refreshState: () => void } | null = null;
let aiConsented = localStorage.getItem("markgo.ai.consent") === "1";
```

And on boot (with the other boot calls), prime the status (no-op in browser):

```ts
void getAiStatus().then((s) => { aiStatus = { hasKey: s.hasKey }; }).catch(() => {});
```

Import at top of `main.ts`:

```ts
import { getAiStatus } from "./ai/client";
import { aiPanelHtml, createAiPanel } from "./ai/panel";
import { settingsModalHtml, wireSettings, openSettings, closeSettings } from "./ai/settings";
```

- [ ] **Step 2: Render the panel column + settings modal in the workspace**

In `workspaceHtml()`, add the panel after the content column, gated by `aiOpen`:

```ts
function workspaceHtml(): string {
  return `
    <div class="workspace">
      ${sidebarHtml()}
      <div class="workspace__content" id="content"></div>
      ${aiOpen ? aiPanelHtml() : ""}
    </div>`;
}
```

In the top-level `render()` template, append the settings modal next to the other modals:

```ts
    ${aboutHtml()}
    ${updateHtml()}
    ${settingsModalHtml()}`;
```

- [ ] **Step 3: Wire the panel + settings after render**

In `render()`, where document-mode wiring happens (`if (state.hasDocument) { ... }`), after `renderContent();` add:

```ts
      wireAiSettings();
      if (aiOpen) {
        aiPanel = createAiPanel(root.querySelector(".ai-panel")!, {
          getDoc: () => state.text,
          getStatus: () => aiStatus,
          openSettings: () => openAiSettings(),
        });
      }
```

Also call `wireAiSettings()` in the library branch (so settings work with no document open). Add these helpers near `openAbout`:

```ts
function wireAiSettings(): void {
  wireSettings(root, () => {
    void getAiStatus().then((s) => {
      aiStatus = { hasKey: s.hasKey };
      aiPanel?.refreshState();
    });
  });
}
function openAiSettings(): void { openSettings(root); }
function closeAiSettings(): void { closeSettings(root); }

async function toggleAi(): Promise<void> {
  aiOpen = !aiOpen;
  if (aiOpen && !aiConsented) {
    const ok = window.confirm(
      "AI 功能会把当前文档内容发送给你配置的服务商（Anthropic / OpenAI）进行处理。是否继续？"
    );
    if (!ok) { aiOpen = false; return; }
    aiConsented = true;
    localStorage.setItem("markgo.ai.consent", "1");
  }
  render();
}
```

(`closeAiSettings` is referenced by the Escape handler in Step 5.)

- [ ] **Step 4: Add the title-bar AI toggle button**

In `chromeHtml()`'s `rightTools` (only when `doc`), before the font menu, add:

```ts
      <button class="tool-btn ${aiOpen ? "tool-btn--prominent" : ""}" id="ai-toggle" title="AI 助手">✦ AI</button>
```

In `wireInlineTools()`, wire it:

```ts
  root.querySelector("#ai-toggle")?.addEventListener("click", () => void toggleAi());
```

- [ ] **Step 5: Close settings on Escape**

In the existing `keydown` Escape branch (currently `closeAbout(); closeUpdate(); closeMenus();`), add `closeAiSettings();`.

- [ ] **Step 6: Add menu items in `src/menus.ts`**

Add `onToggleAi: () => void` and `onAiSettings: () => void` to `MenuContext`. In the `viewMenu` nodes, after the outline/font items add:

```ts
      { kind: "divider" },
      { kind: "action", label: "AI 助手", run: ctx.onToggleAi, disabled: !doc },
      { kind: "action", label: "AI 设置…", run: ctx.onAiSettings },
```

In `src/main.ts`'s `menuContext()`, supply them:

```ts
    onToggleAi: () => void toggleAi(),
    onAiSettings: () => openAiSettings(),
```

- [ ] **Step 7: Verify type-check + build**

Run: `cd platforms/windows && npx tsc --noEmit && npm run build`
Expected: exit 0.

- [ ] **Step 8: Manual verification (dev or CI build)**

Run `npm run tauri:dev` (normal env) or push + CI build + install. Check:
1. ✦ AI button toggles the right panel; consent prompt appears once.
2. With no key: panel shows "先配置 AI"; opening settings, saving a key flips it to "已配置 ✓".
3. Clicking 摘要 streams a Markdown-rendered summary; 要点 streams a bullet list.
4. Free-form question streams an answer; "停止" cancels mid-stream.
5. Switching/opening another document resets the conversation.

- [ ] **Step 9: Commit**

```bash
git add platforms/windows/src/main.ts platforms/windows/src/menus.ts
git commit -m "feat(ai): wire panel toggle, settings, and consent into the app"
```

---

## Task 8: Release notes + version bump

**Files:**
- Modify (via script): version files + `.release-notes.md`

**Interfaces:** none (release mechanics only).

- [ ] **Step 1: Cut a release that includes the AI assistant**

```bash
cd /e/MarkGo/MarkGO
node scripts/release-win.mjs 1.1.0 --notes "$(printf '新增 AI 阅读助手：一键摘要、提炼要点、就文档自由问答（需在设置里填入自己的 API key）。')" --push
```

- [ ] **Step 2: Confirm the release build is green and latest.json updated**

```bash
gh run watch "$(gh run list --workflow windows-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
curl -s -L "https://github.com/Oreo992/MarkGO/releases/latest/download/latest.json" | grep '"version"'
```

Expected: build success; `"version": "1.1.0"`.

---

## Self-Review

**Spec coverage check:**
- §1 capabilities (summary/keypoints/chat, manual) → Tasks 1 (prompts), 6 (panel actions/chat). ✓
- §3 architecture / modules → Tasks 1–7 map 1:1 to the file table. ✓
- §3.1 key only in Rust → Task 3 (`ai_get_status` returns `has_key`, no key; settings never reads back). ✓
- §3.2 data flow / events → Tasks 3 (emit) + 4 (listen) + 6 (render). ✓
- §3.3 layout / toggle → Task 7. ✓
- §4 Rust commands/trait/SSE/cancel/permission → Tasks 2–3. ✓
- §5 panel UX (stream, markdown, empty state, doc-bound reset) → Task 6 + Task 7 reset-on-doc-change (the existing `render()` recreates the panel; `reset()` is exposed and called when a new document loads — wire `aiPanel?.reset()` inside `loadDocument()` as part of Task 7 Step 3). ✓
- §6 settings → Task 5. ✓
- §7 prompts → Task 1. ✓
- §8 long doc clamp + note → Task 1 (`clampDoc`) + Task 6 (note). ✓
- §9 privacy consent → Task 7. ✓
- §10 errors (no key / api / cancel) → Tasks 6–7. ✓
- §11 tests → Tasks 1–4 (vitest + cargo). ✓

**Added during review:** `loadDocument()` must call `aiPanel?.reset()` so the conversation clears when a new document opens (spec §5 "会话绑定当前文档"). Add to Task 7 Step 3: after `state.analysis = analyze(...)` in `loadDocument`, add `aiPanel?.reset();`.

**Placeholder scan:** No TBD/TODO; all code blocks concrete. The one lookup ("confirm `renderMarkdown` export name", Task 6 Step 1) is an explicit verification step against `src/markdown.ts`, not a placeholder.

**Type consistency:** `ChatMessage`, `AiStatus`, `ProviderId`, `QuickAction`, `StreamHandlers`, `StreamHandle` defined in Task 1 and used unchanged in Tasks 4–6. Rust `ChatMessage`/`AiConfig`/`AiStatus`/`AiState` defined in Tasks 2–3 and registered in Task 3. Command names (`ai_set_config`/`ai_get_status`/`ai_stream`/`ai_cancel`) and event names (`ai://chunk|done|error`) match across Rust (Task 3) and TS (Task 4).
