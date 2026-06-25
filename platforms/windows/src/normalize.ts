// Markdown sanitization ported from MarkdownAnalysis.swift (normalize /
// normalizeLine / pipe-table repair). Keeps fenced code blocks untouched and
// repairs the messy Markdown that LLM/clipboard sources often produce.

const ESCAPE_RE = /\\([\\`*_\[\]{}()#+\-.!>|])/g;
const BR_RE = /^<br\s*\/?>$/i;
const LEADING_BR_RE = /^<br\s*\/?>\s*/i;
const HEADING_RE = /^#{1,6}\s+\S/;
const DASH_RUN_RE = /-{3,}/;
const SEPARATOR_CELL_RE = /^:?-{3,}:?$/;

export function normalizeMarkdown(text: string): string {
  const lines = text.split("\n");
  const output: string[] = [];
  let outsideFence: string[] = [];
  let inFence = false;

  const flushOutside = () => {
    if (outsideFence.length === 0) return;
    const normalizedLines = outsideFence.map(normalizeLine);
    output.push(...normalizeWrappedPipeTables(normalizedLines));
    outsideFence = [];
  };

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
      flushOutside();
      output.push(line);
      inFence = !inFence;
      continue;
    }
    if (inFence) {
      output.push(line);
    } else {
      outsideFence.push(line);
    }
  }

  flushOutside();
  return output.join("\n");
}

function normalizeLine(line: string): string {
  let normalized = decodeCommonHTMLEntities(line)
    .replace(ESCAPE_RE, "$1")
    .replace(/\*\*\*\*/g, "**");

  const raw = normalized.trim();
  if (raw === "*") return "";
  if (raw === "\\" || BR_RE.test(raw)) return "";

  if (normalized.endsWith("\\")) {
    normalized = normalized.slice(0, -1);
  }
  normalized = repairOrphanedBulletLeadBold(normalized);

  const cleaned = normalized.trim();
  for (const marker of ["**", "__"]) {
    if (
      cleaned.startsWith(marker) &&
      cleaned.endsWith(marker) &&
      cleaned.length > marker.length * 2
    ) {
      const unwrapped = cleaned.slice(marker.length, -marker.length).trim();
      if (HEADING_RE.test(unwrapped)) return unwrapped;
    }
  }
  return normalized;
}

function repairOrphanedBulletLeadBold(line: string): string {
  const indentMatch = line.match(/^[ \t]*/);
  const indent = indentMatch ? indentMatch[0] : "";
  const rest = line.slice(indent.length);
  const marker = ["- ", "* ", "+ "].find((m) => rest.startsWith(m));
  if (!marker) return line;

  const content = rest.slice(marker.length);
  const colonIdx = (() => {
    const cn = content.indexOf("：");
    const en = content.indexOf(":");
    if (cn === -1) return en;
    if (en === -1) return cn;
    return Math.min(cn, en);
  })();
  if (colonIdx === -1) return line;

  const label = content.slice(0, colonIdx).trim();
  if (!label.endsWith("**") || label.startsWith("**")) return line;

  const repaired = label.slice(0, -2).trim();
  if (!repaired) return line;

  return indent + marker + "**" + repaired + "**" + content.slice(colonIdx);
}

const ENTITIES: Record<string, string> = {
  nbsp: " ",
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
};

function decodeCommonHTMLEntities(line: string): string {
  if (!line.includes("&")) return line;
  let output = "";
  let i = 0;
  while (i < line.length) {
    if (line[i] !== "&") {
      output += line[i];
      i += 1;
      continue;
    }
    const semicolon = line.indexOf(";", i);
    if (semicolon === -1) {
      output += line[i];
      i += 1;
      continue;
    }
    const entity = line.slice(i + 1, semicolon);
    const decoded = decodeEntity(entity);
    if (decoded !== null) {
      output += decoded;
      i = semicolon + 1;
    } else {
      output += line[i];
      i += 1;
    }
  }
  return output;
}

function decodeEntity(entity: string): string | null {
  const lower = entity.toLowerCase();
  if (lower in ENTITIES) return ENTITIES[lower];
  if (lower.startsWith("#x")) {
    const value = parseInt(entity.slice(2), 16);
    if (!Number.isNaN(value)) return safeFromCodePoint(value);
  } else if (entity.startsWith("#")) {
    const value = parseInt(entity.slice(1), 10);
    if (!Number.isNaN(value)) return safeFromCodePoint(value);
  }
  return null;
}

function safeFromCodePoint(value: number): string | null {
  try {
    return String.fromCodePoint(value);
  } catch {
    return null;
  }
}

// ---- Wrapped pipe-table repair ----

function normalizeWrappedPipeTables(lines: string[]): string[] {
  const result: string[] = [];
  let i = 0;
  while (i < lines.length) {
    if (isLikelyPipeTableStart(lines, i)) {
      const block: string[] = [];
      while (i < lines.length) {
        const trimmed = lines[i].trim();
        if (trimmed === "" || isHardBlockBoundary(trimmed)) break;
        block.push(lines[i]);
        i += 1;
      }
      result.push(...normalizePipeTableBlock(block));
    } else {
      result.push(lines[i]);
      i += 1;
    }
  }
  return result;
}

function isLikelyPipeTableStart(lines: string[], index: number): boolean {
  if (!lines[index].includes("|")) return false;
  const lookahead = lines
    .slice(index, Math.min(lines.length, index + 6))
    .map((l) => l.trim())
    .join(" ");
  return lookahead.includes("|") && DASH_RUN_RE.test(lookahead);
}

function isHardBlockBoundary(trimmed: string): boolean {
  return (
    trimmed.startsWith("#") ||
    trimmed.startsWith("```") ||
    trimmed.startsWith("~~~") ||
    trimmed === "*" ||
    trimmed === "---" ||
    trimmed === "***"
  );
}

function pipeCount(value: string): number {
  let count = 0;
  for (const ch of value) if (ch === "|") count += 1;
  return count;
}

function tableCells(row: string): string[] {
  let body = row.trim();
  if (body.startsWith("|")) body = body.slice(1);
  if (body.endsWith("|")) body = body.slice(0, -1);
  return body.split("|").map((c) => c.trim());
}

function isPipeTableSeparator(row: string): boolean {
  const cells = tableCells(row);
  if (cells.length === 0) return false;
  return cells.every((c) => SEPARATOR_CELL_RE.test(c));
}

function logicalPipeRows(block: string[], targetPipeCount: number): string[] {
  const rows: string[] = [];
  let current = "";
  const flush = () => {
    const trimmed = current.trim();
    if (trimmed) rows.push(trimmed);
    current = "";
  };
  for (const line of block) {
    const trimmed = line.trim();
    if (trimmed.startsWith("|") && pipeCount(current) >= targetPipeCount) {
      flush();
      current = trimmed;
    } else if (current === "") {
      current = trimmed;
    } else {
      current += " " + trimmed;
    }
  }
  flush();
  return rows;
}

function normalizePipeTableBlock(block: string[]): string[] {
  const targetPipeCount = Math.max(2, ...block.map(pipeCount));
  const rows = logicalPipeRows(block, targetPipeCount);
  const separatorIndex = rows.findIndex(isPipeTableSeparator);
  if (separatorIndex === -1) return block;

  const columnCount = Math.max(
    2,
    tableCells(rows[Math.max(0, separatorIndex - 1)]).length
  );

  const normalizedRows: string[][] = rows.map((row) => {
    if (isPipeTableSeparator(row)) {
      return new Array(columnCount).fill("---");
    }
    let cells = tableCells(row);
    if (cells.length > columnCount) {
      const head = cells.slice(0, columnCount - 1);
      const tail = cells.slice(columnCount - 1).join(" ");
      cells = [...head, tail];
    } else if (cells.length < columnCount) {
      cells = [...cells, ...new Array(columnCount - cells.length).fill("")];
    }
    return cells;
  });

  const merged = mergeContinuationRows(normalizedRows, separatorIndex);
  return merged.map((cells) => "| " + cells.join(" | ") + " |");
}

function mergeContinuationRows(
  rows: string[][],
  separatorIndex: number
): string[][] {
  const merged: string[][] = [];
  rows.forEach((cells, index) => {
    if (index > separatorIndex && isContinuationRow(cells) && merged.length) {
      const previous = merged.pop()!;
      const continuation = cleanContinuationCell(cells[0]);
      const target = Math.max(0, previous.length - 1);
      previous[target] = [previous[target], continuation]
        .filter((s) => s.trim() !== "")
        .join("<br />");
      merged.push(previous);
    } else {
      merged.push(cells);
    }
  });
  return merged;
}

function isContinuationRow(cells: string[]): boolean {
  if (cells.length === 0) return false;
  const trailingEmpty = cells.slice(1).every((c) => c.trim() === "");
  const first = cells[0].trim();
  return trailingEmpty && (first.startsWith("<br") || first.startsWith("- "));
}

function cleanContinuationCell(cell: string): string {
  return cell.replace(LEADING_BR_RE, "").trim();
}
