// Export pipeline. HTML/Markdown are faithful 1:1 ports of ExportRunner.swift
// (makeHTMLDocument + htmlStylesheet). PDF/PNG render the document offscreen
// with html-to-image and paginate into jsPDF, mirroring the macOS long-image
// and paged-PDF behaviors.

import { renderMarkdown, hasMermaid } from "./markdown";
import { normalizeMarkdown } from "./normalize";
import { saveTextFile, saveBinaryFile } from "./file-io";

export type ExportFormat = "pdf" | "longImage" | "html" | "markdown";
export type ExportThemeId = "clear" | "paper" | "report" | "lesson" | "card";

interface ExportTheme {
  id: ExportThemeId;
  title: string;
  background: string;
  ink: string;
  accent: string;
}

export const EXPORT_THEMES: ExportTheme[] = [
  { id: "clear", title: "清读", background: "#f6f2e8", ink: "#1c1f21", accent: "#386b74" },
  { id: "paper", title: "纸张", background: "#fbf7ec", ink: "#1c1f21", accent: "#334f9e" },
  { id: "report", title: "报告", background: "#f2f4fb", ink: "#1c1f21", accent: "#6b4d8f" },
  { id: "lesson", title: "讲义", background: "#f6f1e2", ink: "#1c1f21", accent: "#d09c3c" },
  { id: "card", title: "卡片", background: "#faf0e6", ink: "#1c1f21", accent: "#944f2e" },
];

export const PAGE_SIZES = {
  a4: { title: "A4", w: 595, h: 842 },
  letter: { title: "Letter", w: 612, h: 792 },
  a5: { title: "A5", w: 420, h: 595 },
} as const;
export type PageSizeId = keyof typeof PAGE_SIZES;

export const IMAGE_WIDTHS = {
  compact: { title: "750", w: 750 },
  standard: { title: "1080", w: 1080 },
  wide: { title: "1440", w: 1440 },
} as const;
export type ImageWidthId = keyof typeof IMAGE_WIDTHS;

export function themeById(id: ExportThemeId): ExportTheme {
  return EXPORT_THEMES.find((t) => t.id === id) ?? EXPORT_THEMES[0];
}

function sanitize(title: string): string {
  const cleaned = title.replace(/[/:\\]/g, "-").trim();
  return cleaned || "Markdown";
}

// ---- HTML (faithful port of makeHTMLDocument / htmlStylesheet) ----

export function buildHtmlDocument(title: string, text: string, theme: ExportTheme): string {
  const body = renderMarkdown(normalizeMarkdown(text));
  const mermaidRuntime = hasMermaid(text) ? mermaidRuntimeScript() : "";
  return `<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>${htmlStylesheet(theme)}</style>
</head>
<body>
<main class="page">
<h1 class="brand">${escapeHtml(title)}</h1>
${body}
<footer>Made with MarkGo · Markdown Reader &amp; Presenter</footer>
</main>
${mermaidRuntime}
</body>
</html>`;
}

function htmlStylesheet(theme: ExportTheme): string {
  const { background: bg, ink, accent } = theme;
  return `
:root { color-scheme: light; }
body { margin: 0; background: ${bg}; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif; color: ${ink}; }
.page { max-width: 760px; margin: 48px auto; padding: 32px 40px 64px; background: #fff; border-radius: 18px; box-shadow: 0 18px 48px rgba(0,0,0,0.08); }
.brand { font-weight: 800; font-size: 2.0em; color: ${accent}; border-bottom: 2px solid ${accent}; padding-bottom: 12px; margin-top: 0; }
h1, h2, h3, h4, h5, h6 { color: ${ink}; line-height: 1.32; }
h2 { border-bottom: 1px solid rgba(0,0,0,0.08); padding-bottom: 6px; }
p { line-height: 1.78; font-size: 16px; }
blockquote { margin: 0 0 16px; padding: 12px 18px; background: rgba(0,0,0,0.04); border-left: 4px solid ${accent}; border-radius: 8px; color: rgba(0,0,0,0.78); }
code { font-family: ui-monospace, "Cascadia Code", "SF Mono", Consolas, monospace; background: rgba(0,0,0,0.06); padding: 2px 6px; border-radius: 4px; font-size: 0.92em; }
pre { background: rgba(0,0,0,0.05); padding: 16px; border-radius: 12px; overflow-x: auto; }
pre code { background: transparent; padding: 0; }
.code-block { background: rgba(0,0,0,0.05); border-radius: 12px; overflow: hidden; margin: 0 0 16px; }
.code-block__bar { display: flex; justify-content: space-between; padding: 10px 14px 0; font-size: 11px; font-weight: 800; color: ${accent}; }
.code-block__copy { display: none; }
.mermaid { overflow-x: auto; padding: 18px; margin: 18px 0; background: rgba(255,255,255,0.55); border: 1px solid rgba(0,0,0,0.08); border-radius: 14px; }
.mermaid svg { max-width: 100%; height: auto; display: block; margin: 0 auto; }
.mermaid-block { margin: 18px 0; }
img { max-width: 100%; height: auto; border-radius: 12px; display: block; margin: 16px 0; }
table { border-collapse: collapse; width: 100%; margin: 16px 0; }
th, td { border: 1px solid rgba(0,0,0,0.10); padding: 8px 12px; text-align: left; }
th { background: rgba(0,0,0,0.04); }
a { color: ${accent}; }
ul, ol { line-height: 1.78; padding-left: 1.4em; }
hr { border: 0; border-top: 1px solid rgba(0,0,0,0.10); margin: 28px 0; }
footer { text-align: center; font-size: 12px; color: rgba(0,0,0,0.45); margin-top: 32px; }
`;
}

function mermaidRuntimeScript(): string {
  return `<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
<script>
document.querySelectorAll('.mermaid-block .mermaid').forEach(function(n){ n.classList.add('__mm'); });
mermaid.initialize({ startOnLoad: true, securityLevel: "strict", theme: "base", themeVariables: { fontFamily: "-apple-system, Segoe UI, PingFang SC, sans-serif", primaryColor: "#e7f7f4", primaryTextColor: "#1d2324", primaryBorderColor: "#18b7ad", lineColor: "#18b7ad" } });
</script>`;
}

// ---- Offscreen render node for image/pdf export ----

function buildExportNode(title: string, text: string, theme: ExportTheme, width: number): HTMLElement {
  const node = document.createElement("div");
  node.style.cssText = `position:fixed;left:-99999px;top:0;width:${width}px;background:${theme.background};`;
  node.innerHTML = `
    <div style="max-width:${width}px;margin:0 auto;padding:48px 56px 64px;background:#fff;color:${theme.ink};font-family:-apple-system,'Segoe UI','PingFang SC','Microsoft YaHei',sans-serif;">
      <h1 style="font-weight:800;font-size:2em;color:${theme.accent};border-bottom:2px solid ${theme.accent};padding-bottom:12px;margin:0 0 24px;">${escapeHtml(title)}</h1>
      <div class="markdown-body" style="--accent:${theme.accent};font-size:16px;line-height:1.78;">${renderMarkdown(normalizeMarkdown(text))}</div>
    </div>`;
  return node;
}

// ---- PNG long image ----

export async function exportLongImage(
  title: string,
  text: string,
  theme: ExportTheme,
  width: number
): Promise<string | null> {
  const { toPng } = await import("html-to-image");
  const node = buildExportNode(title, text, theme, width);
  document.body.appendChild(node);
  try {
    await waitForImages(node);
    const dataUrl = await toPng(node, {
      pixelRatio: 2,
      backgroundColor: theme.background,
      width,
      height: node.scrollHeight,
    });
    const bytes = dataUrlToBytes(dataUrl);
    return saveBinaryFile(`${sanitize(title)}.png`, bytes, "image/png", [
      { name: "PNG", extensions: ["png"] },
    ]);
  } finally {
    node.remove();
  }
}

// ---- PDF (paginate a tall canvas) ----

export async function exportPdf(
  title: string,
  text: string,
  theme: ExportTheme,
  pageSize: { w: number; h: number }
): Promise<string | null> {
  const [{ toCanvas }, { jsPDF }] = await Promise.all([
    import("html-to-image"),
    import("jspdf"),
  ]);

  const renderWidth = 820;
  const node = buildExportNode(title, text, theme, renderWidth);
  document.body.appendChild(node);

  try {
    await waitForImages(node);
    const canvas = await toCanvas(node, {
      pixelRatio: 2,
      backgroundColor: theme.background,
      width: renderWidth,
      height: node.scrollHeight,
    });

    const pdf = new jsPDF({
      orientation: pageSize.w > pageSize.h ? "landscape" : "portrait",
      unit: "pt",
      format: [pageSize.w, pageSize.h],
    });

    const imgW = pageSize.w;
    const scale = imgW / canvas.width;
    const pageCanvasHeight = Math.floor(pageSize.h / scale);
    let renderedHeight = 0;
    let first = true;

    while (renderedHeight < canvas.height) {
      const sliceHeight = Math.min(pageCanvasHeight, canvas.height - renderedHeight);
      const slice = document.createElement("canvas");
      slice.width = canvas.width;
      slice.height = sliceHeight;
      const ctx = slice.getContext("2d");
      if (!ctx) break;
      ctx.fillStyle = theme.background;
      ctx.fillRect(0, 0, slice.width, slice.height);
      ctx.drawImage(
        canvas,
        0,
        renderedHeight,
        canvas.width,
        sliceHeight,
        0,
        0,
        canvas.width,
        sliceHeight
      );

      if (!first) pdf.addPage([pageSize.w, pageSize.h]);
      first = false;
      pdf.addImage(
        slice.toDataURL("image/jpeg", 0.95),
        "JPEG",
        0,
        0,
        imgW,
        sliceHeight * scale
      );
      renderedHeight += sliceHeight;
    }

    const blob = pdf.output("arraybuffer");
    return saveBinaryFile(
      `${sanitize(title)}.pdf`,
      new Uint8Array(blob),
      "application/pdf",
      [{ name: "PDF", extensions: ["pdf"] }]
    );
  } finally {
    node.remove();
  }
}

// ---- Markdown / HTML save ----

export function exportHtml(title: string, text: string, theme: ExportTheme): Promise<string | null> {
  return saveTextFile(`${sanitize(title)}.html`, buildHtmlDocument(title, text, theme), [
    { name: "HTML", extensions: ["html"] },
  ]);
}

export function exportMarkdown(title: string, text: string): Promise<string | null> {
  return saveTextFile(`${sanitize(title)}.md`, text, [
    { name: "Markdown", extensions: ["md"] },
  ]);
}

// ---- helpers ----

function waitForImages(node: HTMLElement): Promise<void> {
  const images = Array.from(node.querySelectorAll("img"));
  return Promise.all(
    images.map(
      (img) =>
        new Promise<void>((resolve) => {
          if (img.complete) resolve();
          else {
            img.onload = () => resolve();
            img.onerror = () => resolve();
          }
        })
    )
  ).then(() => undefined);
}

function dataUrlToBytes(dataUrl: string): Uint8Array {
  const base64 = dataUrl.split(",")[1] ?? "";
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
