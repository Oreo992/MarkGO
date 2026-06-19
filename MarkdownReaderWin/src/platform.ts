// Platform bridge. The same bundle runs in a plain browser (Vite dev / demo)
// and inside the Tauri WebView2 shell on Windows. We feature-detect Tauri so
// dev mode never crashes when the native APIs are absent.

export function isTauri(): boolean {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

/**
 * Resolves an image `src` from Markdown into something the WebView can load.
 * - Absolute http(s)/data URLs pass through untouched.
 * - In Tauri, local/relative paths are resolved against the document folder
 *   and converted with `convertFileSrc` (requires assetProtocol scope).
 * - In the browser we leave relative paths alone (demo uses remote images).
 */
export async function resolveImageSrc(
  src: string,
  baseDir: string | null
): Promise<string> {
  if (/^(https?:|data:|asset:|blob:)/i.test(src)) return src;
  if (!isTauri()) return src;

  try {
    const { convertFileSrc } = await import("@tauri-apps/api/core");
    const path = await joinPath(baseDir, src);
    return convertFileSrc(path);
  } catch {
    return src;
  }
}

async function joinPath(baseDir: string | null, rel: string): Promise<string> {
  if (!baseDir || isAbsolutePath(rel)) return rel;
  try {
    const { join } = await import("@tauri-apps/api/path");
    return await join(baseDir, rel);
  } catch {
    const sep = baseDir.includes("\\") ? "\\" : "/";
    return `${baseDir.replace(/[\\/]$/, "")}${sep}${rel}`;
  }
}

function isAbsolutePath(p: string): boolean {
  return /^([a-zA-Z]:[\\/]|\\\\|\/)/.test(p);
}
