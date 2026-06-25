// Multi-session store for the AI assistant. Sessions are a flat, global list
// persisted in localStorage; grounding always uses the currently-open document.

import type { ChatMessage } from "./types";

export interface AiSession {
  id: string;
  title: string;
  docName: string;
  messages: ChatMessage[];
  updatedAt: number;
}

const KEY = "markgo.ai.sessions";
const ACTIVE_KEY = "markgo.ai.activeId";
const MAX_SESSIONS = 50;
const TITLE_MAX = 24;

function newId(): string {
  try {
    return crypto.randomUUID();
  } catch {
    return `s-${Date.now()}-${Math.round(performance.now())}`;
  }
}

function load(): AiSession[] {
  try {
    const raw = localStorage.getItem(KEY);
    const list = raw ? (JSON.parse(raw) as AiSession[]) : [];
    return Array.isArray(list) ? list.filter((s) => s && s.id) : [];
  } catch {
    return [];
  }
}

function persist(list: AiSession[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(list.slice(0, MAX_SESSIONS)));
  } catch {
    /* storage full/unavailable — ignore */
  }
}

export function getSessions(): AiSession[] {
  // Most-recently-updated first.
  return load().sort((a, b) => b.updatedAt - a.updatedAt);
}

export function getActiveId(): string | null {
  return localStorage.getItem(ACTIVE_KEY);
}

export function setActiveId(id: string): void {
  try {
    localStorage.setItem(ACTIVE_KEY, id);
  } catch {
    /* ignore */
  }
}

/** Returns the active session, creating an empty one if none exists. */
export function ensureActive(docName: string): AiSession {
  const list = load();
  const id = getActiveId();
  const found = id ? list.find((s) => s.id === id) : undefined;
  if (found) return found;
  return createSession(docName);
}

export function createSession(docName: string): AiSession {
  const list = load();
  const session: AiSession = {
    id: newId(),
    title: "新会话",
    docName: docName || "",
    messages: [],
    updatedAt: Date.now(),
  };
  list.unshift(session);
  persist(list);
  setActiveId(session.id);
  return session;
}

/** Saves a session's messages, refreshes its timestamp, and derives a title. */
export function saveSession(session: AiSession): void {
  const list = load();
  const idx = list.findIndex((s) => s.id === session.id);
  session.updatedAt = Date.now();
  if (session.title === "新会话" || !session.title) {
    const firstUser = session.messages.find((m) => m.role === "user");
    if (firstUser) {
      session.title =
        firstUser.content.length > TITLE_MAX
          ? firstUser.content.slice(0, TITLE_MAX) + "…"
          : firstUser.content;
    }
  }
  if (idx === -1) list.unshift(session);
  else list[idx] = session;
  persist(list);
}

export function deleteSession(id: string): void {
  const list = load().filter((s) => s.id !== id);
  persist(list);
  if (getActiveId() === id) {
    if (list.length) setActiveId(list[0].id);
    else localStorage.removeItem(ACTIVE_KEY);
  }
}

export function renameSession(id: string, title: string): void {
  const list = load();
  const s = list.find((x) => x.id === id);
  if (!s) return;
  s.title = title.trim() || s.title;
  persist(list);
}
