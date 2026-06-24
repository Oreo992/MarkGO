// File open / save bridge. Uses the Tauri dialog + fs plugins when running in
// the native shell, and falls back to the browser File API / download for
// plain-browser dev so the UI stays testable everywhere.

import { isTauri } from "./platform";

export interface OpenedDocument {
  text: string;
  path: string | null;
  name: string;
}

export async function openMarkdownFile(): Promise<OpenedDocument | null> {
  if (isTauri()) return openViaTauri();
  return openViaBrowser();
}

async function openViaTauri(): Promise<OpenedDocument | null> {
  const { open } = await import("@tauri-apps/plugin-dialog");
  const selected = await open({
    multiple: false,
    filters: [{ name: "Markdown", extensions: ["md", "markdown", "mdx", "txt"] }],
  });
  if (typeof selected !== "string") return null;

  const { readTextFile } = await import("@tauri-apps/plugin-fs");
  const text = await readTextFile(selected);
  return { text, path: selected, name: baseName(selected) };
}

/**
 * Reopens a Markdown file by absolute path (used by 最近打开). Tauri-only —
 * returns null in the browser, where there is no filesystem access.
 */
export async function openMarkdownPath(
  path: string
): Promise<OpenedDocument | null> {
  if (!isTauri()) return null;
  try {
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const text = await readTextFile(path);
    return { text, path, name: baseName(path) };
  } catch {
    return null;
  }
}

function openViaBrowser(): Promise<OpenedDocument | null> {
  return new Promise((resolve) => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = ".md,.markdown,.mdx,.txt,text/markdown,text/plain";
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) {
        resolve(null);
        return;
      }
      const reader = new FileReader();
      reader.onload = () =>
        resolve({
          text: String(reader.result ?? ""),
          path: null,
          name: file.name.replace(/\.[^.]+$/, ""),
        });
      reader.onerror = () => resolve(null);
      reader.readAsText(file);
    };
    input.click();
  });
}

export async function saveTextFile(
  suggestedName: string,
  contents: string,
  filters: { name: string; extensions: string[] }[]
): Promise<string | null> {
  if (isTauri()) {
    const { save } = await import("@tauri-apps/plugin-dialog");
    const target = await save({ defaultPath: suggestedName, filters });
    if (!target) return null;
    const { writeTextFile } = await import("@tauri-apps/plugin-fs");
    await writeTextFile(target, contents);
    return target;
  }

  triggerBrowserDownload(suggestedName, new Blob([contents], { type: "text/plain" }));
  return suggestedName;
}

export async function saveBinaryFile(
  suggestedName: string,
  bytes: Uint8Array,
  mime: string,
  filters: { name: string; extensions: string[] }[]
): Promise<string | null> {
  if (isTauri()) {
    const { save } = await import("@tauri-apps/plugin-dialog");
    const target = await save({ defaultPath: suggestedName, filters });
    if (!target) return null;
    const { writeFile } = await import("@tauri-apps/plugin-fs");
    await writeFile(target, bytes);
    return target;
  }

  triggerBrowserDownload(
    suggestedName,
    new Blob([bytes as BlobPart], { type: mime })
  );
  return suggestedName;
}

function triggerBrowserDownload(name: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function baseName(path: string): string {
  const file = path.split(/[\\/]/).pop() ?? path;
  return file.replace(/\.[^.]+$/, "");
}
