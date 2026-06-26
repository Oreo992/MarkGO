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
        Provider::Anthropic => {
            // Respect base_url so Anthropic-compatible endpoints (e.g. DeepSeek's
            // https://api.deepseek.com/anthropic) work, not just the official API.
            let base = base_url
                .map(|b| b.trim_end_matches('/').to_string())
                .unwrap_or_else(|| "https://api.anthropic.com".to_string());
            format!("{base}/v1/messages")
        }
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

/// True if this SSE `data:` payload signals the model stopped because it hit the
/// output-token ceiling (Anthropic `stop_reason:max_tokens` / OpenAI
/// `finish_reason:length`). Used to warn the user instead of stopping silently.
pub fn parse_sse_truncated(p: Provider, data: &str) -> bool {
    let data = data.trim();
    if data.is_empty() || data == "[DONE]" {
        return false;
    }
    let v: Value = match serde_json::from_str(data) {
        Ok(v) => v,
        Err(_) => return false,
    };
    match p {
        Provider::Anthropic => {
            v.get("type").and_then(Value::as_str) == Some("message_delta")
                && v.get("delta")
                    .and_then(|d| d.get("stop_reason"))
                    .and_then(Value::as_str)
                    == Some("max_tokens")
        }
        Provider::OpenAi => {
            v.get("choices")
                .and_then(|c| c.get(0))
                .and_then(|c| c.get("finish_reason"))
                .and_then(Value::as_str)
                == Some("length")
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

// ---- Task 3: Config + state + commands ----

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
#[serde(rename_all = "camelCase")]
pub struct AiStatus {
    pub provider: String,
    pub model: String,
    // Serialized as `hasKey` for the TS side. Tauri converts command *args*
    // camel↔snake, but NOT return values — so the struct must match TS itself.
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
        let body = resp.text().await.unwrap_or_default();
        state.active.lock().unwrap().remove(&request_id);
        // 绝不回显原始 body:代理可能在错误体里反射请求头(含 Authorization key)。
        // 只取 provider 结构化错误里的 error.message,否则用通用提示。
        let detail = serde_json::from_str::<Value>(&body)
            .ok()
            .and_then(|v| {
                v.get("error")
                    .and_then(|e| e.get("message"))
                    .and_then(|m| m.as_str())
                    .map(str::to_string)
            })
            .unwrap_or_else(|| "请求被拒绝，请检查 API key、模型名或额度".to_string());
        emit_err(format!("{code}：{}", detail.chars().take(300).collect::<String>()));
        return Ok(());
    }

    let mut stream = resp.bytes_stream();
    let mut buf = String::new();
    let mut truncated = false;
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
                                if parse_sse_truncated(provider, data) {
                                    truncated = true;
                                }
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
    let _ = window.emit(
        "ai://done",
        json!({ "requestId": request_id, "truncated": truncated }),
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn anthropic_endpoint_defaults_and_respects_base_url() {
        assert_eq!(
            endpoint(Provider::Anthropic, None),
            "https://api.anthropic.com/v1/messages"
        );
        assert_eq!(
            endpoint(Provider::Anthropic, Some("https://api.deepseek.com/anthropic")),
            "https://api.deepseek.com/anthropic/v1/messages"
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

    #[test]
    fn detects_max_token_truncation() {
        assert!(parse_sse_truncated(
            Provider::Anthropic,
            r#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#
        ));
        assert!(parse_sse_truncated(
            Provider::OpenAi,
            r#"{"choices":[{"finish_reason":"length"}]}"#
        ));
        // Normal stops are NOT truncation.
        assert!(!parse_sse_truncated(
            Provider::Anthropic,
            r#"{"type":"message_delta","delta":{"stop_reason":"end_turn"}}"#
        ));
        assert!(!parse_sse_truncated(
            Provider::OpenAi,
            r#"{"choices":[{"finish_reason":"stop"}]}"#
        ));
        assert!(!parse_sse_truncated(Provider::OpenAi, "[DONE]"));
    }

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
}
