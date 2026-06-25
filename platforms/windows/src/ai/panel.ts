// Right-side AI reading-assistant panel: multi-session chat + whole-document
// rewrite, streamed. Sessions are persisted via ./sessions (localStorage); the
// document is grounded per-request via the system prompt.

import { streamChat } from "./client";
import { buildRequest, actionUserMessage, rewriteUserMessage, REWRITE_PRESETS } from "./prompts";
import {
  ensureActive,
  createSession,
  saveSession,
  deleteSession,
  getSessions,
  setActiveId,
  type AiSession,
} from "./sessions";
import type { ChatMessage, QuickAction, StreamHandle } from "./types";
import { renderMarkdown } from "../markdown";

export interface AiPanelDeps {
  getDoc: () => string;
  getDocName: () => string;
  getStatus: () => { hasKey: boolean };
  openSettings: () => void;
  onClose: () => void;
  /** Apply a rewritten full Markdown document back to the editor/reader. */
  onApplyRewrite: (markdown: string) => void;
}

export function renderAiMarkdown(md: string): string {
  return renderMarkdown(md);
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// Close any open session dropdown on an outside click. Registered once at module
// load (not per panel instance) so re-renders don't accumulate listeners.
document.addEventListener("click", () => {
  document.querySelector(".ai-sessions__panel.open")?.classList.remove("open");
});

export function aiPanelHtml(): string {
  return `
  <aside class="ai-panel" id="ai-panel">
    <div class="ai-panel__head">
      <div class="ai-sessions" id="ai-sessions">
        <button class="ai-sessions__current" id="ai-session-btn" title="切换会话">
          <span class="ai-sessions__title" id="ai-session-title">新会话</span>
          <span class="ai-caret">▾</span>
        </button>
        <div class="ai-sessions__panel" id="ai-session-panel"></div>
      </div>
      <div class="ai-panel__head-actions">
        <button class="ai-icon-btn" id="ai-new-session" title="新建会话">＋</button>
        <button class="ai-icon-btn" id="ai-open-settings" title="AI 设置">⚙</button>
        <button class="ai-icon-btn" id="ai-panel-close" title="关闭面板">✕</button>
      </div>
    </div>
    <div class="ai-panel__actions">
      <button class="ai-chip" data-action="summary">✦ 摘要</button>
      <button class="ai-chip" data-action="keypoints">☰ 要点</button>
      <button class="ai-chip" id="ai-rewrite-chip">✎ 改写</button>
    </div>
    <div class="ai-rewrite-bar" id="ai-rewrite-bar" hidden>
      <div class="ai-rewrite-bar__presets">
        ${REWRITE_PRESETS.map(
          (p, i) => `<button class="ai-rewrite-preset" data-preset="${i}">${p.label}</button>`
        ).join("")}
      </div>
      <div class="ai-rewrite-bar__custom">
        <input id="ai-rewrite-input" type="text" placeholder="自定义改写要求…" spellcheck="false" />
        <button class="ai-btn ai-btn--primary" id="ai-rewrite-go">开始</button>
      </div>
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
  const titleEl = root.querySelector<HTMLElement>("#ai-session-title")!;
  const sessionPanel = root.querySelector<HTMLElement>("#ai-session-panel")!;
  const rewriteBar = root.querySelector<HTMLElement>("#ai-rewrite-bar")!;

  let session: AiSession = ensureActive(deps.getDocName());
  let active: StreamHandle | null = null;

  // ---- rendering ----

  function renderTitle(): void {
    titleEl.textContent = session.title || "新会话";
  }

  function bubble(role: "user" | "assistant"): HTMLElement {
    const el = document.createElement("div");
    el.className = `ai-msg ai-msg--${role}`;
    transcript.appendChild(el);
    transcript.scrollTop = transcript.scrollHeight;
    return el;
  }

  function renderEmpty(): void {
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
          <p class="ai-empty__sub">点上方「摘要 / 要点 / 改写」，或直接提问。</p>
        </div>`;
    }
  }

  function renderTranscript(): void {
    if (session.messages.length === 0) {
      renderEmpty();
      return;
    }
    transcript.innerHTML = "";
    for (const m of session.messages) {
      const el = bubble(m.role);
      if (m.role === "user") el.textContent = m.content;
      else el.innerHTML = renderAiMarkdown(m.content);
    }
  }

  function renderSessionList(): void {
    const sessions = getSessions();
    sessionPanel.innerHTML = sessions
      .map(
        (s) => `
        <div class="ai-session-row ${s.id === session.id ? "current" : ""}" data-id="${s.id}">
          <button class="ai-session-row__open" data-id="${s.id}">
            <span class="ai-session-row__title">${esc(s.title || "新会话")}</span>
            <span class="ai-session-row__doc">${esc(s.docName || "")}</span>
          </button>
          <button class="ai-session-row__del" data-del="${s.id}" title="删除">✕</button>
        </div>`
      )
      .join("");

    sessionPanel.querySelectorAll<HTMLButtonElement>(".ai-session-row__open").forEach((b) =>
      b.addEventListener("click", () => switchSession(b.dataset.id!))
    );
    sessionPanel.querySelectorAll<HTMLButtonElement>(".ai-session-row__del").forEach((b) =>
      b.addEventListener("click", (e) => {
        e.stopPropagation();
        removeSession(b.dataset.del!);
      })
    );
  }

  function setBusy(busy: boolean): void {
    sendBtn.textContent = busy ? "停止" : "发送";
    sendBtn.dataset.busy = busy ? "1" : "";
  }

  function closeSessionPanel(): void {
    sessionPanel.classList.remove("open");
  }

  // ---- session ops ----

  function switchSession(id: string): void {
    if (id === session.id) {
      closeSessionPanel();
      return;
    }
    active?.cancel();
    active = null;
    setActiveId(id);
    session = ensureActive(deps.getDocName());
    setBusy(false);
    closeSessionPanel();
    renderTitle();
    renderTranscript();
  }

  function newSession(): void {
    active?.cancel();
    active = null;
    session = createSession(deps.getDocName());
    setBusy(false);
    closeSessionPanel();
    hideRewriteBar();
    renderTitle();
    renderTranscript();
  }

  function removeSession(id: string): void {
    deleteSession(id);
    if (id === session.id) {
      active?.cancel();
      active = null;
      setBusy(false);
      session = ensureActive(deps.getDocName());
      renderTitle();
      renderTranscript();
    }
    renderSessionList();
  }

  // ---- streaming ----

  // Shared streaming driver: streams into `el`, then hands the finished text to
  // onComplete (or onErr). Centralizes the cursor / active / busy bookkeeping.
  function runStream(
    req: { system: string; messages: ChatMessage[]; maxTokens?: number },
    el: HTMLElement,
    onComplete: (acc: string) => void,
    onErr: (msg: string) => void
  ): void {
    let acc = "";
    setBusy(true);
    active = streamChat(req, {
      onDelta: (t) => {
        acc += t;
        el.innerHTML = renderAiMarkdown(acc) + `<span class="ai-cursor"></span>`;
        transcript.scrollTop = transcript.scrollHeight;
      },
      onDone: () => {
        el.innerHTML = renderAiMarkdown(acc);
        active = null;
        setBusy(false);
        onComplete(acc);
      },
      onError: (m) => {
        active = null;
        setBusy(false);
        onErr(m);
      },
    });
  }

  // ---- chat ----

  function send(userText: string): void {
    if (active) return;
    if (!deps.getStatus().hasKey) {
      deps.openSettings();
      return;
    }
    // Capture the session this turn belongs to, so a mid-stream switch can't
    // misroute the reply (the visible transcript may change; the reply still
    // lands in its own session).
    const target = session;
    if (target.messages.length === 0) transcript.innerHTML = "";
    target.messages.push({ role: "user", content: userText });
    saveSession(target);
    renderTitle();
    const userEl = bubble("user");
    userEl.textContent = userText;

    const aiEl = bubble("assistant");
    aiEl.innerHTML = `<span class="ai-cursor"></span>`;

    const { system, messages, truncated } = buildRequest(deps.getDoc(), target.messages);
    if (truncated) {
      const note = document.createElement("div");
      note.className = "ai-note";
      note.textContent = "文档较长，已截取前部分用于分析。";
      transcript.insertBefore(note, aiEl);
    }

    runStream(
      { system, messages },
      aiEl,
      (acc) => {
        target.messages.push({ role: "assistant", content: acc });
        saveSession(target);
      },
      (m) => {
        aiEl.innerHTML = `<div class="ai-error">出错了：${esc(m)} <button class="ai-retry">重试</button></div>`;
        aiEl.querySelector(".ai-retry")!.addEventListener("click", () => {
          if (active) return;
          target.messages.pop();
          saveSession(target);
          aiEl.remove();
          userEl.remove();
          send(userText);
        });
      }
    );
  }

  // ---- rewrite (one-off, not part of chat history) ----

  function hideRewriteBar(): void {
    rewriteBar.hidden = true;
  }

  function startRewrite(instruction: string): void {
    if (active) return;
    if (!deps.getStatus().hasKey) {
      deps.openSettings();
      return;
    }
    hideRewriteBar();
    if (session.messages.length === 0) transcript.innerHTML = "";

    const head = document.createElement("div");
    head.className = "ai-rewrite-head";
    head.textContent = `改写预览 · ${instruction}`;
    transcript.appendChild(head);

    const card = bubble("assistant");
    card.classList.add("ai-rewrite-preview");
    card.innerHTML = `<span class="ai-cursor"></span>`;

    const { system } = buildRequest(deps.getDoc(), []);
    runStream(
      { system, messages: [{ role: "user", content: rewriteUserMessage(instruction) }], maxTokens: 4096 },
      card,
      (acc) => {
        const bar = document.createElement("div");
        bar.className = "ai-rewrite-actions";
        bar.innerHTML = `
          <button class="ai-btn ai-btn--primary" id="ai-apply">应用到文档</button>
          <button class="ai-btn" id="ai-discard">放弃</button>`;
        card.appendChild(bar);
        bar.querySelector("#ai-apply")!.addEventListener("click", () => {
          deps.onApplyRewrite(acc);
          bar.innerHTML = `<span class="ai-applied">已应用到文档 ✓</span>`;
        });
        bar.querySelector("#ai-discard")!.addEventListener("click", () => {
          head.remove();
          card.remove();
        });
      },
      (m) => {
        card.innerHTML = `<div class="ai-error">改写失败：${esc(m)}</div>`;
      }
    );
  }

  // ---- wiring ----

  root.querySelectorAll<HTMLButtonElement>(".ai-chip[data-action]").forEach((chip) =>
    chip.addEventListener("click", () => send(actionUserMessage(chip.dataset.action as QuickAction)))
  );

  root.querySelector("#ai-rewrite-chip")!.addEventListener("click", () => {
    rewriteBar.hidden = !rewriteBar.hidden;
  });
  rewriteBar.querySelectorAll<HTMLButtonElement>(".ai-rewrite-preset").forEach((b) =>
    b.addEventListener("click", () => startRewrite(REWRITE_PRESETS[Number(b.dataset.preset)].instruction))
  );
  const rewriteInput = root.querySelector<HTMLInputElement>("#ai-rewrite-input")!;
  root.querySelector("#ai-rewrite-go")!.addEventListener("click", () => {
    const v = rewriteInput.value.trim();
    if (v) {
      rewriteInput.value = "";
      startRewrite(v);
    }
  });

  root.querySelector("#ai-session-btn")!.addEventListener("click", (e) => {
    e.stopPropagation();
    const willOpen = !sessionPanel.classList.contains("open");
    closeSessionPanel();
    if (willOpen) {
      renderSessionList();
      sessionPanel.classList.add("open");
    }
  });

  root.querySelector("#ai-new-session")!.addEventListener("click", newSession);
  root.querySelector("#ai-open-settings")!.addEventListener("click", () => deps.openSettings());
  root.querySelector("#ai-panel-close")!.addEventListener("click", () => deps.onClose());

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

  renderTitle();
  renderTranscript();

  return {
    // Called when a new document is opened. Start a fresh session only if the
    // current one already has messages (so old chats stay in the list); reuse an
    // empty session, just updating its document context.
    reset(): void {
      active?.cancel();
      active = null;
      setBusy(false);
      hideRewriteBar();
      if (session.messages.length > 0) {
        session = createSession(deps.getDocName());
      } else {
        session.docName = deps.getDocName();
        saveSession(session);
      }
      renderTitle();
      renderTranscript();
    },
    refreshState(): void {
      renderTranscript();
    },
  };
}
