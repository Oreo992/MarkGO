// Auto-update via the Tauri updater plugin. This module only talks to the
// native APIs (check / download / install / relaunch); the prompt UI lives in
// main.ts so it can be styled on-brand. No-ops gracefully in a plain browser.

import { isTauri } from "./platform";

export interface UpdateInfo {
  version: string;
  currentVersion: string;
  notes: string;
  /** Downloads + installs the signed package, then relaunches. */
  install: (onProgress?: (pct: number | null) => void) => Promise<void>;
}

/**
 * Returns the available update, or null when up to date / not in the native
 * shell. Throws on network/verification errors so the caller can distinguish a
 * real failure from "no update".
 */
export async function checkUpdate(): Promise<UpdateInfo | null> {
  if (!isTauri()) return null;

  const { check } = await import("@tauri-apps/plugin-updater");
  const update = await check();
  if (!update) return null;

  return {
    version: update.version,
    currentVersion: update.currentVersion,
    notes: update.body ?? "",
    install: async (onProgress) => {
      let total = 0;
      let received = 0;
      await update.downloadAndInstall((event) => {
        if (event.event === "Started") {
          total = event.data.contentLength ?? 0;
          onProgress?.(total ? 0 : null);
        } else if (event.event === "Progress") {
          received += event.data.chunkLength;
          onProgress?.(total ? Math.min(100, Math.round((received / total) * 100)) : null);
        } else if (event.event === "Finished") {
          onProgress?.(100);
        }
      });
      const { relaunch } = await import("@tauri-apps/plugin-process");
      await relaunch();
    },
  };
}
