// Custom menu bar model + renderer for the frameless window. Replaces the
// native Windows application menu. Menus are pure data built from the current
// app state; main.ts supplies the handlers via MenuContext and wires clicks
// back to the node actions through stable data-menu / data-node indices.

import { READING_MODES, type ReadingModeId } from "./modes";
import { getRecent, type RecentItem } from "./recent";

export type EditorLayout = "source" | "split" | "preview";

export type MenuNode =
  | {
      kind: "action";
      label: string;
      hint?: string;
      run: () => void;
      disabled?: boolean;
      checked?: boolean;
    }
  | { kind: "caption"; label: string }
  | { kind: "divider" };

export interface TopMenu {
  id: string;
  label: string;
  nodes: MenuNode[];
}

export interface MenuContext {
  hasDocument: boolean;
  workspace: "read" | "edit";
  mode: ReadingModeId;
  layout: EditorLayout;
  onOpen: () => void;
  onOpenRecent: (item: RecentItem) => void;
  onClearRecent: () => void;
  onLoadDemo: () => void;
  onExport: (kind: string) => void;
  onQuit: () => void;
  onToggleWorkspace: () => void;
  onCopy: (kind: "copyRich" | "copyPlain" | "copyMarkdown") => void;
  onSetMode: (id: ReadingModeId) => void;
  onSetLayout: (id: EditorLayout) => void;
  onToggleOutline: () => void;
  onFont: (action: "in" | "out" | "reset") => void;
  onAbout: () => void;
  onHomepage: () => void;
  onCheckUpdate: () => void;
  onToggleAi: () => void;
  onAiSettings: () => void;
}

const LAYOUTS: { id: EditorLayout; label: string }[] = [
  { id: "source", label: "源码" },
  { id: "split", label: "分屏" },
  { id: "preview", label: "预览" },
];

function recentNodes(ctx: MenuContext): MenuNode[] {
  const recent = getRecent();
  if (recent.length === 0) {
    return [{ kind: "action", label: "暂无最近文件", run: () => {}, disabled: true }];
  }
  const items: MenuNode[] = recent.map((r) => ({
    kind: "action",
    label: r.name,
    run: () => ctx.onOpenRecent(r),
  }));
  items.push({ kind: "divider" });
  items.push({ kind: "action", label: "清除最近记录", run: ctx.onClearRecent });
  return items;
}

export function buildMenus(ctx: MenuContext): TopMenu[] {
  const doc = ctx.hasDocument;

  const fileMenu: TopMenu = {
    id: "file",
    label: "文件",
    nodes: [
      { kind: "action", label: "打开…", hint: "Ctrl+O", run: ctx.onOpen },
      { kind: "action", label: "打开示例文档", run: ctx.onLoadDemo },
      { kind: "caption", label: "最近打开" },
      ...recentNodes(ctx),
      { kind: "divider" },
      { kind: "action", label: "导出 PDF", run: () => ctx.onExport("pdf"), disabled: !doc },
      { kind: "action", label: "导出长图", run: () => ctx.onExport("longImage"), disabled: !doc },
      { kind: "action", label: "导出 HTML", run: () => ctx.onExport("html"), disabled: !doc },
      { kind: "action", label: "导出 Markdown", run: () => ctx.onExport("markdown"), disabled: !doc },
      { kind: "divider" },
      { kind: "action", label: "退出", hint: "Ctrl+Q", run: ctx.onQuit },
    ],
  };

  const editMenu: TopMenu = {
    id: "edit",
    label: "编辑",
    nodes: [
      {
        kind: "action",
        label: ctx.workspace === "edit" ? "切换到阅读" : "切换到编辑",
        hint: "Ctrl+E",
        run: ctx.onToggleWorkspace,
        disabled: !doc,
      },
      { kind: "divider" },
      { kind: "action", label: "复制富文本", run: () => ctx.onCopy("copyRich"), disabled: !doc },
      { kind: "action", label: "复制纯文本", run: () => ctx.onCopy("copyPlain"), disabled: !doc },
      { kind: "action", label: "复制 Markdown 全文", run: () => ctx.onCopy("copyMarkdown"), disabled: !doc },
    ],
  };

  const viewMenu: TopMenu = {
    id: "view",
    label: "视图",
    nodes: [
      { kind: "caption", label: "阅读模式" },
      ...READING_MODES.map<MenuNode>((m) => ({
        kind: "action",
        label: `${m.title} · ${m.subtitle}`,
        checked: ctx.mode === m.id,
        run: () => ctx.onSetMode(m.id),
        disabled: !doc,
      })),
      { kind: "divider" },
      { kind: "caption", label: "编辑布局" },
      ...LAYOUTS.map<MenuNode>((l) => ({
        kind: "action",
        label: l.label,
        checked: ctx.layout === l.id,
        run: () => ctx.onSetLayout(l.id),
        disabled: !doc || ctx.workspace !== "edit",
      })),
      { kind: "divider" },
      { kind: "action", label: "显示 / 隐藏目录", run: ctx.onToggleOutline, disabled: !doc },
      { kind: "action", label: "放大字号", hint: "Ctrl+=", run: () => ctx.onFont("in"), disabled: !doc },
      { kind: "action", label: "缩小字号", hint: "Ctrl+-", run: () => ctx.onFont("out"), disabled: !doc },
      { kind: "action", label: "重置字号", hint: "Ctrl+0", run: () => ctx.onFont("reset"), disabled: !doc },
      { kind: "divider" },
      { kind: "action", label: "AI 助手", run: ctx.onToggleAi, disabled: !doc },
      { kind: "action", label: "AI 设置…", run: ctx.onAiSettings },
    ],
  };

  const helpMenu: TopMenu = {
    id: "help",
    label: "帮助",
    nodes: [
      { kind: "action", label: "检查更新…", run: ctx.onCheckUpdate },
      { kind: "divider" },
      { kind: "action", label: "关于 MarkGo", run: ctx.onAbout },
      { kind: "action", label: "查看示例文档", run: ctx.onLoadDemo },
      { kind: "action", label: "项目主页", run: ctx.onHomepage },
    ],
  };

  return [fileMenu, editMenu, viewMenu, helpMenu];
}

// ---- Rendering ----

// Hamburger glyph for the single condensed menu button.
const MENU_GLYPH = `<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>`;

function nodeHtml(node: MenuNode, mi: number, ni: number): string {
  if (node.kind === "divider") return `<div class="menu__divider"></div>`;
  if (node.kind === "caption") return `<div class="menu__caption">${node.label}</div>`;
  const hint = node.hint ? `<span class="menu__hint">${node.hint}</span>` : "";
  return `
    <button class="menu__item" data-mi="${mi}" data-ni="${ni}" ${node.disabled ? "disabled" : ""}>
      <span class="menu__check">${node.checked ? "✓" : ""}</span>
      <span class="menu__label">${escapeMenu(node.label)}</span>
      ${hint}
    </button>`;
}

// Single condensed menu: one ≡ button opening one dropdown, with the former
// top-level menus (文件 / 编辑 / 视图 / 帮助) becoming labelled sections.
export function menuButtonHtml(menus: TopMenu[]): string {
  const sections = menus
    .map(
      (m, mi) =>
        `<div class="menu__caption menu__caption--section">${m.label}</div>` +
        m.nodes.map((n, ni) => nodeHtml(n, mi, ni)).join("")
    )
    .join(`<div class="menu__divider"></div>`);

  return `
  <div class="menubar">
    <div class="menubar__group menu">
      <button class="menubar__btn menubar__btn--icon" type="button" title="菜单" aria-label="菜单">${MENU_GLYPH}</button>
      <div class="menu__panel menu__panel--bar menu__panel--single">
        ${sections}
      </div>
    </div>
  </div>`;
}

/**
 * Wires the condensed menu button: toggle on click, and every action item runs
 * its node handler (resolved via data-mi / data-ni). `closeAll` lets the host
 * close any open menu/popover before running an action.
 */
export function wireMenuButton(
  scope: HTMLElement,
  menus: TopMenu[],
  closeAll: () => void
): void {
  const group = scope.querySelector<HTMLElement>(".menubar__group");
  if (!group) return;
  const btn = group.querySelector<HTMLButtonElement>(".menubar__btn")!;
  const panel = group.querySelector<HTMLElement>(".menu__panel")!;

  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    const willOpen = !panel.classList.contains("open");
    closeAll();
    if (willOpen) panel.classList.add("open");
  });

  panel.querySelectorAll<HTMLButtonElement>(".menu__item").forEach((item) => {
    const mi = Number(item.dataset.mi);
    const ni = Number(item.dataset.ni);
    const node = menus[mi]?.nodes[ni];
    if (!node || node.kind !== "action" || node.disabled) return;
    item.addEventListener("click", (e) => {
      e.stopPropagation();
      closeAll();
      node.run();
    });
  });
}

function escapeMenu(value: string): string {
  return value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}
