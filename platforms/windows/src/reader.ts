// Reader surface controller. Renders Markdown into a scroll container and
// wires the behaviors the macOS ReaderSurface provides: image resolution,
// copy-code buttons, mermaid rendering and outline scroll-sync.

import { renderMarkdown, hasMermaid } from "./markdown";
import { resolveImageSrc } from "./platform";

export interface ReaderRenderOptions {
  title: string;
  text: string;
  baseDir: string | null;
  onCurrentSection?: (sectionId: string) => void;
}

let mermaidLoaded = false;

export async function renderReader(
  body: HTMLElement,
  options: ReaderRenderOptions
): Promise<void> {
  const html = renderMarkdown(options.text);
  body.innerHTML = html;

  attachCopyButtons(body);
  await resolveImages(body, options.baseDir);
  if (hasMermaid(options.text)) {
    await renderMermaid(body);
  }
}

function attachCopyButtons(root: HTMLElement): void {
  root.querySelectorAll<HTMLButtonElement>(".code-block__copy").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const block = btn.closest<HTMLElement>(".code-block");
      const encoded = block?.dataset.code;
      if (!encoded) return;
      const code = decodeURIComponent(encoded);
      try {
        await navigator.clipboard.writeText(code);
        const original = btn.lastChild?.textContent;
        if (btn.lastChild) btn.lastChild.textContent = " 已复制";
        setTimeout(() => {
          if (btn.lastChild && original) btn.lastChild.textContent = original;
        }, 1200);
      } catch {
        /* clipboard unavailable */
      }
    });
  });
}

async function resolveImages(root: HTMLElement, baseDir: string | null): Promise<void> {
  const images = Array.from(root.querySelectorAll<HTMLImageElement>("img"));
  await Promise.all(
    images.map(async (img) => {
      const raw = img.getAttribute("src");
      if (!raw) return;
      const resolved = await resolveImageSrc(raw, baseDir);
      if (resolved !== raw) img.setAttribute("src", resolved);
    })
  );
}

async function renderMermaid(root: HTMLElement): Promise<void> {
  const nodes = Array.from(root.querySelectorAll<HTMLElement>(".mermaid"));
  if (nodes.length === 0) return;

  try {
    const mermaid = (await import("mermaid")).default;
    if (!mermaidLoaded) {
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: "base",
        themeVariables: {
          fontFamily: "-apple-system, Segoe UI, PingFang SC, sans-serif",
          primaryColor: "#e7f7f4",
          primaryTextColor: "#1d2324",
          primaryBorderColor: "#18b7ad",
          lineColor: "#18b7ad",
          secondaryColor: "#fff7ea",
          tertiaryColor: "#f6efe4",
        },
      });
      mermaidLoaded = true;
    }
    for (let i = 0; i < nodes.length; i += 1) {
      const node = nodes[i];
      const source = node.textContent ?? "";
      try {
        const { svg } = await mermaid.render(`mg-mermaid-${Date.now()}-${i}`, source);
        node.innerHTML = svg;
      } catch (error) {
        node.innerHTML = `<pre>Mermaid 解析失败\n\n${String(error)}</pre>`;
      }
    }
  } catch {
    /* mermaid failed to load; leave source visible */
  }
}

/**
 * Scroll-spy: reports the heading section currently nearest the top of the
 * viewport so the outline can highlight it (and the host can persist it).
 */
export function installScrollSpy(
  scroller: HTMLElement,
  body: HTMLElement,
  onCurrentSection: (sectionId: string) => void
): () => void {
  let frame = 0;
  let lastId = "";

  const handler = () => {
    if (frame) return;
    frame = requestAnimationFrame(() => {
      frame = 0;
      const headings = Array.from(
        body.querySelectorAll<HTMLElement>("h1[id], h2[id], h3[id], h4[id], h5[id], h6[id]")
      );
      const top = scroller.getBoundingClientRect().top + 120;
      let currentId = headings[0]?.id ?? "";
      for (const h of headings) {
        if (h.getBoundingClientRect().top <= top) currentId = h.id;
        else break;
      }
      if (currentId && currentId !== lastId) {
        lastId = currentId;
        onCurrentSection(currentId);
      }
    });
  };

  scroller.addEventListener("scroll", handler, { passive: true });
  handler();
  return () => scroller.removeEventListener("scroll", handler);
}
