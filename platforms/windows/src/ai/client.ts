// Bridge between the AI UI and the Rust commands/events. No key ever returns
// to the WebView; we only send one to ai_set_config.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  AiStatus,
  ChatMessage,
  ProviderId,
  StreamHandle,
  StreamHandlers,
} from "./types";

let counter = 0;
export function nextRequestId(): string {
  return `ai-${++counter}`;
}

export async function getAiStatus(): Promise<AiStatus> {
  return invoke<AiStatus>("ai_get_status");
}

export async function saveAiConfig(
  provider: ProviderId,
  model: string,
  baseUrl: string | null,
  maxTokens: number,
  apiKey: string
): Promise<void> {
  // An empty apiKey tells Rust to keep the previously-saved key (so adjusting
  // only the output ceiling doesn't require re-entering it).
  await invoke("ai_set_config", {
    provider,
    model,
    baseUrl: baseUrl || null,
    maxTokens,
    apiKey,
  });
}

interface ChunkPayload { requestId: string; delta: string }
interface DonePayload { requestId: string; truncated?: boolean }
interface ErrorPayload { requestId: string; message: string }

export function streamChat(
  req: { system: string; messages: ChatMessage[]; maxTokens?: number },
  h: StreamHandlers
): StreamHandle {
  const requestId = nextRequestId();
  const unlisten: UnlistenFn[] = [];
  let finished = false;

  const cleanup = () => {
    finished = true;
    unlisten.forEach((u) => u());
    unlisten.length = 0;
  };

  void (async () => {
    unlisten.push(
      await listen<ChunkPayload>("ai://chunk", (e) => {
        if (e.payload.requestId === requestId) h.onDelta(e.payload.delta);
      })
    );
    unlisten.push(
      await listen<DonePayload>("ai://done", (e) => {
        if (e.payload.requestId === requestId) {
          h.onDone(!!e.payload.truncated);
          cleanup();
        }
      })
    );
    unlisten.push(
      await listen<ErrorPayload>("ai://error", (e) => {
        if (e.payload.requestId === requestId) {
          h.onError(e.payload.message);
          cleanup();
        }
      })
    );
    if (finished) {
      unlisten.forEach((u) => u());
      return;
    }
    try {
      await invoke("ai_stream", {
        requestId,
        system: req.system,
        messages: req.messages,
        // Fallback only — the panel always passes the user-configured ceiling.
        // Default high so long replies aren't truncated (was 1024, which cut off
        // anything past a short paragraph).
        maxTokens: req.maxTokens ?? 32768,
      });
    } catch (err) {
      if (!finished) {
        h.onError(String(err));
        cleanup();
      }
    }
  })();

  return {
    cancel: () => {
      if (finished) return;
      void invoke("ai_cancel", { requestId });
      cleanup();
    },
  };
}
