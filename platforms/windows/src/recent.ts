// Recent documents, persisted in localStorage. Powers the 文件 ▸ 最近打开
// section of the menu bar. Only entries opened from a real file path are kept
// (demo / browser-dropped docs have no reopenable path).

const KEY = "markgo.recent";
const MAX = 8;

export interface RecentItem {
  path: string;
  name: string;
}

export function getRecent(): RecentItem[] {
  try {
    const raw = localStorage.getItem(KEY);
    const list = raw ? (JSON.parse(raw) as RecentItem[]) : [];
    return Array.isArray(list) ? list.filter((r) => r && r.path) : [];
  } catch {
    return [];
  }
}

export function pushRecent(item: RecentItem | null): void {
  if (!item || !item.path) return;
  const list = getRecent().filter((r) => r.path !== item.path);
  list.unshift({ path: item.path, name: item.name || item.path });
  try {
    localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX)));
  } catch {
    /* storage full / unavailable — ignore */
  }
}

export function clearRecent(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* ignore */
  }
}
