// Native window bridge for the custom (frameless) title bar. All calls no-op
// gracefully in a plain browser (Vite dev / demo) so the UI stays testable
// outside the Tauri WebView2 shell.

import { isTauri } from "./platform";

// Lazily cached handle to the current Tauri window.
let winHandle: unknown = null;

async function win(): Promise<any | null> {
  if (!isTauri()) return null;
  if (!winHandle) {
    const { getCurrentWindow } = await import("@tauri-apps/api/window");
    winHandle = getCurrentWindow();
  }
  return winHandle;
}

export async function minimizeWindow(): Promise<void> {
  (await win())?.minimize();
}

export async function toggleMaximizeWindow(): Promise<void> {
  const w = await win();
  if (w) await w.toggleMaximize();
}

export async function closeWindow(): Promise<void> {
  (await win())?.close();
}

export async function isWindowMaximized(): Promise<boolean> {
  const w = await win();
  return w ? w.isMaximized() : false;
}

/**
 * Subscribes to maximize/restore changes so the max/restore button can swap
 * its glyph. Returns immediately (and never fires) in the browser.
 */
export async function onMaximizeChange(
  cb: (maximized: boolean) => void
): Promise<void> {
  const w = await win();
  if (!w) return;
  const update = async () => cb(await w.isMaximized());
  await w.onResized(update);
  update();
}

// Eight invisible edge / corner handles that drive native resizing. A frameless
// Tauri window on Windows loses the OS resize border, so we recreate it. Handles
// live on <body> (outside #app) so app re-renders never remove them.
// Top edge / corners are intentionally omitted: they would sit under the menu
// bar and the minimize/maximize/close buttons in the custom title bar. The
// remaining handles cover the common resize gestures.
const RESIZE_HANDLES: { cls: string; dir: string }[] = [
  { cls: "s", dir: "South" },
  { cls: "e", dir: "East" },
  { cls: "w", dir: "West" },
  { cls: "se", dir: "SouthEast" },
  { cls: "sw", dir: "SouthWest" },
];

export function initResizeHandles(): void {
  if (!isTauri()) return;
  if (document.querySelector(".resize-handles")) return;
  const layer = document.createElement("div");
  layer.className = "resize-handles";
  for (const h of RESIZE_HANDLES) {
    const el = document.createElement("div");
    el.className = `resize-handle resize-handle--${h.cls}`;
    el.addEventListener("mousedown", async (e) => {
      if (e.button !== 0) return;
      e.preventDefault();
      const w = await win();
      if (w) await w.startResizeDragging(h.dir);
    });
    layer.appendChild(el);
  }
  document.body.appendChild(layer);
}

/** Opens a URL in the user's default browser (or a new tab in dev). */
export async function openExternalUrl(url: string): Promise<void> {
  if (!isTauri()) {
    window.open(url, "_blank", "noopener");
    return;
  }
  try {
    const { openUrl } = await import("@tauri-apps/plugin-opener");
    await openUrl(url);
  } catch {
    /* opener unavailable — silently ignore */
  }
}
