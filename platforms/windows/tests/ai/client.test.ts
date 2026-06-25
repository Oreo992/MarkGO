import { describe, it, expect } from "vitest";
import { nextRequestId } from "../../src/ai/client";

describe("nextRequestId", () => {
  it("produces unique, prefixed ids", () => {
    const a = nextRequestId();
    const b = nextRequestId();
    expect(a).toMatch(/^ai-\d+$/);
    expect(a).not.toBe(b);
  });
});
