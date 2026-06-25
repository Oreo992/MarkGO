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

// Whole-document rewrite: returns ONLY the revised Markdown so it can be applied
// back to the document. `instruction` is the user's rewrite request.
export function rewriteUserMessage(instruction: string): string {
  return (
    "请按下面的要求改写这篇文档。只输出改写后的【完整 Markdown 正文】，" +
    "保留原有结构与信息，不要添加任何解释、前言或代码围栏包裹。\n\n要求：" +
    instruction
  );
}

export const REWRITE_PRESETS: { label: string; instruction: string }[] = [
  { label: "润色全文", instruction: "在不改变原意的前提下润色语言，使表达更通顺自然。" },
  { label: "改成正式", instruction: "改写为正式、书面、专业的口吻。" },
  { label: "改得简洁", instruction: "在保留关键信息的前提下精简，删除冗余。" },
];
