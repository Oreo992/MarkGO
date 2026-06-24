// Auto-update via the Tauri updater plugin. Checks the GitHub Releases
// `latest.json` (configured in tauri.conf.json → plugins.updater) against the
// embedded public key, then downloads + installs the signed package and
// relaunches. All calls are best-effort and no-op in a plain browser.

import { isTauri } from "./platform";

async function notify(text: string): Promise<void> {
  if (!isTauri()) return;
  try {
    const { message } = await import("@tauri-apps/plugin-dialog");
    await message(text, { title: "MarkGo 更新", kind: "info" });
  } catch {
    /* dialog unavailable — ignore */
  }
}

/**
 * @param silent when true (e.g. the launch check), stay quiet unless an update
 *               is actually available; when false (the 帮助 ▸ 检查更新 menu),
 *               also report "already up to date" / failures.
 */
export async function checkForUpdate(silent: boolean): Promise<void> {
  if (!isTauri()) {
    if (!silent) await notify("自动更新仅在安装版中可用。");
    return;
  }

  try {
    const { check } = await import("@tauri-apps/plugin-updater");
    const update = await check();

    if (!update) {
      if (!silent) await notify("当前已是最新版本。");
      return;
    }

    const { ask } = await import("@tauri-apps/plugin-dialog");
    const notes = update.body ? `\n\n更新说明：\n${update.body}` : "";
    const accepted = await ask(
      `发现新版本 v${update.version}（当前 v${update.currentVersion}）。${notes}\n\n现在下载并安装吗？`,
      { title: "MarkGo 有可用更新", kind: "info", okLabel: "更新", cancelLabel: "稍后" }
    );
    if (!accepted) return;

    await update.downloadAndInstall();

    const { relaunch } = await import("@tauri-apps/plugin-process");
    await relaunch();
  } catch (error) {
    // Until a signed release with latest.json exists, check() will fail — keep
    // that quiet on the silent launch check.
    if (!silent) await notify(`检查更新失败：${String(error)}`);
  }
}
