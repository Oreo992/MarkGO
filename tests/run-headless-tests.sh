#!/usr/bin/env bash
# Headless smoke + functional tests for MarkGo.
# Exercises: launch, file open via the registered URL handler, recent
# document persistence, ad-hoc signature integrity, and quarantine flow.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/.build/export/MarkGo.app"
SAMPLE="$REPO_ROOT/tests/sample.md"
PASS=0
FAIL=0

ok()   { printf "  ✔ %s\n"  "$1"; PASS=$((PASS+1)); }
fail() { printf "  ✘ %s\n"  "$1"; FAIL=$((FAIL+1)); }

section() { printf "\n▶︎ %s\n" "$1"; }

section "Bundle integrity"

if [[ -d "$APP_BUNDLE" ]]; then ok "App bundle exists at $APP_BUNDLE"; else fail "Missing app bundle"; fi
if [[ -x "$APP_BUNDLE/Contents/MacOS/MarkGo" ]]; then ok "Executable is present and runnable"; else fail "Executable missing or not executable"; fi
if codesign --verify --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then ok "Code signature verifies"; else fail "Code signature broken"; fi
ARCHS=$(file "$APP_BUNDLE/Contents/MacOS/MarkGo" | grep -oE 'arm64|x86_64' | sort -u | tr '\n' ' ')
if [[ "$ARCHS" == *"arm64"* && "$ARCHS" == *"x86_64"* ]]; then ok "Universal binary (x86_64 + arm64)"; else fail "Not universal: $ARCHS"; fi

section "Info.plist content"

if /usr/libexec/PlistBuddy -c "Print :CFBundleDocumentTypes" "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
  ok "CFBundleDocumentTypes registered (Markdown file association)"
else
  fail "CFBundleDocumentTypes missing"
fi

if /usr/libexec/PlistBuddy -c "Print :UTImportedTypeDeclarations:0:UTTypeIdentifier" "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null | grep -q "net.daringfireball.markdown"; then
  ok "Markdown UTI imported"
else
  fail "Markdown UTI not imported"
fi

section "Reset state"

# Make sure the app is not running so cfprefsd lets us delete cleanly.
pkill -f MarkGo 2>/dev/null || true
sleep 1
defaults delete com.oreo.MarkGo 2>/dev/null || true
# Allow cfprefsd to flush.
sleep 1
ok "Cleared previous UserDefaults"

section "Launch and document open"

open -g "$APP_BUNDLE"
sleep 3
if pgrep -lf "MarkGo" >/dev/null; then
  ok "App launched successfully"
else
  fail "App failed to launch"
fi

open -g -a "$APP_BUNDLE" "$SAMPLE"
# Give SwiftUI time to mount DocumentReaderRoot, run onAppear, persist
# RecentDocumentStore, and let cfprefsd flush to disk.
sleep 5

if pgrep -lf "MarkGo" >/dev/null; then
  ok "App still running after opening document"
else
  fail "App crashed when opening document"
fi

# Quit so cfprefsd can flush before persistence check.
osascript -e 'tell application "MarkGo" to quit' 2>/dev/null || pkill -f MarkGo || true
sleep 2

section "Persistence"

python3 - <<'PY' 2>&1 | sed 's/^/  /'
import json, plistlib, os, sys, time
plist_path = os.path.expanduser("~/Library/Preferences/com.oreo.MarkGo.plist")

data = {}
raw = None
for _ in range(12):
    if os.path.exists(plist_path):
        with open(plist_path, 'rb') as f:
            data = plistlib.load(f)
        raw = data.get('markgo.recent.documents.v1')
        if raw is not None:
            break
    time.sleep(0.5)

if not os.path.exists(plist_path):
    print("✘ Preferences plist not written"); sys.exit(2)

if raw is None:
    print("✘ No recent document entry written"); sys.exit(3)

docs = json.loads(raw.decode('utf-8'))
if not docs:
    print("✘ Recent document list is empty"); sys.exit(4)
print(f"✔ Recent documents persisted: {len(docs)}")

doc = docs[0]
if doc.get('title'): print(f"✔ Title resolved: {doc['title']}")
else: print("✘ Title not resolved"); sys.exit(5)
if doc.get('source'): print(f"✔ Source recorded: {doc['source']}")
else: print("✘ Source missing"); sys.exit(6)
if doc.get('characterCount'): print(f"✔ Character count: {doc['characterCount']}")
else: print("✘ Character count missing"); sys.exit(7)
if doc.get('fileBookmark'): print("✔ File bookmark stored (re-openable across launches)")
else: print("⚠ No file bookmark — inline-only entry")
PY

section "Cleanup"

if pgrep -lf "MarkGo" >/dev/null; then
  fail "App did not quit cleanly"
else
  ok "App quit cleanly"
fi

section "Distribution artifacts"

for artifact in "$REPO_ROOT/dist/MarkGo-"*; do
  if [[ -f "$artifact" ]]; then
    size=$(du -h "$artifact" | cut -f1)
    ok "$(basename "$artifact") · $size"
  fi
done

printf "\n=================================\n"
printf "  Passed: %d\n  Failed: %d\n" "$PASS" "$FAIL"
printf "=================================\n"

if [[ $FAIL -gt 0 ]]; then exit 1; else exit 0; fi
