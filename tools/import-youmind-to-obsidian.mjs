#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

const vault = "/Users/pintn/Documents/Obsidian Vault";
const targetRoot = join(vault, "40 Resources", "YouMind");
const mode = process.argv.includes("--import") ? "import" : "inventory";
const limitArg = process.argv.find((arg) => arg.startsWith("--limit="));
const limit = limitArg ? Number(limitArg.split("=")[1]) : Infinity;
const downloadAssets = process.argv.includes("--download-assets");

if (!process.env.YOUMIND_API_KEY) {
  console.error("YOUMIND_API_KEY is required in the environment.");
  process.exit(1);
}

function callYouMind(apiName, body = {}) {
  let lastError;
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const out = execFileSync("youmind", ["call", apiName, JSON.stringify(body)], {
        encoding: "utf8",
        maxBuffer: 256 * 1024 * 1024,
        env: process.env,
      });
      return JSON.parse(out);
    } catch (error) {
      lastError = error;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, attempt * 1000);
    }
  }
  throw lastError;
}

function safeName(input, fallback = "Untitled") {
  const name = String(input || fallback)
    .replace(/[\\/:*?"<>|#^[\]]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 110);
  return name || fallback;
}

function yamlString(value) {
  if (value === null || value === undefined || value === "") return "null";
  return JSON.stringify(String(value));
}

function linkFor(file) {
  return file.links?.find((item) => item.rel === "open_in_browser")?.href || "";
}

function cleanContent(content) {
  return String(content || "")
    .replaceAll("<EMPTY_PARAGRAPH>", "")
    .replace(/\n{4,}/g, "\n\n")
    .trim();
}

function frontmatter(board, file) {
  const fileInfo = file.file || {};
  const lines = [
    "---",
    "source: youmind",
    `board: ${yamlString(board.name)}`,
    `board_id: ${yamlString(board.id)}`,
    `youmind_id: ${yamlString(file.id)}`,
    `youmind_type: ${yamlString(file.type)}`,
    `class: ${yamlString(file.$class)}`,
    `visibility: ${yamlString(file.visibility)}`,
    `created: ${yamlString(file.createdAt)}`,
    `updated: ${yamlString(file.updatedAt)}`,
    `parent_group_id: ${yamlString(file.parentGroupId)}`,
    `youmind_url: ${yamlString(linkFor(file))}`,
    `asset_name: ${yamlString(fileInfo.name)}`,
    `asset_mime: ${yamlString(fileInfo.mimeType)}`,
    `asset_size: ${fileInfo.size ?? "null"}`,
    `asset_url: ${yamlString(fileInfo.url || fileInfo.storageUrl)}`,
    "tags:",
    "  - youmind",
    "---",
    "",
  ];
  return lines.join("\n");
}

function markdownFor(board, file, assetPath = "") {
  const title = safeName(file.title, file.type || "Untitled");
  let body = cleanContent(file.content);
  const parts = [frontmatter(board, file), `# ${title}`, ""];

  if (assetPath) {
    parts.push(`Asset: [[${assetPath}]]`, "");
  } else if (file.file?.url || file.file?.storageUrl) {
    parts.push(`Asset URL: ${file.file.url || file.file.storageUrl}`, "");
  }

  if (body) {
    parts.push(body, "");
  } else {
    parts.push("_No extracted text content was returned by YouMind for this item._", "");
  }

  return parts.join("\n");
}

function groupSegments(file, fileById) {
  const segments = [];
  let parentId = file.parentGroupId;
  const seen = new Set();
  while (parentId && !seen.has(parentId)) {
    seen.add(parentId);
    const group = fileById.get(parentId);
    if (!group) break;
    segments.unshift(safeName(group.title, group.id));
    parentId = group.parentGroupId;
  }
  return segments;
}

async function download(url, filePath) {
  if (!url || existsSync(filePath)) return false;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Download failed ${response.status} ${response.statusText}: ${url}`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  mkdirSync(dirname(filePath), { recursive: true });
  writeFileSync(filePath, buffer);
  return true;
}

const boards = callYouMind("listBoards", { withFavorite: true });
const summary = {
  boards: boards.length,
  files: 0,
  byType: {},
  assetCount: 0,
  assetBytes: 0,
  imported: 0,
  downloadedAssets: 0,
  errors: [],
};

mkdirSync(targetRoot, { recursive: true });

let processed = 0;
for (const board of boards) {
  if (processed >= limit) break;
  let files = [];
  try {
    files = callYouMind("listFiles", { boardId: board.id });
  } catch (error) {
    summary.errors.push({ board: board.name, error: error.message });
    continue;
  }

  summary.files += files.length;
  const fileById = new Map(files.map((file) => [file.id, file]));
  const boardDir = join(targetRoot, safeName(board.name, board.id));
  if (mode === "import") mkdirSync(boardDir, { recursive: true });

  for (const file of files) {
    summary.byType[file.type || "unknown"] = (summary.byType[file.type || "unknown"] || 0) + 1;
    if (file.file?.url || file.file?.storageUrl) {
      summary.assetCount += 1;
      summary.assetBytes += Number(file.file?.size || 0);
    }
    if (mode !== "import") continue;
    if (processed >= limit) break;

    let assetRelPath = "";
    if (downloadAssets && (file.file?.url || file.file?.storageUrl)) {
      const extName = safeName(file.file.name || `${file.id}.bin`, `${file.id}.bin`);
      const assetName = `${file.id} - ${extName}`;
      const assetDir = join(vault, "attachments", "YouMind", safeName(board.name, board.id));
      const assetPath = join(assetDir, assetName);
      try {
        const didDownload = await download(file.file.url || file.file.storageUrl, assetPath);
        if (didDownload) summary.downloadedAssets += 1;
        assetRelPath = join("attachments", "YouMind", safeName(board.name, board.id), assetName);
      } catch (error) {
        summary.errors.push({ file: file.title || file.id, error: error.message });
      }
    }

    const title = safeName(file.title, file.type || "Untitled");
    const segments = groupSegments(file, fileById);
    const itemDir =
      file.type === "group"
        ? join(boardDir, ...segments, title)
        : join(boardDir, ...segments);
    mkdirSync(itemDir, { recursive: true });
    const mdName = file.type === "group" ? `_Group - ${file.id}.md` : `${title} - ${file.id}.md`;
    const mdPath = join(itemDir, mdName);
    writeFileSync(mdPath, markdownFor(board, file, assetRelPath), "utf8");
    summary.imported += 1;
    processed += 1;
  }
}

writeFileSync(
  join(targetRoot, "_migration-summary.json"),
  JSON.stringify(summary, null, 2),
  "utf8",
);

console.log(JSON.stringify(summary, null, 2));
