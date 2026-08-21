#!/usr/bin/env bash
set -euo pipefail

vault="/Users/pintn/Documents/Obsidian Vault"
plugins_dir="$vault/.obsidian/plugins"
mkdir -p "$plugins_dir"

plugins=(
  "table-editor-obsidian|tgrosinger/advanced-tables-obsidian"
  "url-into-selection|denolehov/obsidian-url-into-selection"
  "obsidian-git|vinzent03/obsidian-git"
  "templater-obsidian|silentvoid13/Templater"
  "dataview|blacksmithgu/obsidian-dataview"
  "obsidian-tasks-plugin|obsidian-tasks-group/obsidian-tasks"
  "omnisearch|scambier/obsidian-omnisearch"
  "cm-chs-patch|aidenlx/cm-chs-patch"
  "obsidian-excalidraw-plugin|zsviczian/obsidian-excalidraw-plugin"
  "smart-connections|brianpetro/obsidian-smart-connections"
  "copilot|logancyang/obsidian-copilot"
)

asset_url() {
  local json="$1"
  local name="$2"
  printf '%s\n' "$json" \
    | awk -v asset="$name" '
      /browser_download_url/ && $0 ~ asset {
        gsub(/[",]/, "", $2);
        print $2;
        exit
      }
    '
}

for entry in "${plugins[@]}"; do
  id="${entry%%|*}"
  repo="${entry##*|}"
  target="$plugins_dir/$id"
  mkdir -p "$target"

  echo "Installing $id from $repo"
  release_json="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest")"

  for asset in manifest.json main.js styles.css; do
    url="$(asset_url "$release_json" "$asset" || true)"
    if [[ -n "$url" ]]; then
      curl -fsSL "$url" -o "$target/$asset"
    elif [[ "$asset" != "styles.css" ]]; then
      echo "Missing required asset $asset for $id" >&2
      exit 1
    fi
  done
done

cat > "$vault/.obsidian/community-plugins.json" <<'JSON'
[
  "table-editor-obsidian",
  "url-into-selection",
  "obsidian-git",
  "templater-obsidian",
  "dataview",
  "obsidian-tasks-plugin",
  "omnisearch",
  "cm-chs-patch",
  "obsidian-excalidraw-plugin",
  "smart-connections",
  "copilot"
]
JSON

echo "Done"
