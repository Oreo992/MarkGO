// Right-side AI reading-assistant panel: quick actions + chat, streamed.

import { streamChat } from "./client";
import { buildRequest, actionUserMessage } from "./prompts";
import type { ChatMessage, QuickAction, StreamHandle } from "./types";
import { renderMarkdown } from "../markdown"; // adjust to the real export name

export interface AiPanelDeps {
  getDoc: () => string;
  getStatus: () => { hasKey: boolean };
  openSettings: () => void;
  onClose: () => void;
  history: ChatMessage[];
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
  const history = deps.history;
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
            if (active) return;
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

  // Header buttons: ⚙ opens AI settings, ✕ closes the panel.
  root.querySelector("#ai-open-settings")!.addEventListener("click", () => deps.openSettings());
  root.querySelector("#ai-panel-close")!.addEventListener("click", () => deps.onClose());

  function renderHistory(): void {
    if (history.length === 0) {
      renderEmpty();
      return;
    }
    transcript.innerHTML = "";
    for (const m of history) {
      const el = bubble(m.role as "user" | "assistant");
      if (m.role === "user") {
        el.textContent = m.content;
      } else {
        el.innerHTML = renderAiMarkdown(m.content);
      }
    }
  }

  renderHistory();

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
