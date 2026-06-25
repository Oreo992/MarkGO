// Structural Markdown analysis ported from MarkdownAnalysis.swift. Drives the
// outline, section ids, reading time and stats. Splits on ATX headings while
// honoring fenced code blocks so headings inside code are not promoted.

import { normalizeMarkdown } from "./normalize";

export interface MarkdownHeading {
  id: string;
  sectionId: string;
  level: number;
  title: string;
  displayNumber: number;
}

export interface MarkdownSection {
  id: string;
  heading: MarkdownHeading | null;
  markdown: string;
}

export interface MarkdownAnalysis {
  text: string;
  headings: MarkdownHeading[];
  sections: MarkdownSection[];
  characterCount: number;
  title: string;
  readingTimeText: string;
  wordCountText: string;
}

export function analyze(rawText: string): MarkdownAnalysis {
  const text = normalizeMarkdown(rawText);
  const sections = parseSections(text);
  const headings = sections
    .map((s) => s.heading)
    .filter((h): h is MarkdownHeading => h !== null);

  let characterCount = 0;
  for (const ch of text) {
    if (!/\s/.test(ch)) characterCount += 1;
  }

  const title = headings[0]?.title || "未命名 Markdown";
  const readingTimeText = `${Math.max(1, Math.floor(characterCount / 450))} 分钟`;
  const wordCountText = `${characterCount} 字`;

  return {
    text,
    headings,
    sections,
    characterCount,
    title,
    readingTimeText,
    wordCountText,
  };
}

function parseHeading(line: string, sectionIndex: number): MarkdownHeading | null {
  const raw = line.trim();
  let count = 0;
  while (count < raw.length && raw[count] === "#") count += 1;
  if (count < 1 || count > 6) return null;
  if (raw[count] !== " ") return null;
  const title = raw.slice(count).trim();
  if (!title) return null;
  const id = `section-${sectionIndex}`;
  return {
    id,
    sectionId: id,
    level: count,
    title,
    displayNumber: sectionIndex + 1,
  };
}

function canonical(markdown: string): string {
  return markdown.split(/\s+/).filter(Boolean).join(" ");
}

function duplicateKey(h: MarkdownHeading): string {
  return `${h.level}|${h.title.trim()}`;
}

function parseSections(text: string): MarkdownSection[] {
  const lines = normalizeMarkdown(text).split("\n");
  const sections: MarkdownSection[] = [];
  let currentLines: string[] = [];
  let currentHeading: MarkdownHeading | null = null;
  let sectionIndex = 0;
  let inFence = false;
  const seenHeadingKeys = new Set<string>();

  const flush = () => {
    const markdown = currentLines.join("\n").trim();
    if (!markdown) return;
    const last = sections[sections.length - 1];
    if (last && canonical(last.markdown) === canonical(markdown)) return;
    if (currentHeading) {
      const key = duplicateKey(currentHeading);
      if (seenHeadingKeys.has(key)) return;
      seenHeadingKeys.add(key);
    }
    const id = currentHeading?.sectionId ?? `section-${sectionIndex}`;
    sections.push({ id, heading: currentHeading, markdown });
    sectionIndex += 1;
  };

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
      inFence = !inFence;
    }
    if (!inFence && parseHeading(line, 0) !== null) {
      flush();
      const heading = parseHeading(line, sectionIndex);
      if (!heading) {
        currentLines.push(line);
        continue;
      }
      currentLines = [line];
      currentHeading = heading;
    } else {
      currentLines.push(line);
    }
  }

  flush();
  if (sections.length === 0) {
    return [{ id: "section-0", heading: null, markdown: text }];
  }
  return sections;
}
