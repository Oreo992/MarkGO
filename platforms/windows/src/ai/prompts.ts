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
