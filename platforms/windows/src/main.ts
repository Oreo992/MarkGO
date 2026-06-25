import "./styles/tokens.css";
import "./styles/app.css";
import "./styles/chrome.css";
import "./ai/styles/ai.css";
import "./styles/sidebar.css";
import "./styles/reader.css";
import "./styles/editor.css";
import "./styles/export.css";
import "./styles/library.css";
import "highlight.js/styles/github.css";

import markgoIcon from "./assets/markgo-icon.png";
import { READING_MODES, DEFAULT_MODE, type ReadingModeId } from "./modes";
import { analyze, type MarkdownAnalysis } from "./analysis";
import { renderReader, installScrollSpy } from "./reader";
import { normalizeMarkdown } from "./normalize";
import { openMarkdownFile, openMarkdownPath } from "./file-io";
import {
  buildMenus,
  menuButtonHtml,
  wireMenuButton,
  type MenuContext,
} from "./menus";
import { getRecent, pushRecent, clearRecent, type RecentItem } from "./recent";
import {
  minimizeWindow,
  toggleMaximizeWindow,
  closeWindow,
  onMaximizeChange,
  openExternalUrl,
  initResizeHandles,
} from "./window";
import { checkUpdate, type UpdateInfo } from "./updater";
import {
  EXPORT_THEMES,
  PAGE_SIZES,
  IMAGE_WIDTHS,
  themeById,
  exportHtml,
  exportMarkdown,
  exportLongImage,
  exportPdf,
  type ExportThemeId,
  type PageSizeId,
  type ImageWidthId,
} from "./export";
import { DEMO_MARKDOWN } from "./demo";
import { getAiStatus } from "./ai/client";
import { aiPanelHtml, createAiPanel } from "./ai/panel";
import { settingsModalHtml, wireSettings, openSettings, closeSettings } from "./ai/settings";

type WorkspaceMode = "read" | "edit";
type EditorLayout = "source" | "split" | "preview";

interface AppState {
  text: string;
  path: string | null;
  baseDir: string | null;
  displayName: string | null;
  mode: ReadingModeId;
  workspace: WorkspaceMode;
  layout: EditorLayout;
  fontScale: number;
  hasDocument: boolean;
  analysis: MarkdownAnalysis;
}

const FONT_MIN = 0.75;
const FONT_MAX = 1.6;

const state: AppState = {
  text: "",
  path: null,
  baseDir: null,
  displayName: null,
  mode: DEFAULT_MODE,
  workspace: "read",
  layout: "split",
  fontScale: 1,
  hasDocument: false,
  analysis: analyze(""),
};

const root = document.getElementById("app")!;
let detachScrollSpy: (() => void) | null = null;
let reparseTimer = 0;
let aiOpen = false;
let aiStatus = { hasKey: false };
let aiPanel: { reset: () => void; refreshState: () => void } | null = null;
let aiConsented = localStorage.getItem("markgo.ai.consent") === "1";

function icon(path: string, size = 16): string {
  return `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="${path}"/></svg>`;
}

const ICONS = {
  book: "M4 19.5A2.5 2.5 0 0 1 6.5 17H20M4 19.5A2.5 2.5 0 0 0 6.5 22H20V2H6.5A2.5 2.5 0 0 0 4 4.5z",
  pencil: "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z",
  type: "M4 7V5h16v2M9 19h6M12 5v14",
  upload: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12",
  folder: "M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z",
  sidebar: "M3 3h18v18H3zM9 3v18",
  doc: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8zM14 2v6h6",
};

const HOMEPAGE_URL = "https://github.com/Oreo992/MarkGO";
const APP_VERSION = "1.0.0";

// Window-control glyphs (drawn inline so they keep crisp 1px strokes).
const WIN_ICON = {
  min: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M5 12h14"/></svg>`,
  max: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="5.5" y="5.5" width="13" height="13" rx="1.5"/></svg>`,
  restore: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="7.5" y="7.5" width="11" height="11" rx="1.5"/><path d="M5.5 14.5V6.5a1 1 0 0 1 1-1h8"/></svg>`,
  close: `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><path d="M6 6l12 12M18 6L6 18"/></svg>`,
};

// ---- Top-level render ----

function render(): void {
  document.documentElement.setAttribute("data-mode", state.mode);
  document.documentElement.style.setProperty("--reader-font-scale", String(state.fontScale));

  const menus = buildMenus(menuContext());
  root.innerHTML = `
    ${chromeHtml(menus)}
    ${state.hasDocument ? workspaceHtml() : libraryHtml()}
    ${exportSheetHtml()}
    ${aboutHtml()}
    ${updateHtml()}
    ${settingsModalHtml()}`;

  wireChrome(menus);
  if (state.hasDocument) {
    wireInlineTools();
    wireSidebar();
    renderContent();
    wireAiSettings();
    if (aiOpen) {
      aiPanel = createAiPanel(root.querySelector(".ai-panel")!, {
        getDoc: () => state.text,
        getDocName: () => documentTitle(),
        getStatus: () => aiStatus,
        openSettings: () => openAiSettings(),
        onClose: () => void toggleAi(),
        onApplyRewrite: (md) => applyRewrite(md),
      });
    }
  } else {
    wireLibrary();
    wireAiSettings();
  }
}

function libraryHtml(): string {
  return `
    <div class="library">
      <img class="library__logo" src="${markgoIcon}" alt="MarkGo" width="88" height="88" />
      <h1 class="library__title">MarkGo</h1>
      <p class="library__tagline">为 Windows 打造的 Markdown 阅读与演示器 · 与 macOS 同源设计</p>
      <div class="library__actions">
        <button class="library__btn library__btn--primary" id="lib-open">${icon(ICONS.folder)} 打开文件</button>
        <button class="library__btn" id="lib-demo">${icon(ICONS.book)} 查看示例文档</button>
      </div>
      ${recentLibraryHtml()}
      <div class="library__modes">
        ${READING_MODES.map(
          (m) => `
          <div class="library__mode-pill">
            <span class="dot" style="background:${m.accent}"></span>
            <span class="name">${m.title}</span>
            <span class="sub">${m.subtitle}</span>
          </div>`
        ).join("")}
      </div>
    </div>`;
}

function recentLibraryHtml(): string {
  const recent = getRecent();
  if (recent.length === 0) return "";
  return `
    <div class="library__recent">
      <div class="library__recent-head">
        <span class="library__recent-title">最近打开</span>
        <button class="library__recent-clear" id="lib-recent-clear">清除</button>
      </div>
      <div class="library__recent-list">
        ${recent
          .map(
            (r, i) => `
          <button class="recent-card" data-recent="${i}" title="${escapeText(r.path)}">
            <span class="recent-card__icon">${icon(ICONS.doc, 17)}</span>
            <span class="recent-card__text">
              <span class="recent-card__name">${escapeText(r.name)}</span>
              <span class="recent-card__path">${escapeText(prettyDir(r.path))}</span>
            </span>
          </button>`
          )
          .join("")}
      </div>
    </div>`;
}

function prettyDir(path: string): string {
  const dir = path.replace(/[\\/][^\\/]*$/, "");
  return dir.length > 48 ? "…" + dir.slice(-47) : dir;
}

function wireLibrary(): void {
  document.getElementById("lib-open")!.addEventListener("click", handleOpen);
  document.getElementById("lib-demo")!.addEventListener("click", () => {
    loadDocument(DEMO_MARKDOWN, null, "MarkGo 示例");
  });

  const recent = getRecent();
  root.querySelectorAll<HTMLButtonElement>(".recent-card").forEach((card) =>
    card.addEventListener("click", () => {
      const item = recent[Number(card.dataset.recent)];
      if (item) handleOpenRecent(item);
    })
  );
  root.querySelector("#lib-recent-clear")?.addEventListener("click", () => {
    clearRecent();
    render();
  });
}

function workspaceHtml(): string {
  return `
    <div class="workspace">
      ${sidebarHtml()}
      <div class="workspace__content" id="content"></div>
      ${aiOpen ? aiPanelHtml() : ""}
    </div>`;
}

// ---- Window chrome (single merged bar) ----

function chromeHtml(menus: ReturnType<typeof buildMenus>): string {
  const doc = state.hasDocument;

  const leftTools = doc
    ? `
      <div class="workspace-switch">
        <button class="workspace-switch__btn" data-ws="read" aria-pressed="${state.workspace === "read"}">${icon(ICONS.book, 13)} 阅读</button>
        <button class="workspace-switch__btn" data-ws="edit" aria-pressed="${state.workspace === "edit"}">${icon(ICONS.pencil, 13)} 编辑</button>
      </div>
      <button class="tool-btn" id="toggle-outline" title="显示 / 隐藏目录">${icon(ICONS.sidebar)}</button>
      ${state.workspace === "edit" ? layoutSegmentHtml() : ""}`
    : "";

  const centerTools = doc
    ? `
      <div class="mode-strip">
        ${READING_MODES.map(
          (m) => `
          <button class="mode-chip" data-mode="${m.id}" aria-pressed="${state.mode === m.id}" style="--chip-accent:${m.accent}" title="${m.title} · ${m.subtitle}">
            ${icon(m.icon, 12)} ${m.title}
          </button>`
        ).join("")}
      </div>`
    : "";

  const rightTools = doc
    ? `
      <button class="tool-btn ${aiOpen ? "tool-btn--prominent" : ""}" id="ai-toggle" title="AI 助手">✦ AI</button>
      <div class="menu" id="font-menu">
        <button class="tool-btn" id="font-btn" title="阅读字号">${icon(ICONS.type)}</button>
        ${fontPopoverHtml()}
      </div>
      <div class="menu" id="export-menu">
        <button class="tool-btn tool-btn--prominent" id="export-btn" title="导出与分享">${icon(ICONS.upload)} 导出</button>
        <div class="menu__panel" id="export-panel">
          <button class="menu__item" data-export="pdf">导出 PDF</button>
          <button class="menu__item" data-export="longImage">导出长图</button>
          <button class="menu__item" data-export="html">导出 HTML</button>
          <button class="menu__item" data-export="markdown">导出 Markdown</button>
          <div class="menu__divider"></div>
          <button class="menu__item" data-export="copyRich">复制富文本</button>
          <button class="menu__item" data-export="copyPlain">复制纯文本</button>
        </div>
      </div>`
    : "";

  // Three flex:1 zones keep the mode strip geometrically centered; empty zone
  // space is draggable. Window controls sit flush in the right zone.
  return `
  <div class="titlebar">
    <div class="titlebar__zone titlebar__zone--left" data-tauri-drag-region>
      ${menuButtonHtml(menus)}
      ${leftTools}
    </div>
    <div class="titlebar__zone titlebar__zone--center" data-tauri-drag-region>
      ${centerTools}
    </div>
    <div class="titlebar__zone titlebar__zone--right" data-tauri-drag-region>
      ${rightTools}
      <div class="winctl">
        <button class="winctl__btn" id="win-min" title="最小化">${WIN_ICON.min}</button>
        <button class="winctl__btn" id="win-max" title="最大化">${WIN_ICON.max}</button>
        <button class="winctl__btn winctl__btn--close" id="win-close" title="关闭">${WIN_ICON.close}</button>
      </div>
    </div>
  </div>`;
}

function aboutHtml(): string {
  return `
  <div class="about-backdrop" id="about-backdrop">
    <div class="about">
      <img class="about__logo" src="${markgoIcon}" alt="MarkGo" width="64" height="64" />
      <div class="about__name">MarkGo</div>
      <div class="about__version">Windows · v${APP_VERSION}</div>
      <p class="about__tagline">轻量的 Markdown 阅读与呈现器。把 .md 变成可阅读、可分享、可交付的成品。与 macOS 版同源设计。</p>
      <div class="about__actions">
        <button class="about__btn" id="about-home">项目主页</button>
        <button class="about__btn about__btn--primary" id="about-close">好的</button>
      </div>
    </div>
  </div>`;
}

// Custom update card (replaces the native OS update dialog). Version + notes
// are filled in by showUpdate() when an update is found.
function updateHtml(): string {
  return `
  <div class="about-backdrop" id="update-backdrop">
    <div class="about update-card">
      <div class="update-card__badge">${icon(ICONS.upload, 26)}</div>
      <div class="about__name">发现新版本</div>
      <div class="update-card__ver">
        <span class="update-card__new" id="update-new"></span>
        <span class="update-card__old" id="update-old"></span>
      </div>
      <div class="update-card__notes" id="update-notes"></div>
      <div class="update-card__status" id="update-status"></div>
      <div class="about__actions">
        <button class="about__btn" id="update-later">稍后</button>
        <button class="about__btn about__btn--primary" id="update-now">立即更新</button>
      </div>
    </div>
  </div>`;
}

function layoutSegmentHtml(): string {
  const layouts: { id: EditorLayout; label: string }[] = [
    { id: "source", label: "源码" },
    { id: "split", label: "分屏" },
    { id: "preview", label: "预览" },
  ];
  return `<div class="segmented" id="layout-seg">${layouts
    .map(
      (l) =>
        `<button data-layout="${l.id}" aria-pressed="${state.layout === l.id}">${l.label}</button>`
    )
    .join("")}</div>`;
}

function fontPopoverHtml(): string {
  return `
  <div class="popover" id="font-popover">
    <div class="popover__head">
      ${icon(ICONS.type, 14)}
      <span class="popover__title">阅读字号</span>
      <span class="popover__pct" id="font-pct">${Math.round(state.fontScale * 100)}%</span>
    </div>
    <input type="range" id="font-range" min="${FONT_MIN}" max="${FONT_MAX}" step="0.01" value="${state.fontScale}">
    <div class="popover__scale-labels"><span>${Math.round(FONT_MIN * 100)}%</span><span>${Math.round(FONT_MAX * 100)}%</span></div>
  </div>`;
}

// Snapshot of state + handlers handed to the menu builder each render.
function menuContext(): MenuContext {
  return {
    hasDocument: state.hasDocument,
    workspace: state.workspace,
    mode: state.mode,
    layout: state.layout,
    onOpen: handleOpen,
    onOpenRecent: handleOpenRecent,
    onClearRecent: () => {
      clearRecent();
      render();
    },
    onLoadDemo: () => loadDocument(DEMO_MARKDOWN, null, "MarkGo 示例"),
    onExport: handleExport,
    onQuit: () => void closeWindow(),
    onToggleWorkspace: () =>
      setWorkspace(state.workspace === "edit" ? "read" : "edit"),
    onCopy: handleCopy,
    onSetMode: setMode,
    onSetLayout: setLayout,
    onToggleOutline: toggleOutline,
    onFont: adjustFont,
    onAbout: openAbout,
    onHomepage: () => void openExternalUrl(HOMEPAGE_URL),
    onCheckUpdate: () => void handleCheckUpdate(false),
    onToggleAi: () => void toggleAi(),
    onAiSettings: () => openAiSettings(),
  };
}

// Wires the always-present chrome: menu bar, window controls, about modal.
function wireChrome(menus: ReturnType<typeof buildMenus>): void {
  const titlebar = root.querySelector<HTMLElement>(".titlebar")!;
  wireMenuButton(titlebar, menus, closeMenus);

  root.querySelector("#win-min")!.addEventListener("click", () => void minimizeWindow());
  root.querySelector("#win-max")!.addEventListener("click", () => void toggleMaximizeWindow());
  root.querySelector("#win-close")!.addEventListener("click", () => void closeWindow());

  root.querySelector("#about-backdrop")!.addEventListener("click", (e) => {
    if (e.target === e.currentTarget) closeAbout();
  });
  root.querySelector("#about-close")!.addEventListener("click", closeAbout);
  root.querySelector("#about-home")!.addEventListener("click", () => void openExternalUrl(HOMEPAGE_URL));

  root.querySelector("#update-backdrop")!.addEventListener("click", (e) => {
    if (e.target === e.currentTarget) closeUpdate();
  });
  root.querySelector("#update-later")!.addEventListener("click", closeUpdate);
  root.querySelector("#update-now")!.addEventListener("click", () => void runPendingUpdate());
}

// Wires the document-only inline tools (workspace switch, modes, font, export).
function wireInlineTools(): void {
  root.querySelectorAll<HTMLButtonElement>(".workspace-switch__btn").forEach((btn) =>
    btn.addEventListener("click", () => setWorkspace(btn.dataset.ws as WorkspaceMode))
  );
  root.querySelectorAll<HTMLButtonElement>(".mode-chip").forEach((btn) =>
    btn.addEventListener("click", () => setMode(btn.dataset.mode as ReadingModeId))
  );
  root.querySelector("#toggle-outline")!.addEventListener("click", toggleOutline);

  const layoutSeg = root.querySelector("#layout-seg");
  layoutSeg?.querySelectorAll<HTMLButtonElement>("button").forEach((btn) =>
    btn.addEventListener("click", () => setLayout(btn.dataset.layout as EditorLayout))
  );

  root.querySelector("#ai-toggle")?.addEventListener("click", () => void toggleAi());
  setupMenu("#font-btn", "#font-popover");
  setupMenu("#export-btn", "#export-panel");

  const range = root.querySelector<HTMLInputElement>("#font-range");
  range?.addEventListener("input", () => {
    setFontScale(Number(range.value));
  });

  root.querySelectorAll<HTMLButtonElement>("[data-export]").forEach((btn) =>
    btn.addEventListener("click", () => {
      closeMenus();
      handleExport(btn.dataset.export!);
    })
  );
}

function toggleOutline(): void {
  document.querySelector(".sidebar")?.classList.toggle("collapsed");
}

function openAbout(): void {
  root.querySelector("#about-backdrop")?.classList.add("open");
}

function closeAbout(): void {
  root.querySelector("#about-backdrop")?.classList.remove("open");
}

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

// ---- Update flow ----

let pendingUpdate: UpdateInfo | null = null;
let updating = false;

async function handleCheckUpdate(silent: boolean): Promise<void> {
  try {
    const update = await checkUpdate();
    if (!update) {
      if (!silent) toast("当前已是最新版本");
      return;
    }
    pendingUpdate = update;
    showUpdate(update);
  } catch {
    if (!silent) toast("检查更新失败，请稍后重试");
  }
}

function showUpdate(update: UpdateInfo): void {
  root.querySelector("#update-new")!.textContent = `v${update.version}`;
  root.querySelector("#update-old")!.textContent = `当前 v${update.currentVersion}`;
  (root.querySelector("#update-notes") as HTMLElement).innerHTML = formatNotes(update.notes);
  root.querySelector("#update-status")!.textContent = "";
  setUpdateBusy(false);
  root.querySelector("#update-backdrop")!.classList.add("open");
}

// Render notes as simple paragraphs; strips leading list markers. Text is
// escaped (release bodies are author-controlled, but stay safe).
function formatNotes(notes: string): string {
  const trimmed = notes.trim();
  if (!trimmed) return `<p class="update-card__note-line">本次更新包含优化与修复。</p>`;
  return trimmed
    .split(/\n+/)
    .map((line) => `<p class="update-card__note-line">${escapeText(line.replace(/^[-*]\s*/, ""))}</p>`)
    .join("");
}

function setUpdateBusy(busy: boolean): void {
  updating = busy;
  root.querySelector<HTMLButtonElement>("#update-now")!.disabled = busy;
  root.querySelector<HTMLButtonElement>("#update-later")!.disabled = busy;
}

function closeUpdate(): void {
  if (updating) return;
  root.querySelector("#update-backdrop")?.classList.remove("open");
}

async function runPendingUpdate(): Promise<void> {
  if (!pendingUpdate) return;
  const status = root.querySelector<HTMLElement>("#update-status")!;
  setUpdateBusy(true);
  status.textContent = "正在下载…";
  try {
    await pendingUpdate.install((pct) => {
      status.textContent = pct == null ? "正在下载…" : `正在下载… ${pct}%`;
    });
    status.textContent = "即将重启以完成更新…";
  } catch {
    status.textContent = "更新失败，请稍后重试。";
    setUpdateBusy(false);
  }
}

let toastTimer = 0;
function toast(message: string): void {
  let el = document.getElementById("app-toast");
  if (!el) {
    el = document.createElement("div");
    el.id = "app-toast";
    el.className = "app-toast";
    document.body.appendChild(el);
  }
  el.textContent = message;
  el.classList.add("show");
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => el?.classList.remove("show"), 2600);
}

function setupMenu(triggerSel: string, panelSel: string): void {
  const trigger = root.querySelector<HTMLButtonElement>(triggerSel);
  const panel = root.querySelector<HTMLElement>(panelSel);
  if (!trigger || !panel) return;
  trigger.addEventListener("click", (e) => {
    e.stopPropagation();
    const willOpen = !panel.classList.contains("open");
    closeMenus();
    if (willOpen) panel.classList.add("open");
  });
}

function closeMenus(): void {
  root.querySelectorAll(".menu__panel.open, .popover.open").forEach((p) => p.classList.remove("open"));
}

document.addEventListener("click", () => closeMenus());

// ---- Sidebar ----

function sidebarHtml(): string {
  const a = state.analysis;
  const outline = a.headings.length
    ? `<div class="outline-list">${a.headings
        .map(
          (h) => `
        <button class="outline-row" data-section="${h.sectionId}" data-level="${h.level}">
          <span class="outline-row__tick"></span>
          <span class="outline-row__text">${escapeText(h.title)}</span>
        </button>`
        )
        .join("")}</div>`
    : `<p class="outline-empty">这是一篇连续内容，没有标题层级。</p>`;

  return `
  <aside class="sidebar">
    <div class="sidebar__doc">
      <span class="sidebar__doc-eyebrow">当前文档</span>
      <h1 class="sidebar__doc-title">${escapeText(documentTitle())}</h1>
    </div>
    <h2 class="sidebar__label">目录</h2>
    ${outline}
    <div class="sidebar__divider"></div>
    <h2 class="sidebar__label">统计</h2>
    <div class="stats-card">
      <div class="stat-row"><span>字数</span><span>${a.wordCountText}</span></div>
      <div class="stat-row"><span>节数</span><span>${a.sections.length}</span></div>
      <div class="stat-row"><span>标题</span><span>${a.headings.length}</span></div>
      <div class="stat-row"><span>时长</span><span>${a.readingTimeText}</span></div>
    </div>
  </aside>`;
}

function wireSidebar(): void {
  root.querySelectorAll<HTMLButtonElement>(".outline-row").forEach((row) =>
    row.addEventListener("click", () => scrollToSection(row.dataset.section!))
  );
}

function refreshSidebar(): void {
  const aside = root.querySelector(".sidebar");
  if (!aside) return;
  const collapsed = aside.classList.contains("collapsed");
  aside.outerHTML = sidebarHtml();
  if (collapsed) root.querySelector(".sidebar")!.classList.add("collapsed");
  wireSidebar();
}

function setCurrentSection(sectionId: string): void {
  root.querySelectorAll(".outline-row").forEach((row) => {
    row.classList.toggle("current", (row as HTMLElement).dataset.section === sectionId);
  });
}

function scrollToSection(sectionId: string): void {
  const target = document.getElementById(sectionId);
  const scroller = document.querySelector<HTMLElement>(".reader-scroll");
  if (target && scroller) {
    const top = target.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop - 24;
    scroller.scrollTo({ top, behavior: "smooth" });
  }
}

// ---- Content (reader / editor) ----

function renderContent(): void {
  const content = root.querySelector<HTMLElement>("#content")!;
  detachScrollSpy?.();
  detachScrollSpy = null;

  if (state.workspace === "read") {
    content.innerHTML = readerShellHtml();
    mountReader(content.querySelector(".reader-scroll")!, content.querySelector(".markdown-body")!);
  } else {
    content.innerHTML = editorShellHtml();
    wireEditor(content);
  }
}

function readerShellHtml(): string {
  return `
  <div class="reader-scroll">
    <div class="reader-canvas">
      <div class="reader-card">
        <div class="reader-meta">${readerMetaText()}</div>
        <div class="markdown-body"></div>
      </div>
    </div>
  </div>`;
}

function readerMetaText(): string {
  const a = state.analysis;
  return `${a.readingTimeText} · ${a.sections.length} 节 · ${a.wordCountText}`;
}

async function mountReader(scroller: HTMLElement, body: HTMLElement): Promise<void> {
  await renderReader(body, {
    title: documentTitle(),
    text: state.text,
    baseDir: state.baseDir,
  });
  detachScrollSpy = installScrollSpy(scroller, body, setCurrentSection);
}

function editorShellHtml(): string {
  return `
  <div class="editor">
    <div class="editor__toolbar">
      <button class="fmt-btn" data-prefix="# ">H1</button>
      <button class="fmt-btn" data-prefix="## ">H2</button>
      <button class="fmt-btn" data-prefix="### ">H3</button>
      <span class="divider"></span>
      <button class="fmt-btn" data-wrap="**" data-ph="粗体">B</button>
      <button class="fmt-btn" data-wrap="*" data-ph="斜体">I</button>
      <button class="fmt-btn" data-wrap="~~" data-ph="删除">S</button>
      <span class="divider"></span>
      <button class="fmt-btn" data-wrap="\`" data-ph="code">代码</button>
      <button class="fmt-btn" data-prefix="> ">引用</button>
      <button class="fmt-btn" data-prefix="- ">列表</button>
      <button class="fmt-btn" data-prefix="- [ ] ">任务</button>
      <button class="fmt-btn" data-insert="[标题](https://)">链接</button>
      <button class="fmt-btn" data-insert="\n\n---\n\n">分割</button>
      <span class="editor__count" id="editor-count"></span>
    </div>
    <div class="editor__body ${state.layout}">
      <div class="editor__source"><textarea id="editor-textarea" spellcheck="false"></textarea></div>
      <div class="editor__preview">
        <div class="reader-scroll">
          <div class="reader-canvas">
            <div class="reader-card">
              <div class="reader-meta" id="preview-meta"></div>
              <div class="markdown-body" id="preview-body"></div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>`;
}

function wireEditor(content: HTMLElement): void {
  const textarea = content.querySelector<HTMLTextAreaElement>("#editor-textarea")!;
  textarea.value = state.text;
  updateEditorCount(textarea.value);
  if (state.layout !== "source") refreshPreview();

  textarea.addEventListener("input", () => {
    state.text = textarea.value;
    updateEditorCount(textarea.value);
    scheduleReparse();
  });

  content.querySelectorAll<HTMLButtonElement>(".fmt-btn").forEach((btn) =>
    btn.addEventListener("click", () => {
      applyFormat(textarea, btn);
      state.text = textarea.value;
      updateEditorCount(textarea.value);
      scheduleReparse();
    })
  );
}

function updateEditorCount(text: string): void {
  const nonWs = (text.match(/\S/g) ?? []).length;
  const el = root.querySelector("#editor-count");
  if (el) el.textContent = `${nonWs} 字 · ${text.length} 字符`;
}

function applyFormat(ta: HTMLTextAreaElement, btn: HTMLButtonElement): void {
  const start = ta.selectionStart;
  const end = ta.selectionEnd;
  const value = ta.value;
  const selected = value.slice(start, end);

  if (btn.dataset.prefix) {
    const prefix = btn.dataset.prefix;
    const lineStart = value.lastIndexOf("\n", start - 1) + 1;
    const lineEnd = value.indexOf("\n", end);
    const blockEnd = lineEnd === -1 ? value.length : lineEnd;
    const block = value.slice(lineStart, blockEnd);
    const lines = block.split("\n");
    const allHave = lines.every((l) => l === "" || l.startsWith(prefix));
    const transformed = lines
      .map((l) => (l === "" ? l : allHave ? l.slice(prefix.length) : prefix + l))
      .join("\n");
    ta.setRangeText(transformed, lineStart, blockEnd, "select");
  } else if (btn.dataset.wrap) {
    const wrap = btn.dataset.wrap;
    const body = selected || btn.dataset.ph || "";
    ta.setRangeText(`${wrap}${body}${wrap}`, start, end, "end");
  } else if (btn.dataset.insert) {
    const ins = btn.dataset.insert.replace(/\\n/g, "\n");
    ta.setRangeText(ins, start, end, "end");
  }
  ta.focus();
}

let previewTimer = 0;
function refreshPreview(): void {
  const metaEl = root.querySelector<HTMLElement>("#preview-meta");
  const bodyEl = root.querySelector<HTMLElement>("#preview-body");
  if (!metaEl || !bodyEl) return;
  metaEl.textContent = readerMetaText();
  renderReader(bodyEl, { title: documentTitle(), text: state.text, baseDir: state.baseDir });
}

function scheduleReparse(): void {
  window.clearTimeout(reparseTimer);
  reparseTimer = window.setTimeout(() => {
    state.analysis = analyze(state.text);
    refreshSidebar();
    if (state.workspace === "edit" && state.layout !== "source") {
      window.clearTimeout(previewTimer);
      previewTimer = window.setTimeout(refreshPreview, 60);
    }
  }, 160);
}

// ---- State setters ----

function setMode(mode: ReadingModeId): void {
  if (state.mode === mode) return;
  state.mode = mode;
  document.documentElement.setAttribute("data-mode", mode);
  root.querySelectorAll<HTMLButtonElement>(".mode-chip").forEach((c) =>
    c.setAttribute("aria-pressed", String(c.dataset.mode === mode))
  );
  refreshMenubar();
  if (state.workspace === "edit" && state.layout !== "source") refreshPreview();
}

function setWorkspace(ws: WorkspaceMode): void {
  if (state.workspace === ws) return;
  state.workspace = ws;
  render();
}

function setLayout(layout: EditorLayout): void {
  if (state.layout === layout) return;
  state.layout = layout;
  const body = root.querySelector(".editor__body");
  if (body) {
    body.className = `editor__body ${layout}`;
    root.querySelectorAll<HTMLButtonElement>("#layout-seg button").forEach((b) =>
      b.setAttribute("aria-pressed", String(b.dataset.layout === layout))
    );
    if (layout !== "source") refreshPreview();
  }
  refreshMenubar();
}

// Rebuilds just the menu bar in place so checkmarks / recent list / enabled
// states track the latest mode, layout, and workspace without re-rendering the
// reader (which would re-run Markdown + Mermaid rendering).
function refreshMenubar(): void {
  const bar = root.querySelector(".menubar");
  if (!bar) return;
  const menus = buildMenus(menuContext());
  bar.outerHTML = menuButtonHtml(menus);
  wireMenuButton(root.querySelector<HTMLElement>(".titlebar")!, menus, closeMenus);
}

// ---- Font scale ----

function setFontScale(value: number): void {
  state.fontScale = Math.min(FONT_MAX, Math.max(FONT_MIN, value));
  document.documentElement.style.setProperty("--reader-font-scale", String(state.fontScale));
  const pct = root.querySelector("#font-pct");
  if (pct) pct.textContent = `${Math.round(state.fontScale * 100)}%`;
  const range = root.querySelector<HTMLInputElement>("#font-range");
  if (range) range.value = String(state.fontScale);
}

function adjustFont(action: "in" | "out" | "reset"): void {
  if (action === "reset") setFontScale(1);
  else setFontScale(state.fontScale + (action === "in" ? 0.1 : -0.1));
}

// ---- Document loading ----

function documentTitle(): string {
  return state.displayName || state.analysis.title;
}

function loadDocument(text: string, path: string | null, name: string | null): void {
  const normalized = normalizeMarkdown(text);
  state.text = normalized;
  state.path = path;
  state.baseDir = path ? path.replace(/[\\/][^\\/]*$/, "") : null;
  state.displayName = name;
  state.analysis = analyze(normalized);
  state.hasDocument = true;
  if (path) pushRecent({ path, name: name || state.analysis.title });
  aiPanel?.reset(); // start a fresh AI session for the new doc (keeps old ones)
  render();
}

// Apply an AI-rewritten full Markdown document back into the in-app document.
// Updates the reader/editor + outline in place (the panel is left intact). The
// user saves via 导出 Markdown, consistent with the rest of the app.
function applyRewrite(markdown: string): void {
  state.text = markdown;
  state.analysis = analyze(markdown);
  renderContent();
  refreshSidebar();
  if (state.workspace === "edit" && state.layout !== "source") refreshPreview();
}

async function handleOpen(): Promise<void> {
  const opened = await openMarkdownFile();
  if (!opened) return;
  loadDocument(opened.text, opened.path, opened.name);
}

async function handleOpenRecent(item: RecentItem): Promise<void> {
  const opened = await openMarkdownPath(item.path);
  if (!opened) return; // moved or deleted — leave the current view untouched
  loadDocument(opened.text, opened.path, opened.name);
}

function handleCopy(kind: "copyRich" | "copyPlain" | "copyMarkdown"): void {
  if (kind === "copyRich") {
    copyRichText();
    return;
  }
  if (kind === "copyMarkdown") {
    navigator.clipboard.writeText(state.text).catch(() => {});
    return;
  }
  navigator.clipboard.writeText(`${documentTitle()}\n\n${state.text}`).catch(() => {});
}

// ---- Export ----

function handleExport(kind: string): void {
  if (kind === "copyPlain") {
    navigator.clipboard.writeText(`${documentTitle()}\n\n${state.text}`).catch(() => {});
    return;
  }
  if (kind === "copyRich") {
    copyRichText();
    return;
  }
  openExportSheet(kind as "pdf" | "longImage" | "html" | "markdown");
}

function copyRichText(): void {
  const html = `<h1>${escapeText(documentTitle())}</h1>` +
    document.querySelector(".markdown-body")?.innerHTML;
  try {
    const blob = new Blob([html], { type: "text/html" });
    navigator.clipboard.write([new ClipboardItem({ "text/html": blob })]).catch(() => {});
  } catch {
    navigator.clipboard.writeText(state.text).catch(() => {});
  }
}

// ---- Export sheet ----

const sheetState = {
  format: "pdf" as "pdf" | "longImage" | "html" | "markdown",
  theme: "paper" as ExportThemeId,
  pageSize: "a4" as PageSizeId,
  imageWidth: "standard" as ImageWidthId,
  watermark: false,
};

function exportSheetHtml(): string {
  return `
  <div class="sheet-backdrop" id="sheet-backdrop">
    <div class="sheet" id="sheet">
      <div class="sheet__header">
        <div>
          <h2 class="sheet__headline" id="sheet-headline">导出 PDF</h2>
          <p class="sheet__sub" id="sheet-sub"></p>
        </div>
        <button class="sheet__close" id="sheet-close">&times;</button>
      </div>
      <div class="sheet__body">
        <div>
          <p class="section-label">主题</p>
          <div class="theme-grid" id="theme-grid">
            ${EXPORT_THEMES.map(
              (t) => `
              <button class="theme-card" data-theme="${t.id}">
                <span class="theme-card__swatch" style="background:${t.background}">
                  <span class="theme-card__bar" style="background:${t.accent};width:60%"></span>
                  <span class="theme-card__bar" style="background:rgba(0,0,0,0.25);width:90%"></span>
                  <span class="theme-card__bar" style="background:rgba(0,0,0,0.25);width:70%"></span>
                </span>
                <span class="theme-card__name">${t.title}</span>
              </button>`
            ).join("")}
          </div>
        </div>
        <div id="sheet-format"></div>
      </div>
      <div class="sheet__footer">
        <span class="sheet__status" id="sheet-status">成品会保存到你选择的位置。</span>
        <button class="btn" id="sheet-cancel">取消</button>
        <button class="btn btn--primary" id="sheet-run">导出</button>
      </div>
    </div>
  </div>`;
}

function openExportSheet(format: "pdf" | "longImage" | "html" | "markdown"): void {
  sheetState.format = format;
  const backdrop = root.querySelector<HTMLElement>("#sheet-backdrop")!;
  const headlines: Record<string, string> = {
    pdf: "导出 PDF",
    longImage: "导出长图",
    html: "导出 HTML",
    markdown: "导出 Markdown",
  };
  root.querySelector("#sheet-headline")!.textContent = headlines[format];
  root.querySelector("#sheet-sub")!.textContent = documentTitle();
  setStatus("成品会保存到你选择的位置。", "");
  renderSheetFormat();
  highlightThemeCards();
  backdrop.classList.add("open");

  backdrop.querySelector("#sheet-close")!.addEventListener("click", closeSheet, { once: true });
  backdrop.querySelector("#sheet-cancel")!.addEventListener("click", closeSheet, { once: true });
  backdrop.addEventListener("click", (e) => {
    if (e.target === backdrop) closeSheet();
  });
  root.querySelectorAll<HTMLButtonElement>("#theme-grid .theme-card").forEach((card) =>
    card.addEventListener("click", () => {
      sheetState.theme = card.dataset.theme as ExportThemeId;
      highlightThemeCards();
    })
  );
  const runBtn = root.querySelector<HTMLButtonElement>("#sheet-run")!;
  runBtn.onclick = runExport;
}

function highlightThemeCards(): void {
  root.querySelectorAll<HTMLButtonElement>("#theme-grid .theme-card").forEach((card) =>
    card.classList.toggle("selected", card.dataset.theme === sheetState.theme)
  );
}

function renderSheetFormat(): void {
  const host = root.querySelector<HTMLElement>("#sheet-format")!;
  if (sheetState.format === "pdf") {
    host.innerHTML = `
      <p class="section-label">页面尺寸</p>
      <div class="opt-seg" id="page-seg">
        ${Object.entries(PAGE_SIZES)
          .map(([id, s]) => `<button data-page="${id}" aria-pressed="${sheetState.pageSize === id}">${s.title}</button>`)
          .join("")}
      </div>`;
    host.querySelectorAll<HTMLButtonElement>("#page-seg button").forEach((b) =>
      b.addEventListener("click", () => {
        sheetState.pageSize = b.dataset.page as PageSizeId;
        host.querySelectorAll<HTMLButtonElement>("#page-seg button").forEach((x) =>
          x.setAttribute("aria-pressed", String(x.dataset.page === sheetState.pageSize))
        );
      })
    );
  } else if (sheetState.format === "longImage") {
    host.innerHTML = `
      <p class="section-label">图像宽度</p>
      <div class="opt-seg" id="width-seg">
        ${Object.entries(IMAGE_WIDTHS)
          .map(([id, s]) => `<button data-width="${id}" aria-pressed="${sheetState.imageWidth === id}">${s.title}</button>`)
          .join("")}
      </div>`;
    host.querySelectorAll<HTMLButtonElement>("#width-seg button").forEach((b) =>
      b.addEventListener("click", () => {
        sheetState.imageWidth = b.dataset.width as ImageWidthId;
        host.querySelectorAll<HTMLButtonElement>("#width-seg button").forEach((x) =>
          x.setAttribute("aria-pressed", String(x.dataset.width === sheetState.imageWidth))
        );
      })
    );
  } else if (sheetState.format === "html") {
    host.innerHTML = `<p class="section-label">HTML 选项</p><p class="opt-note">生成内嵌主题样式与中文排版的 HTML 文档；Mermaid 图表通过 CDN 运行时渲染。</p>`;
  } else {
    host.innerHTML = `<p class="section-label">Markdown 源文件</p><p class="opt-note">保留原始 Markdown 文本，可分享给开发者或归档。</p>`;
  }
}

function closeSheet(): void {
  root.querySelector("#sheet-backdrop")!.classList.remove("open");
}

function setStatus(text: string, kind: "ok" | "err" | ""): void {
  const el = root.querySelector<HTMLElement>("#sheet-status");
  if (!el) return;
  el.textContent = text;
  el.className = `sheet__status ${kind}`;
}

async function runExport(): Promise<void> {
  const theme = themeById(sheetState.theme);
  const title = documentTitle();
  const runBtn = root.querySelector<HTMLButtonElement>("#sheet-run")!;
  runBtn.disabled = true;
  setStatus("正在导出…", "");
  try {
    let saved: string | null = null;
    switch (sheetState.format) {
      case "html":
        saved = await exportHtml(title, state.text, theme);
        break;
      case "markdown":
        saved = await exportMarkdown(title, state.text);
        break;
      case "longImage":
        saved = await exportLongImage(title, state.text, theme, IMAGE_WIDTHS[sheetState.imageWidth].w);
        break;
      case "pdf":
        saved = await exportPdf(title, state.text, theme, PAGE_SIZES[sheetState.pageSize]);
        break;
    }
    if (saved) setStatus(`已保存：${saved.split(/[\\/]/).pop()}`, "ok");
    else setStatus("已取消", "");
  } catch (error) {
    setStatus(`导出失败：${String(error)}`, "err");
  } finally {
    runBtn.disabled = false;
  }
}

// ---- helpers ----

function escapeText(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// ---- Keyboard shortcuts ----

document.addEventListener("keydown", (e) => {
  const mod = e.metaKey || e.ctrlKey;
  if (!mod) {
    if (e.key === "Escape") {
      closeAbout();
      closeUpdate();
      closeMenus();
      closeAiSettings();
    }
    return;
  }

  // Window / app-wide shortcuts (work on the library screen too).
  if (e.key.toLowerCase() === "o") {
    e.preventDefault();
    handleOpen();
    return;
  }
  if (e.key.toLowerCase() === "q") {
    e.preventDefault();
    void closeWindow();
    return;
  }

  if (!state.hasDocument) return;

  // Document-only shortcuts.
  if (e.altKey) {
    const mode = READING_MODES.find((m) => m.shortcut === e.key);
    if (mode) {
      e.preventDefault();
      setMode(mode.id);
    }
    return;
  }
  if (e.key.toLowerCase() === "e") {
    e.preventDefault();
    setWorkspace(state.workspace === "edit" ? "read" : "edit");
  } else if (e.key === "=" || e.key === "+") {
    e.preventDefault();
    adjustFont("in");
  } else if (e.key === "-") {
    e.preventDefault();
    adjustFont("out");
  } else if (e.key === "0") {
    e.preventDefault();
    adjustFont("reset");
  }
});

// ---- Boot ----

// Recreate the OS resize border the frameless window gives up.
initResizeHandles();

// Silent update check on launch — stays quiet unless a newer signed release
// is available, in which case the custom update card is shown.
void handleCheckUpdate(true);
void getAiStatus().then((s) => { aiStatus = { hasKey: s.hasKey }; }).catch(() => {});

// Keep the custom maximize / restore glyph in sync with the real window state.
void onMaximizeChange((maximized) => {
  const btn = root.querySelector<HTMLButtonElement>("#win-max");
  if (!btn) return;
  btn.innerHTML = maximized ? WIN_ICON.restore : WIN_ICON.max;
  btn.title = maximized ? "向下还原" : "最大化";
});

const params = new URLSearchParams(location.search);
if (params.has("demo")) {
  loadDocument(DEMO_MARKDOWN, null, "MarkGo 示例");
} else {
  render();
}
