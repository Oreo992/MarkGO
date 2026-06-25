import { describe, it, expect } from "vitest";
import {
  MAX_DOC_CHARS,
  clampDoc,
  systemPrompt,
  actionUserMessage,
} from "../../src/ai/prompts";

describe("clampDoc", () => {
  it("keeps short docs intact", () => {
    const r = clampDoc("hello");
    expect(r.text).toBe("hello");
    expect(r.truncated).toBe(false);
  });

  it("truncates docs over the cap and flags it", () => {
    const big = "x".repeat(MAX_DOC_CHARS + 100);
    const r = clampDoc(big);
    expect(r.text.length).toBe(MAX_DOC_CHARS);
    expect(r.truncated).toBe(true);
  });
});

describe("systemPrompt", () => {
  it("grounds on the document and includes its text", () => {
    const { system, truncated } = systemPrompt("MY DOC BODY");
    expect(system).toContain("阅读助手");
    expect(system).toContain("MY DOC BODY");
    expect(truncated).toBe(false);
  });
});

describe("actionUserMessage", () => {
  it("returns the summary instruction", () => {
    expect(actionUserMessage("summary")).toContain("概括");
  });
  it("returns the key-points instruction", () => {
    expect(actionUserMessage("keypoints")).toContain("要点");
  });
});
