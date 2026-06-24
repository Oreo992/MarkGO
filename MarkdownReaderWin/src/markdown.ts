// Markdown -> HTML rendering. markdown-it core + GFM tables + task lists +
// highlight.js, plus a fenced-code renderer that produces the macOS reader's
// code-block chrome (language tag + copy button) and tags mermaid fences.

import MarkdownIt from "markdown-it";
import type { PluginSimple } from "markdown-it";
import hljs from "highlight.js";
import taskLists from "markdown-it-task-lists";

const md = new MarkdownIt({
  html: false,
  linkify: true,
  breaks: false,
  typographer: false,
});

md.use(taskLists as unknown as PluginSimple, { enabled: true, label: true });

// ---- Heading slugs so the outline can scroll to sections ----
let headingCounter = 0;
const defaultHeadingOpen =
  md.renderer.rules.heading_open ||
  ((tokens, idx, options, _env, self) => self.renderToken(tokens, idx, options));

md.renderer.rules.heading_open = (tokens, idx, options, env, self) => {
  tokens[idx].attrSet("id", `section-${headingCounter}`);
  headingCounter += 1;
  return defaultHeadingOpen(tokens, idx, options, env, self);
};

// ---- Fenced code -> styled block (or mermaid placeholder) ----
md.renderer.rules.fence = (tokens, idx) => {
  const token = tokens[idx];
  const info = token.info.trim();
  const lang = info.split(/\s+/)[0] || "";
  const code = token.content;

  if (lang.toLowerCase() === "mermaid" || lang.toLowerCase() === "mmd") {
    return `<div class="mermaid-block"><div class="mermaid">${escapeHtml(
      code
    )}</div></div>`;
  }

  let highlighted: string;
  if (lang && hljs.getLanguage(lang)) {
    try {
      highlighted = hljs.highlight(code, { language: lang }).value;
    } catch {
      highlighted = escapeHtml(code);
    }
  } else {
    highlighted = escapeHtml(code);
  }

  const label = (lang || "code").toUpperCase();
  return `
    <div class="code-block" data-code="${encodeURIComponent(code)}">
      <div class="code-block__bar">
        <span class="code-block__lang">${escapeHtml(label)}</span>
        <button class="code-block__copy" type="button" title="复制代码">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          复制
        </button>
      </div>
      <pre><code class="hljs language-${escapeHtml(lang)}">${highlighted}</code></pre>
    </div>`;
};

export function renderMarkdown(text: string): string {
  headingCounter = 0;
  return md.render(text);
}

export function hasMermaid(text: string): boolean {
  return /(^|\n)```\s*(mermaid|mmd)\s*(\n|$)/i.test(text);
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
