// Shared types for the AI reading assistant.

export type ProviderId = "anthropic" | "openai";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface AiStatus {
  provider: ProviderId;
  model: string;
  hasKey: boolean;
}

export interface StreamHandlers {
  onDelta: (text: string) => void;
  /** `truncated` is true when the model stopped at the output-token ceiling. */
  onDone: (truncated: boolean) => void;
  onError: (message: string) => void;
}

export interface StreamHandle {
  cancel: () => void;
}

export type QuickAction = "summary" | "keypoints";
