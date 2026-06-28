#!/usr/bin/env bash
# skills-sync.sh — one command to put EVERY skill where every agent can use it.
#
#  • Claude Code  : install/update each plugin in marketplace.json (local skills +
#                   external mirror plugins). marketplace.json is the single source
#                   of truth, so adding a skill there is enough — nobody forgets it.
#  • Gemini / Codex / Cline : sync this repo's OWN skills (bare SKILL.md dirs) into
#                   each agent. SKILL.md is read natively by Claude Code, Codex CLI
#                   and Gemini CLI, so we just SYMLINK the one source dir into each
#                   agent's skills location — zero content duplication. Cline can't
#                   read SKILL.md, so we generate a thin pointer rule from it.
#
# Usage:
#   bash skills-sync.sh              # Claude plugins + cross-agent sync (auto-detect)
#   bash skills-sync.sh agents       # only the cross-agent sync step
#   bash skills-sync.sh --self-test  # offline checks (bundle filter + cross-agent)
set -euo pipefail

# Swap GITLAB_URL for your internal GitLab mirror of this repo once it exists.
GITLAB_URL="https://gitlab.internal.example.com/mirrors/ai-agent-skills.git"
MARKET="ai-agent-skills"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"

# Print the plugin names to install: every entry EXCEPT the bundle. The bundle is
# a local "./" source listing more than one skill; installing it AND its member
# skills would double-load the same skill. Everything else (the individual local
# skills and the external mirror plugins) gets installed.
plugins_to_install() {
  python3 - "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data.get("plugins", []):
    src = p.get("source")
    skills = p.get("skills", [])
    is_bundle = (src == "./" and isinstance(skills, list) and len(skills) > 1)
    if not is_bundle:
        print(p["name"])
PY
}

# This repo's own skills = direct subdirs that contain a SKILL.md.
own_skill_dirs() {
  local d
  for d in "$SCRIPT_DIR"/*/; do
    [ -f "${d}SKILL.md" ] && basename "$d"
  done
}

# Print "<name>\t<description>" from a SKILL.md frontmatter (for the Cline rule).
skill_meta() {
  python3 - "$1" <<'PY'
import sys
text = open(sys.argv[1], encoding="utf-8").read()
name = desc = ""
if text.startswith("---"):
    end = text.find("\n---", 3)
    fm = text[3:end] if end != -1 else ""
    for line in fm.splitlines():
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip()
        elif line.startswith("description:"):
            desc = line.split(":", 1)[1].strip()
print(f"{name}\t{desc}")
PY
}

# Symlink each own skill into every agent whose home dir exists. Only agents the
# user actually has are touched — we never create config for an agent you don't use.
sync_agents() {
  local home="$HOME" did=0
  local gemini=0 codex=0 cline_dir=""

  # Gemini CLI reads ~/.agents/skills natively (neutral interop dir); also ~/.gemini.
  if [ -d "$home/.gemini" ] || [ -d "$home/.agents" ]; then
    mkdir -p "$home/.agents/skills"; gemini=1; did=1
  fi
  # Codex CLI: ~/.codex/skills
  if [ -d "$home/.codex" ]; then
    mkdir -p "$home/.codex/skills"; codex=1; did=1
  fi
  # Cline: plain .md rules (not SKILL.md). Global rules dir.
  if [ -d "$home/.cline" ]; then
    cline_dir="$home/.cline/rules"
  elif [ -d "$home/Documents/Cline" ]; then
    cline_dir="$home/Documents/Cline/Rules"
  fi
  [ -n "$cline_dir" ] && { mkdir -p "$cline_dir"; did=1; }

  if [ "$did" = 0 ]; then
    echo "→ 跨 agent：未偵測到 Gemini / Codex / Cline，略過（只處理了 Claude）"
    return 0
  fi

  echo "→ 跨 agent：同步自家 skill 到偵測到的 agent"
  local skill src nm ds
  for skill in $(own_skill_dirs); do
    src="$SCRIPT_DIR/$skill"
    [ "$gemini" = 1 ] && ln -sfn "$src" "$home/.agents/skills/$skill"
    [ "$codex" = 1 ]  && ln -sfn "$src" "$home/.codex/skills/$skill"
    if [ -n "$cline_dir" ]; then
      IFS=$'\t' read -r nm ds < <(skill_meta "$src/SKILL.md")
      # pointer rule, not full copy — keeps Cline's always-on context lean.
      printf '# Skill: %s\n\n%s\n\n完整步驟在 `%s/SKILL.md`。要做這件事時，先讀該檔再照做（這是指向 ai-agent-skills 的指標規則，內容以該 SKILL.md 為準）。\n' \
        "${nm:-$skill}" "$ds" "$src" > "$cline_dir/$skill.md"
    fi
    echo "  • $skill"
  done
  [ "$gemini" = 1 ]   && echo "  Gemini → ~/.agents/skills"
  [ "$codex" = 1 ]    && echo "  Codex  → ~/.codex/skills"
  [ -n "$cline_dir" ] && echo "  Cline  → $cline_dir （pointer rule）"
}

self_test() {
  local tmp; tmp="$(mktemp -d)"
  cat > "$tmp/mp.json" <<'JSON'
{"plugins":[
  {"name":"wiki-doc-author","source":"./","skills":["./wiki-doc-author"]},
  {"name":"sop-to-spec","source":"./","skills":["./sop-to-spec"]},
  {"name":"skill-author","source":"./","skills":["./skill-author"]},
  {"name":"ai-agent-skills","source":"./","skills":["./wiki-doc-author","./sop-to-spec","./skill-author"]},
  {"name":"superpowers","source":{"source":"url","url":"x"}},
  {"name":"andrej-karpathy-skills","source":{"source":"url","url":"y"}}
]}
JSON
  local got want
  got="$(plugins_to_install "$tmp/mp.json" | sort | tr '\n' ' ')"
  rm -rf "$tmp"
  want="andrej-karpathy-skills skill-author sop-to-spec superpowers wiki-doc-author "
  if [ "$got" = "$want" ]; then
    echo "self-test OK — bundle skipped, 5 plugins selected"
  else
    echo "self-test FAIL"; echo "  got:  [$got]"; echo "  want: [$want]"; exit 1
  fi
}

self_test_agents() {
  local sb; sb="$(mktemp -d)" fail=0
  mkdir -p "$sb/src/demo-skill"
  printf -- '---\nname: demo-skill\ndescription: 測試用 skill。\n---\n# body\n' > "$sb/src/demo-skill/SKILL.md"

  # case 1: all three agent homes present
  mkdir -p "$sb/h1/.gemini" "$sb/h1/.codex" "$sb/h1/.cline"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ -L "$sb/h1/.agents/skills/demo-skill" ] || { echo "  FAIL: gemini ~/.agents symlink"; fail=1; }
  [ "$(readlink "$sb/h1/.codex/skills/demo-skill" 2>/dev/null)" = "$sb/src/demo-skill" ] \
    || { echo "  FAIL: codex symlink target"; fail=1; }
  grep -q "demo-skill" "$sb/h1/.cline/rules/demo-skill.md" 2>/dev/null \
    || { echo "  FAIL: cline rule missing name"; fail=1; }
  grep -q "$sb/src/demo-skill/SKILL.md" "$sb/h1/.cline/rules/demo-skill.md" 2>/dev/null \
    || { echo "  FAIL: cline rule missing source path"; fail=1; }

  # case 2: no agent homes → nothing created
  mkdir -p "$sb/h2"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h2"; sync_agents >/dev/null )
  [ -e "$sb/h2/.agents" ] && { echo "  FAIL: created agent dir when none detected"; fail=1; }

  # case 3: idempotent — re-run, symlink still valid (not nested)
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ "$(readlink "$sb/h1/.codex/skills/demo-skill" 2>/dev/null)" = "$sb/src/demo-skill" ] \
    || { echo "  FAIL: not idempotent"; fail=1; }

  rm -rf "$sb"
  if [ "$fail" = 0 ]; then
    echo "self-test OK — agents: symlinks + cline rule + skip-absent + idempotent"
  else
    exit 1
  fi
}

case "${1:-}" in
  --self-test) self_test; self_test_agents; exit 0 ;;
  agents)      sync_agents; exit 0 ;;
esac

[ -f "$MARKETPLACE_JSON" ] || { echo "marketplace.json not found at $MARKETPLACE_JSON" >&2; exit 1; }

echo "→ marketplace: add or update ($MARKET)"
claude plugin marketplace add "$GITLAB_URL" 2>/dev/null || claude plugin marketplace update "$MARKET"

echo "→ install/update plugins listed in marketplace.json"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "  • $name"
  # install covers a fresh machine; update brings an already-installed one to latest.
  # If both fail (e.g. an external mirror is unreachable / not set up yet), say so
  # instead of swallowing it silently — otherwise a missing skill looks installed.
  ok=0
  claude plugin install "$name@$MARKET" 2>/dev/null && ok=1
  claude plugin update  "$name@$MARKET" 2>/dev/null && ok=1
  [ "$ok" = 1 ] || echo "    ⚠ $name 未能安裝/更新（mirror 不可達或尚未設定？已跳過）"
done < <(plugins_to_install "$MARKETPLACE_JSON")

sync_agents

echo "✓ done — Claude 端跑 /reload-plugins 或重啟；其他 agent 重開即可"
