#!/usr/bin/env bash
# skills-sync.sh — run ONCE per machine; updates arrive automatically afterwards.
#
#  • Claude Code  : install the BUNDLE plugin (this repo's own skills as one plugin)
#                   plus the external mirror plugins, then enable marketplace
#                   auto-update. From then on every Claude Code startup refreshes the
#                   marketplace and updates installed plugins — a merged change OR a
#                   NEW skill (added to the bundle) reaches everyone with zero action.
#  • Gemini / Codex / Cline / OpenCode : sync this repo's OWN skills (bare SKILL.md
#                   dirs) into each agent. SKILL.md is read natively by Claude Code,
#                   Codex CLI, Gemini CLI and OpenCode, so we just SYMLINK the one
#                   source dir into each agent's skills location — zero content
#                   duplication (Gemini and OpenCode both read the neutral
#                   ~/.agents/skills, so they share the same symlinks). Cline can't
#                   read SKILL.md, so we generate a thin pointer rule from it.
#                   Symlinks track marketplace updates automatically; only a brand-new
#                   skill needs a re-run here (to create its symlink).
#  • --constitution (OPT-IN, default off): also write agent-rules/rules/CONSTITUTION.md
#                   into each detected agent's GLOBAL rules file — Codex ~/.codex/AGENTS.md,
#                   Gemini ~/.gemini/GEMINI.md, OpenCode ~/.config/opencode/AGENTS.md
#                   (managed marker block, idempotent, never touches your own content),
#                   Cline <rules dir>/agent-rules-constitution.md (generated copy).
#                   Off by default because these are personal dotfiles. The block is a
#                   snapshot — re-run with --constitution after the constitution changes.
#
# Usage:
#   bash skills-sync.sh                       # Claude plugins + auto-update + cross-agent sync
#   bash skills-sync.sh --constitution        # same + write constitution into agent rules files
#   bash skills-sync.sh agents                # only the cross-agent sync step
#   bash skills-sync.sh agents --constitution # cross-agent sync + constitution
#   bash skills-sync.sh --self-test           # offline checks (plugin plan + auto-update + cross-agent)
set -euo pipefail

# Swap GITLAB_URL for your internal GitLab mirror of this repo once it exists.
GITLAB_URL="https://gitlab.internal.example.com/mirrors/ai-agent-skills.git"
MARKET="ai-agent-skills"
CLAUDE_SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"
CONSTITUTION="${CONSTITUTION:-0}"   # set by --constitution; opt-in, default off

# Print the plugin plan as "INSTALL <name>" / "RETIRE <name>" lines.
# INSTALL: the bundle (source "./" listing >1 skill) + external mirror plugins +
#          any local single-skill plugin NOT covered by the bundle.
# RETIRE:  local single-skill plugins whose skill the bundle already ships —
#          installing both would double-load the skill, and individually installed
#          plugins don't pick up NEW skills; the bundle does.
plugin_plan() {
  python3 - "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
plugins = data.get("plugins", [])
bundle_skills = set()
for p in plugins:
    skills = p.get("skills", [])
    if p.get("source") == "./" and isinstance(skills, list) and len(skills) > 1:
        bundle_skills.update(skills)
for p in plugins:
    skills = p.get("skills", [])
    is_local_single = p.get("source") == "./" and isinstance(skills, list) and len(skills) == 1
    covered = is_local_single and skills[0] in bundle_skills
    print(("RETIRE" if covered else "INSTALL") + " " + p["name"])
PY
}

# Enable marketplace auto-update non-interactively: Claude Code resolves autoUpdate
# from settings extraKnownMarketplaces first (overrides the /plugin UI toggle and
# the third-party default of off), so merge {"autoUpdate": true} into the user
# settings entry. `claude plugin marketplace add` writes that entry too; create it
# (with the git source) when it doesn't exist yet.
enable_auto_update() {
  python3 - "$CLAUDE_SETTINGS_FILE" "$MARKET" "$GITLAB_URL" <<'PY'
import json, os, sys
path, market, url = sys.argv[1], sys.argv[2], sys.argv[3]
settings = {}
if os.path.exists(path):
    settings = json.load(open(path))
entry = settings.setdefault("extraKnownMarketplaces", {}).setdefault(
    market, {"source": {"source": "git", "url": url}}
)
if entry.get("autoUpdate") is True:
    print("already on")
    sys.exit(0)
entry["autoUpdate"] = True
os.makedirs(os.path.dirname(path), exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
print("enabled")
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

# Write the constitution into one agent's global rules file inside a managed
# marker block — idempotent, appends on first run, replaces only the block after;
# everything the user wrote outside the markers is preserved byte-for-byte.
write_constitution_block() {  # $1 = target rules file
  python3 - "$1" "$SCRIPT_DIR/agent-rules/rules/CONSTITUTION.md" <<'PY'
import os, sys
path, src = sys.argv[1], sys.argv[2]
begin = "<!-- agent-rules-constitution:begin (managed by skills-sync.sh --constitution; edits inside are overwritten) -->"
end = "<!-- agent-rules-constitution:end -->"
block = begin + "\n" + open(src, encoding="utf-8").read().rstrip() + "\n" + end
content = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
if begin in content and end in content:
    content = content.split(begin)[0] + block + content.split(end, 1)[1]
elif content.strip():
    content = content.rstrip() + "\n\n" + block + "\n"
else:
    content = block + "\n"
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    f.write(content)
os.replace(tmp, path)
PY
}

# Symlink each own skill into every agent whose home dir exists. Only agents the
# user actually has are touched — we never create config for an agent you don't use.
sync_agents() {
  local home="$HOME" did=0
  local gemini=0 codex=0 opencode=0 agents_dir=0 cline_dir=""

  # Gemini CLI reads ~/.agents/skills natively (neutral interop dir); also ~/.gemini.
  if [ -d "$home/.gemini" ] || [ -d "$home/.agents" ]; then
    gemini=1
  fi
  # OpenCode reads ~/.agents/skills natively too (plus ~/.config/opencode/skills).
  if [ -d "$home/.config/opencode" ]; then
    opencode=1
  fi
  if [ "$gemini" = 1 ] || [ "$opencode" = 1 ]; then
    mkdir -p "$home/.agents/skills"; agents_dir=1; did=1
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
    echo "→ 跨 agent：未偵測到 Gemini / Codex / Cline / OpenCode，略過（只處理了 Claude）"
    return 0
  fi

  echo "→ 跨 agent：同步自家 skill 到偵測到的 agent"
  local skill src nm ds
  for skill in $(own_skill_dirs); do
    src="$SCRIPT_DIR/$skill"
    [ "$agents_dir" = 1 ] && ln -sfn "$src" "$home/.agents/skills/$skill"
    [ "$codex" = 1 ]      && ln -sfn "$src" "$home/.codex/skills/$skill"
    if [ -n "$cline_dir" ]; then
      IFS=$'\t' read -r nm ds < <(skill_meta "$src/SKILL.md")
      # pointer rule, not full copy — keeps Cline's always-on context lean.
      printf '# Skill: %s\n\n%s\n\n完整步驟在 `%s/SKILL.md`。要做這件事時，先讀該檔再照做（這是指向 ai-agent-skills 的指標規則，內容以該 SKILL.md 為準）。\n' \
        "${nm:-$skill}" "$ds" "$src" > "$cline_dir/$skill.md"
    fi
    echo "  • $skill"
  done
  [ "$gemini" = 1 ]   && echo "  Gemini   → ~/.agents/skills"
  [ "$opencode" = 1 ] && echo "  OpenCode → ~/.agents/skills（原生讀取，與 Gemini 共用）"
  [ "$codex" = 1 ]    && echo "  Codex    → ~/.codex/skills"
  [ -n "$cline_dir" ] && echo "  Cline    → $cline_dir （pointer rule）"

  # Constitution: OPT-IN — these are personal dotfiles, so nothing is written
  # unless --constitution was passed. Managed block = re-runnable, user content kept.
  if [ "$CONSTITUTION" = 1 ]; then
    local const_src="$SCRIPT_DIR/agent-rules/rules/CONSTITUTION.md"
    if [ ! -f "$const_src" ]; then
      echo "  ⚠ --constitution：找不到 $const_src，跳過"
      return 0
    fi
    echo "→ 憲法（--constitution）：寫入偵測到的 agent 的全域 rules（managed block；憲法更新後重跑本旗標才會跟著新）"
    if [ "$codex" = 1 ]; then
      write_constitution_block "$home/.codex/AGENTS.md"
      echo "  Codex    → ~/.codex/AGENTS.md"
    fi
    if [ -d "$home/.gemini" ]; then
      write_constitution_block "$home/.gemini/GEMINI.md"
      echo "  Gemini   → ~/.gemini/GEMINI.md"
    fi
    if [ "$opencode" = 1 ]; then
      write_constitution_block "$home/.config/opencode/AGENTS.md"
      echo "  OpenCode → ~/.config/opencode/AGENTS.md"
    fi
    if [ -n "$cline_dir" ]; then
      cp "$const_src" "$cline_dir/agent-rules-constitution.md"
      echo "  Cline    → $cline_dir/agent-rules-constitution.md"
    fi
  fi
}

self_test() {
  local tmp; tmp="$(mktemp -d)"
  cat > "$tmp/mp.json" <<'JSON'
{"plugins":[
  {"name":"wiki-doc-author","source":"./","skills":["./wiki-doc-author"]},
  {"name":"sop-to-spec","source":"./","skills":["./sop-to-spec"]},
  {"name":"skill-author","source":"./","skills":["./skill-author"]},
  {"name":"loner","source":"./","skills":["./loner"]},
  {"name":"ai-agent-skills","source":"./","skills":["./wiki-doc-author","./sop-to-spec","./skill-author"]},
  {"name":"superpowers","source":{"source":"url","url":"x"}},
  {"name":"andrej-karpathy-skills","source":{"source":"url","url":"y"}}
]}
JSON
  local got want
  got="$(plugin_plan "$tmp/mp.json" | sort | tr '\n' ';')"
  want="INSTALL ai-agent-skills;INSTALL andrej-karpathy-skills;INSTALL loner;INSTALL superpowers;RETIRE skill-author;RETIRE sop-to-spec;RETIRE wiki-doc-author;"
  if [ "$got" != "$want" ]; then
    rm -rf "$tmp"
    echo "self-test FAIL (plugin plan)"; echo "  got:  [$got]"; echo "  want: [$want]"; exit 1
  fi

  # auto-update merge: creates the entry, preserves other keys, idempotent.
  local out1 out2 fail=0
  printf '{"model":"keep-me","extraKnownMarketplaces":{"other":{"source":{"source":"github","repo":"x/y"}}}}\n' > "$tmp/settings.json"
  out1="$(CLAUDE_SETTINGS_FILE="$tmp/settings.json" enable_auto_update)"
  out2="$(CLAUDE_SETTINGS_FILE="$tmp/settings.json" enable_auto_update)"
  python3 - "$tmp/settings.json" <<'PY' || fail=1
import json, sys
s = json.load(open(sys.argv[1]))
assert s["model"] == "keep-me", "clobbered unrelated key"
assert s["extraKnownMarketplaces"]["other"]["source"]["repo"] == "x/y", "clobbered other marketplace"
mk = s["extraKnownMarketplaces"]["ai-agent-skills"]
assert mk["autoUpdate"] is True, "autoUpdate not set"
assert mk["source"]["url"].endswith(".git"), "source not created"
PY
  [ "$out1" = "enabled" ] && [ "$out2" = "already on" ] || { echo "  FAIL: auto-update not idempotent (got '$out1'/'$out2')"; fail=1; }
  rm -rf "$tmp"
  if [ "$fail" = 0 ]; then
    echo "self-test OK — plugin plan (bundle installs, covered singles retire) + auto-update merge"
  else
    exit 1
  fi
}

self_test_agents() {
  local sb; sb="$(mktemp -d)" fail=0
  mkdir -p "$sb/src/demo-skill" "$sb/src/agent-rules/rules"
  printf -- '---\nname: demo-skill\ndescription: 測試用 skill。\n---\n# body\n' > "$sb/src/demo-skill/SKILL.md"
  printf -- '# 憲法\nLAW-MARKER-42\n' > "$sb/src/agent-rules/rules/CONSTITUTION.md"

  # case 1: all agent homes present (constitution OFF by default)
  mkdir -p "$sb/h1/.gemini" "$sb/h1/.codex" "$sb/h1/.cline"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ -L "$sb/h1/.agents/skills/demo-skill" ] || { echo "  FAIL: gemini ~/.agents symlink"; fail=1; }
  [ "$(readlink "$sb/h1/.codex/skills/demo-skill" 2>/dev/null)" = "$sb/src/demo-skill" ] \
    || { echo "  FAIL: codex symlink target"; fail=1; }
  grep -q "demo-skill" "$sb/h1/.cline/rules/demo-skill.md" 2>/dev/null \
    || { echo "  FAIL: cline rule missing name"; fail=1; }
  grep -q "$sb/src/demo-skill/SKILL.md" "$sb/h1/.cline/rules/demo-skill.md" 2>/dev/null \
    || { echo "  FAIL: cline rule missing source path"; fail=1; }
  [ -e "$sb/h1/.codex/AGENTS.md" ] && { echo "  FAIL: constitution written without --constitution"; fail=1; }
  [ -e "$sb/h1/.gemini/GEMINI.md" ] && { echo "  FAIL: gemini constitution written without flag"; fail=1; }

  # case 2: no agent homes → nothing created
  mkdir -p "$sb/h2"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h2"; sync_agents >/dev/null )
  [ -e "$sb/h2/.agents" ] && { echo "  FAIL: created agent dir when none detected"; fail=1; }

  # case 3: idempotent — re-run, symlink still valid (not nested)
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ "$(readlink "$sb/h1/.codex/skills/demo-skill" 2>/dev/null)" = "$sb/src/demo-skill" ] \
    || { echo "  FAIL: not idempotent"; fail=1; }

  # case 4: OpenCode detected via ~/.config/opencode → shares ~/.agents/skills
  mkdir -p "$sb/h3/.config/opencode"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h3"; sync_agents >/dev/null )
  [ -L "$sb/h3/.agents/skills/demo-skill" ] || { echo "  FAIL: opencode ~/.agents symlink"; fail=1; }

  # case 5: --constitution → managed block in every detected rules file,
  # user content preserved, idempotent (single block after double run)
  mkdir -p "$sb/h4/.codex" "$sb/h4/.gemini" "$sb/h4/.config/opencode" "$sb/h4/.cline"
  printf 'my own codex rules\n' > "$sb/h4/.codex/AGENTS.md"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; sync_agents >/dev/null )
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; sync_agents >/dev/null )
  grep -q "my own codex rules" "$sb/h4/.codex/AGENTS.md" 2>/dev/null \
    || { echo "  FAIL: constitution clobbered user content"; fail=1; }
  grep -q "LAW-MARKER-42" "$sb/h4/.codex/AGENTS.md" 2>/dev/null \
    || { echo "  FAIL: codex constitution block missing"; fail=1; }
  [ "$(grep -c "agent-rules-constitution:begin" "$sb/h4/.codex/AGENTS.md" 2>/dev/null)" = 1 ] \
    || { echo "  FAIL: constitution block not idempotent"; fail=1; }
  grep -q "LAW-MARKER-42" "$sb/h4/.gemini/GEMINI.md" 2>/dev/null \
    || { echo "  FAIL: gemini constitution missing"; fail=1; }
  grep -q "LAW-MARKER-42" "$sb/h4/.config/opencode/AGENTS.md" 2>/dev/null \
    || { echo "  FAIL: opencode constitution missing"; fail=1; }
  grep -q "LAW-MARKER-42" "$sb/h4/.cline/rules/agent-rules-constitution.md" 2>/dev/null \
    || { echo "  FAIL: cline constitution copy missing"; fail=1; }

  rm -rf "$sb"
  if [ "$fail" = 0 ]; then
    echo "self-test OK — agents: symlinks + cline rule + skip-absent + idempotent + opencode + constitution(opt-in/preserve/idempotent)"
  else
    exit 1
  fi
}

MODE=""
for arg in "$@"; do
  case "$arg" in
    --constitution)      CONSTITUTION=1 ;;
    --self-test|agents)  MODE="$arg" ;;
    *) echo "unknown argument: $arg（可用：agents、--constitution、--self-test）" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  --self-test) self_test; self_test_agents; exit 0 ;;
  agents)      sync_agents; exit 0 ;;
esac

[ -f "$MARKETPLACE_JSON" ] || { echo "marketplace.json not found at $MARKETPLACE_JSON" >&2; exit 1; }

echo "→ marketplace: add or update ($MARKET)"
claude plugin marketplace add "$GITLAB_URL" 2>/dev/null || claude plugin marketplace update "$MARKET"

echo "→ plugins（bundle 取代逐裝；舊逐裝的先移除避免同 skill 雙載）"
while IFS=' ' read -r action name; do
  [ -n "$name" ] || continue
  if [ "$action" = "RETIRE" ]; then
    # migration from the pre-bundle layout; a no-op when it was never installed.
    claude plugin uninstall "$name@$MARKET" 2>/dev/null \
      && echo "  − $name（改由 bundle 提供）"
    continue
  fi
  echo "  • $name"
  # install covers a fresh machine; update brings an already-installed one to latest.
  # If both fail (e.g. an external mirror is unreachable / not set up yet), say so
  # instead of swallowing it silently — otherwise a missing skill looks installed.
  ok=0
  claude plugin install "$name@$MARKET" 2>/dev/null && ok=1
  claude plugin update  "$name@$MARKET" 2>/dev/null && ok=1
  [ "$ok" = 1 ] || echo "    ⚠ $name 未能安裝/更新（mirror 不可達或尚未設定？已跳過）"
done < <(plugin_plan "$MARKETPLACE_JSON")

echo "→ marketplace auto-update：$(enable_auto_update)（之後每次啟動自動更新，不用再跑本腳本）"

sync_agents

echo "✓ done — Claude 端跑 /reload-plugins 或重啟；其他 agent 重開即可"
echo "  之後自家 skills 新增/修改都自動到；重跑本腳本只剩：新機器、同步到新 agent、marketplace 新收錄外部 plugin"
