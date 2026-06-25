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
