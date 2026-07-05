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
#  • --constitution (OPT-IN, default off): inject agent-rules/rules/CONSTITUTION.md
#                   into each detected agent at session start via its HOOK mechanism
#                   (content read from the marketplace file at session time → always
#                   fresh, mirroring Claude Code's own SessionStart hook plugin):
#                     Codex    ~/.codex/hooks.json           SessionStart command (stdout → context)
#                     Gemini   ~/.gemini/settings.json        SessionStart hook (JSON additionalContext)
#                     Cline    ~/Documents/Cline/Rules/Hooks/TaskStart  (contextModification;
#                              hooks are macOS/Linux only; a ~/.cline-only layout falls back
#                              to a rules-dir symlink)
#                     OpenCode ~/.config/opencode/opencode.json  instructions[] entries — its
#                              plugin API has no session-start context hook; instructions IS
#                              OpenCode's native always-on mechanism
#                   Off by default because these are personal dotfiles. All merges are
#                   idempotent and keep every unrelated key/file content; old managed
#                   blocks from previous versions are stripped automatically.
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

# Strip the managed marker block older versions of this script embedded in
# GEMINI.md / AGENTS.md — migration so hook + block don't double-inject.
strip_managed_block() {  # $1 = target file
  python3 - "$1" <<'PY'
import os, sys
path = sys.argv[1]
begin = "<!-- agent-rules-constitution:begin (managed by skills-sync.sh --constitution; edits inside are overwritten) -->"
end = "<!-- agent-rules-constitution:end -->"
if not os.path.exists(path):
    sys.exit(0)
c = open(path, encoding="utf-8").read()
if begin not in c or end not in c:
    sys.exit(0)
c = (c.split(begin)[0].rstrip() + "\n" + c.split(end, 1)[1].lstrip()).strip()
with open(path, "w", encoding="utf-8") as f:
    f.write(c + "\n" if c else "")
PY
}

# Idempotently merge one SessionStart-style command hook into a Claude-shaped
# hooks config ({"hooks": {"<Event>": [ {..., "hooks": [{type,command,...}]} ]}}).
# Codex ~/.codex/hooks.json and Gemini ~/.gemini/settings.json share this shape.
# Our entries are recognized by "agent-rules" in the command; old ones are
# replaced, every unrelated key and hook group is preserved.
merge_json_hook() {  # $1 = config file; $2 = event name; $3 = hook-group JSON
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, sys
path, event, entry_json = sys.argv[1], sys.argv[2], sys.argv[3]
entry = json.loads(entry_json)
cfg = {}
if os.path.exists(path):
    try:
        cfg = json.load(open(path, encoding="utf-8"))
    except Exception:
        print("  ⚠ 解析不了 " + path + "（jsonc/註解？）— 請手動加 SessionStart hook（見 README）")
        sys.exit(0)
groups = cfg.setdefault("hooks", {}).setdefault(event, [])
def ours(g):
    return any("agent-rules" in h.get("command", "") for h in g.get("hooks", []))
groups[:] = [g for g in groups if not ours(g)]
groups.append(entry)
os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
os.replace(tmp, path)
PY
}

# Situational-paths listing: the constitution says WHEN to read DECISIONS /
# SAFETY / ANTIPATTERNS, this says WHERE — the same job Claude Code's hook does
# by echoing ${CLAUDE_PLUGIN_ROOT} paths. Files stay read-on-demand by design;
# only their paths are always-on.
situational_paths_body() {
  local rules="$SCRIPT_DIR/agent-rules/rules" n
  echo "## 情境檔路徑（憲法「情境檔」節說何時讀，這裡是去哪讀 — 用讀檔工具開）"
  for n in DECISIONS SAFETY ANTIPATTERNS; do
    [ -f "$rules/$n.md" ] && echo "- $n: $rules/$n.md"
  done
}

# Add instruction file paths to OpenCode's global opencode.json `instructions`
# array — its native multi-file mechanism (merged with AGENTS.md at load time),
# so we never touch the user's AGENTS.md at all. Idempotent; other keys kept.
opencode_add_instructions() {  # $1 = opencode.json path; $2.. = instruction paths
  python3 - "$@" <<'PY'
import json, os, sys
path, paths = sys.argv[1], sys.argv[2:]
cfg = {}
if os.path.exists(path):
    try:
        cfg = json.load(open(path, encoding="utf-8"))
    except Exception:
        print("  ⚠ 解析不了 " + path + "（jsonc/註解？）— 請手動把這些路徑加進 instructions: " + ", ".join(paths))
        sys.exit(0)
arr = cfg.setdefault("instructions", [])
changed = False
for p in paths:
    if p not in arr:
        arr.append(p)
        changed = True
if changed:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
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
  # prune OUR stale entries (skills renamed/removed upstream): only symlinks
  # pointing INTO this repo with a vanished target, and only pointer rules we
  # generated — anything the user made themselves is left alone.
  local d link tgt f p
  for d in "$home/.agents/skills" "$home/.codex/skills"; do
    [ -d "$d" ] || continue
    for link in "$d"/*; do
      [ -L "$link" ] || continue
      tgt="$(readlink "$link")"
      case "$tgt" in
        "$SCRIPT_DIR"/*) [ -e "$tgt" ] || { rm -f "$link"; echo "  − $(basename "$link")（已改名/移除，清掉 stale symlink）"; } ;;
      esac
    done
  done
  if [ -n "$cline_dir" ]; then
    for f in "$cline_dir"/*.md; do
      [ -f "$f" ] || continue
      grep -q "ai-agent-skills 的指標規則" "$f" || continue
      p="$(grep -o "$SCRIPT_DIR/[^\`]*SKILL\.md" "$f" | head -1)"
      [ -n "$p" ] && [ ! -f "$p" ] && { rm -f "$f"; echo "  − $(basename "$f")（stale Cline pointer rule）"; }
    done
  fi

  [ "$gemini" = 1 ]   && echo "  Gemini   → ~/.agents/skills"
  [ "$opencode" = 1 ] && echo "  OpenCode → ~/.agents/skills（原生讀取，與 Gemini 共用）"
  [ "$codex" = 1 ]    && echo "  Codex    → ~/.codex/skills"
  [ -n "$cline_dir" ] && echo "  Cline    → $cline_dir （pointer rule）"

  # Constitution: OPT-IN — these are personal dotfiles, so nothing is written
  # unless --constitution was passed. Injection is done with each agent's HOOK
  # mechanism (session-start command reads the marketplace file → always fresh),
  # mirroring the Claude Code hook plugin. OpenCode has no such hook; its
  # instructions[] array is the native always-on mechanism and stays.
  if [ "$CONSTITUTION" = 1 ]; then
    local const_src="$SCRIPT_DIR/agent-rules/rules/CONSTITUTION.md"
    if [ ! -f "$const_src" ]; then
      echo "  ⚠ --constitution：找不到 $const_src，跳過"
      return 0
    fi
    echo "→ 憲法（--constitution）：用各家 hook 在 session 開頭注入（讀 marketplace 檔，內容自動跟新）"

    # shared situational-paths file, regenerated on every run — read by the
    # hooks together with the constitution itself.
    local paths_file="$home/.agents/agent-rules-situational-paths.md"
    mkdir -p "$home/.agents"
    situational_paths_body > "$paths_file"

    if [ "$codex" = 1 ]; then
      # SessionStart command hook; plain stdout becomes developer context.
      merge_json_hook "$home/.codex/hooks.json" "SessionStart" \
        "{\"matcher\":\"startup|resume\",\"hooks\":[{\"type\":\"command\",\"command\":\"cat '$const_src' '$paths_file'\",\"statusMessage\":\"agent-rules constitution\",\"timeout\":30}]}"
      strip_managed_block "$home/.codex/AGENTS.md"   # migrate off the old embedded snapshot
      echo "  Codex    → ~/.codex/hooks.json SessionStart（自動跟新）"
    fi
    if [ -d "$home/.gemini" ]; then
      # Gemini hooks must answer with JSON (hookSpecificOutput.additionalContext),
      # so generate a tiny stdlib wrapper the hook invokes.
      local ghook="$home/.agents/agent-rules-gemini-hook.py"
      cat > "$ghook" <<PYEOF
#!/usr/bin/env python3
# agent-rules managed - regenerated by skills-sync.sh --constitution
import json, os
paths = ["$const_src", "$paths_file"]
txt = "\n\n".join(open(p, encoding="utf-8").read() for p in paths if os.path.exists(p))
print(json.dumps({"hookSpecificOutput": {"additionalContext": txt}}))
PYEOF
      chmod +x "$ghook"
      merge_json_hook "$home/.gemini/settings.json" "SessionStart" \
        "{\"hooks\":[{\"type\":\"command\",\"command\":\"python3 '$ghook'\",\"name\":\"agent-rules-constitution\",\"timeout\":10000}]}"
      strip_managed_block "$home/.gemini/GEMINI.md"  # migrate off the old @import block
      echo "  Gemini   → ~/.gemini/settings.json SessionStart（自動跟新）"
    fi
    if [ "$opencode" = 1 ]; then
      opencode_add_instructions "$home/.config/opencode/opencode.json" "$const_src" "$paths_file"
      echo "  OpenCode → ~/.config/opencode/opencode.json instructions（原生常駐機制；plugin API 無 session-start 注入 hook）"
    fi
    if [ -n "$cline_dir" ]; then
      if [ -d "$home/Documents/Cline" ]; then
        # documented global hooks dir; hooks are macOS/Linux only.
        local chooks="$home/Documents/Cline/Rules/Hooks" cts
        mkdir -p "$chooks"; cts="$chooks/TaskStart"
        if [ -f "$cts" ] && ! grep -q "agent-rules managed" "$cts"; then
          echo "  ⚠ Cline：$cts 已存在且不是本腳本產生的（Cline 每個 hook 只能一支腳本）— 不覆蓋；請手動在你的 TaskStart 裡 cat '$const_src'"
        else
          cat > "$cts" <<SHEOF
#!/usr/bin/env bash
# agent-rules managed - regenerated by skills-sync.sh --constitution
cat >/dev/null
python3 - "$const_src" "$paths_file" <<'PY'
import json, os, sys
txt = "\n\n".join(open(p, encoding="utf-8").read() for p in sys.argv[1:] if os.path.exists(p))
print(json.dumps({"cancel": False, "contextModification": txt}))
PY
SHEOF
          chmod +x "$cts"
          # migrate off the old rules-dir symlink + paths file (hook replaces both)
          rm -f "$cline_dir/agent-rules-constitution.md" "$cline_dir/agent-rules-situational-paths.md"
          echo "  Cline    → $cts（TaskStart hook，自動跟新）"
        fi
      else
        # ~/.cline-only layout: global hooks dir undocumented there → keep the
        # rules-dir symlink fallback (also auto-fresh, just not a hook).
        ln -sfn "$const_src" "$cline_dir/agent-rules-constitution.md"
        cp "$paths_file" "$cline_dir/agent-rules-situational-paths.md"
        echo "  Cline    → $cline_dir（無 Documents/Cline 佈局，退回 rules symlink，自動跟新）"
      fi
    fi

    # SAFETY guard: PreToolUse-level interception of destructive commands —
    # upgrades SAFETY.md §1 from "the model read the rule" to "the host blocks
    # the call". Claude Code gets this from the agent-rules plugin itself.
    local guard="$SCRIPT_DIR/agent-rules/hooks/guard.py"
    if [ ! -f "$guard" ]; then
      echo "  ⚠ 找不到 $guard，跳過 SAFETY guard"
    else
      echo "→ SAFETY guard（--constitution）：hook 層攔破壞性指令（pattern 清單＝SAFETY.md §1）"
      if [ "$codex" = 1 ]; then
        merge_json_hook "$home/.codex/hooks.json" "PreToolUse" \
          "{\"hooks\":[{\"type\":\"command\",\"command\":\"python3 '$guard' --agent codex\",\"statusMessage\":\"agent-rules guard\",\"timeout\":15}]}"
        echo "  Codex    → ~/.codex/hooks.json PreToolUse（deny）"
      fi
      if [ -d "$home/.gemini" ]; then
        merge_json_hook "$home/.gemini/settings.json" "BeforeTool" \
          "{\"hooks\":[{\"type\":\"command\",\"command\":\"python3 '$guard' --agent gemini\",\"name\":\"agent-rules-guard\",\"timeout\":10000}]}"
        echo "  Gemini   → ~/.gemini/settings.json BeforeTool（deny）"
      fi
      if [ -n "$cline_dir" ] && [ -d "$home/Documents/Cline" ]; then
        local cpre="$home/Documents/Cline/Rules/Hooks/PreToolUse"
        mkdir -p "$home/Documents/Cline/Rules/Hooks"
        if [ -f "$cpre" ] && ! grep -q "agent-rules managed" "$cpre"; then
          echo "  ⚠ Cline：$cpre 已存在且不是本腳本產生的 — 不覆蓋；請在你的 PreToolUse 裡自行呼叫 python3 '$guard' --agent cline"
        else
          cat > "$cpre" <<SHEOF
#!/usr/bin/env bash
# agent-rules managed - regenerated by skills-sync.sh --constitution
exec python3 '$guard' --agent cline
SHEOF
          chmod +x "$cpre"
          echo "  Cline    → $cpre（cancel）"
        fi
      fi
      if [ "$opencode" = 1 ]; then
        mkdir -p "$home/.config/opencode/plugins"
        cat > "$home/.config/opencode/plugins/agent-rules-guard.js" <<'JSEOF'
// agent-rules managed - regenerated by skills-sync.sh --constitution
// Pattern list mirrors agent-rules/hooks/guard.py — change one, change both.
export const AgentRulesGuard = async () => ({
  "tool.execute.before": async (input, output) => {
    if (input.tool !== "bash") return
    const cmd = (output && output.args && output.args.command) || ""
    const patterns = [
      [/\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\b/, "rm -rf"],
      [/\bgit\s+reset\s+--hard\b/, "git reset --hard"],
      [/\bgit\s+push\b[^|;&]*(\s--force(-with-lease)?\b|\s-f\b)/, "git push --force"],
      [/\bgit\s+clean\s+-[a-zA-Z]*f/, "git clean -f"],
      [/\bgit\s+checkout\s+--\s+\./, "git checkout -- ."],
      [/\bgit\s+restore\s+\.(\s|$)/, "git restore ."],
      [/\bdrop\s+(table|database)\b/i, "DROP TABLE/DATABASE"],
      [/\btruncate\s+table\b/i, "TRUNCATE TABLE"],
      [/\bdelete\s+from\b(?![\s\S]*\bwhere\b)/i, "DELETE without WHERE"],
      [/(^|[;&|]\s*)sudo\b/, "sudo"],
      [/\b(chmod|chown)\s+-[a-zA-Z]*R[a-zA-Z]*\s+[^ ]*\s*(\/|~)(\s|$)/i, "recursive chmod/chown on / or ~"],
    ]
    for (const [re, label] of patterns) {
      if (re.test(cmd)) {
        throw new Error("agent-rules SAFETY hook: 命中 " + label + " — SAFETY.md §1 需使用者同回合明確同意；請把完整指令亮給使用者確認，或請使用者自己跑。")
      }
    }
  },
})
JSEOF
        echo "  OpenCode → ~/.config/opencode/plugins/agent-rules-guard.js（throw）"
      fi
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

# Unit-test the guard against the real script with per-agent payloads.
self_test_guard() {
  local g="$SCRIPT_DIR/agent-rules/hooks/guard.py" fail=0 out
  # block cases per agent
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}' | python3 "$g" --agent claude)"
  echo "$out" | grep -q '"permissionDecision": *"ask"' || { echo "  FAIL: claude rm -rf not asked"; fail=1; }
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"git push -f origin main"}}' | python3 "$g" --agent codex)"
  echo "$out" | grep -q '"permissionDecision": *"deny"' || { echo "  FAIL: codex force-push not denied"; fail=1; }
  out="$(echo '{"tool_name":"run_shell_command","tool_input":{"command":"sudo rm x"}}' | python3 "$g" --agent gemini)"
  echo "$out" | grep -q '"decision": *"deny"' || { echo "  FAIL: gemini sudo not denied"; fail=1; }
  out="$(echo '{"toolName":"executeCommand","parameters":{"command":"DROP TABLE users;"}}' | python3 "$g" --agent cline)"
  echo "$out" | grep -q '"cancel": *true' || { echo "  FAIL: cline DROP TABLE not cancelled"; fail=1; }
  # pass cases — safe command, non-shell tool, dangerous text under a content key
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la && git status"}}' | python3 "$g" --agent claude)"
  [ -z "$out" ] || { echo "  FAIL: claude safe command produced output"; fail=1; }
  out="$(echo '{"tool_name":"Write","tool_input":{"command":"rm -rf /"}}' | python3 "$g" --agent claude)"
  [ -z "$out" ] || { echo "  FAIL: claude non-Bash tool should be ignored"; fail=1; }
  out="$(echo '{"toolName":"write_to_file","parameters":{"content":"#!/bin/sh\nrm -rf build/"}}' | python3 "$g" --agent cline)"
  echo "$out" | grep -q '"cancel": *false' || { echo "  FAIL: cline content key false positive"; fail=1; }
  # SQL nuance: DELETE with WHERE passes, without blocks
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM t WHERE id=1\""}}' | python3 "$g" --agent claude)"
  [ -z "$out" ] || { echo "  FAIL: DELETE with WHERE should pass"; fail=1; }
  out="$(echo '{"tool_name":"Bash","tool_input":{"command":"psql -c \"DELETE FROM t\""}}' | python3 "$g" --agent claude)"
  echo "$out" | grep -q '"permissionDecision": *"ask"' || { echo "  FAIL: DELETE without WHERE not asked"; fail=1; }
  # malformed stdin: exit 0, no crash
  echo 'not-json' | python3 "$g" --agent claude >/dev/null 2>&1 || { echo "  FAIL: guard crashed on malformed input"; fail=1; }
  if [ "$fail" = 0 ]; then
    echo "self-test OK — guard: block(rm -rf/force-push/sudo/DROP/DELETE-no-WHERE) + pass(safe/non-shell/content-key/WHERE) + malformed-input"
  else
    exit 1
  fi
}

self_test_agents() {
  local sb; sb="$(mktemp -d)" fail=0
  mkdir -p "$sb/src/demo-skill" "$sb/src/agent-rules/rules" "$sb/src/agent-rules/hooks"
  cp "$SCRIPT_DIR/agent-rules/hooks/guard.py" "$sb/src/agent-rules/hooks/guard.py"
  printf -- '---\nname: demo-skill\ndescription: 測試用 skill。\n---\n# body\n' > "$sb/src/demo-skill/SKILL.md"
  printf -- '# 憲法\nLAW-MARKER-42\n' > "$sb/src/agent-rules/rules/CONSTITUTION.md"
  printf -- '# D\n' > "$sb/src/agent-rules/rules/DECISIONS.md"
  printf -- '# S\n' > "$sb/src/agent-rules/rules/SAFETY.md"
  printf -- '# A\n' > "$sb/src/agent-rules/rules/ANTIPATTERNS.md"

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

  # case 3b: stale prune — our dangling symlink and stale Cline pointer rule are
  # removed; a user's own symlink pointing elsewhere is kept.
  ln -s "$sb/src/renamed-away" "$sb/h1/.codex/skills/renamed-away"
  ln -s "$sb/elsewhere/thing" "$sb/h1/.codex/skills/users-own"
  printf '# Skill: gone\n\ngone.\n\n完整步驟在 `%s/gone-skill/SKILL.md`。（這是指向 ai-agent-skills 的指標規則）\n' "$sb/src" > "$sb/h1/.cline/rules/gone-skill.md"
  printf '# my note\n' > "$sb/h1/.cline/rules/my-note.md"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ -L "$sb/h1/.codex/skills/renamed-away" ] && { echo "  FAIL: stale symlink not pruned"; fail=1; }
  [ -L "$sb/h1/.codex/skills/users-own" ] || { echo "  FAIL: user's own symlink pruned"; fail=1; }
  [ -f "$sb/h1/.cline/rules/gone-skill.md" ] && { echo "  FAIL: stale cline rule not pruned"; fail=1; }
  [ -f "$sb/h1/.cline/rules/my-note.md" ] || { echo "  FAIL: user's own cline rule pruned"; fail=1; }

  # case 4: OpenCode detected via ~/.config/opencode → shares ~/.agents/skills
  mkdir -p "$sb/h3/.config/opencode"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h3"; sync_agents >/dev/null )
  [ -L "$sb/h3/.agents/skills/demo-skill" ] || { echo "  FAIL: opencode ~/.agents symlink"; fail=1; }

  # case 5: --constitution → hooks everywhere: Codex hooks.json, Gemini
  # settings.json hook (+ wrapper actually executed), OpenCode instructions[],
  # Cline without Documents/ falls back to symlink; old managed blocks are
  # stripped (migration); unrelated keys survive; double run stays idempotent.
  mkdir -p "$sb/h4/.codex" "$sb/h4/.gemini" "$sb/h4/.config/opencode" "$sb/h4/.cline"
  OLDBLOCK='<!-- agent-rules-constitution:begin (managed by skills-sync.sh --constitution; edits inside are overwritten) -->
old embedded stuff
<!-- agent-rules-constitution:end -->'
  printf 'my own codex rules\n\n%s\n' "$OLDBLOCK" > "$sb/h4/.codex/AGENTS.md"
  printf 'my gemini notes\n\n%s\n' "$OLDBLOCK" > "$sb/h4/.gemini/GEMINI.md"
  printf '{"theme": "dark"}\n' > "$sb/h4/.gemini/settings.json"
  printf '{"model": "keep-me"}\n' > "$sb/h4/.config/opencode/opencode.json"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; sync_agents >/dev/null )
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; sync_agents >/dev/null )
  # Codex: hook registered once, command points at the constitution; old block gone
  python3 - "$sb/h4/.codex/hooks.json" "$sb/src/agent-rules/rules/CONSTITUTION.md" <<'PY' || { echo "  FAIL: codex hooks.json wrong"; fail=1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
gs = cfg["hooks"]["SessionStart"]
ours = [g for g in gs if any("agent-rules" in h["command"] for h in g["hooks"])]
assert len(ours) == 1, "not exactly one agent-rules hook group"
assert sys.argv[2] in ours[0]["hooks"][0]["command"], "command missing constitution path"
PY
  grep -q "my own codex rules" "$sb/h4/.codex/AGENTS.md" \
    || { echo "  FAIL: codex user content lost during block strip"; fail=1; }
  grep -q "agent-rules-constitution:begin" "$sb/h4/.codex/AGENTS.md" \
    && { echo "  FAIL: codex old managed block not stripped"; fail=1; }
  # Gemini: settings hook idempotent + unrelated key kept; wrapper runs and emits the constitution
  python3 - "$sb/h4/.gemini/settings.json" <<'PY' || { echo "  FAIL: gemini settings.json wrong"; fail=1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
assert cfg["theme"] == "dark", "clobbered theme"
gs = cfg["hooks"]["SessionStart"]
ours = [g for g in gs if any("agent-rules" in h["command"] for h in g["hooks"])]
assert len(ours) == 1, "not exactly one agent-rules hook group"
PY
  out="$(python3 "$sb/h4/.agents/agent-rules-gemini-hook.py")"
  printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "LAW-MARKER-42" in d["hookSpecificOutput"]["additionalContext"]' \
    || { echo "  FAIL: gemini wrapper output wrong"; fail=1; }
  grep -q "my gemini notes" "$sb/h4/.gemini/GEMINI.md" \
    || { echo "  FAIL: gemini user content lost during block strip"; fail=1; }
  grep -q "agent-rules-constitution:begin" "$sb/h4/.gemini/GEMINI.md" \
    && { echo "  FAIL: gemini old managed block not stripped"; fail=1; }
  # OpenCode: instructions[] entries, AGENTS.md untouched, other keys kept, no dupes
  python3 - "$sb/h4/.config/opencode/opencode.json" "$sb/src/agent-rules/rules/CONSTITUTION.md" <<'PY' || { echo "  FAIL: opencode instructions wrong"; fail=1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
assert cfg["model"] == "keep-me", "clobbered other key"
ins = cfg["instructions"]
assert ins.count(sys.argv[2]) == 1, "constitution path missing or duplicated"
assert any(p.endswith("agent-rules-situational-paths.md") for p in ins), "paths file missing"
PY
  [ -e "$sb/h4/.config/opencode/AGENTS.md" ] \
    && { echo "  FAIL: opencode AGENTS.md should be untouched"; fail=1; }
  # Cline (~/.cline only, no Documents/Cline): falls back to rules symlink
  [ "$(readlink "$sb/h4/.cline/rules/agent-rules-constitution.md" 2>/dev/null)" = "$sb/src/agent-rules/rules/CONSTITUTION.md" ] \
    || { echo "  FAIL: cline fallback symlink missing"; fail=1; }
  # guard wiring: codex PreToolUse + gemini BeforeTool registered once, constitution hooks intact
  python3 - "$sb/h4/.codex/hooks.json" <<'PY' || { echo "  FAIL: codex guard hook wrong"; fail=1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
pre = [g for g in cfg["hooks"]["PreToolUse"] if any("agent-rules" in h["command"] for h in g["hooks"])]
assert len(pre) == 1 and "--agent codex" in pre[0]["hooks"][0]["command"]
assert len(cfg["hooks"]["SessionStart"]) >= 1, "constitution hook lost"
PY
  python3 - "$sb/h4/.gemini/settings.json" <<'PY' || { echo "  FAIL: gemini guard hook wrong"; fail=1; }
import json, sys
cfg = json.load(open(sys.argv[1]))
bt = [g for g in cfg["hooks"]["BeforeTool"] if any("agent-rules" in h["command"] for h in g["hooks"])]
assert len(bt) == 1 and "--agent gemini" in bt[0]["hooks"][0]["command"]
assert cfg["theme"] == "dark"
PY
  grep -q "tool.execute.before" "$sb/h4/.config/opencode/plugins/agent-rules-guard.js" 2>/dev/null \
    || { echo "  FAIL: opencode guard plugin missing"; fail=1; }
  # shared paths file generated in ~/.agents
  grep -q "SAFETY: $sb/src/agent-rules/rules/SAFETY.md" "$sb/h4/.agents/agent-rules-situational-paths.md" 2>/dev/null \
    || { echo "  FAIL: shared situational paths file missing"; fail=1; }

  # case 6: Cline with Documents/Cline layout → TaskStart hook script, executable,
  # actually runs and injects; a foreign TaskStart is never clobbered.
  mkdir -p "$sb/h5/Documents/Cline"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h5"; CONSTITUTION=1; sync_agents >/dev/null )
  cts="$sb/h5/Documents/Cline/Rules/Hooks/TaskStart"
  [ -x "$cts" ] || { echo "  FAIL: cline TaskStart hook missing or not executable"; fail=1; }
  echo '{}' | "$cts" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["cancel"] is False and "LAW-MARKER-42" in d["contextModification"]' \
    || { echo "  FAIL: cline TaskStart output wrong"; fail=1; }
  cpre="$sb/h5/Documents/Cline/Rules/Hooks/PreToolUse"
  [ -x "$cpre" ] || { echo "  FAIL: cline PreToolUse guard missing or not executable"; fail=1; }
  echo '{"toolName":"executeCommand","parameters":{"command":"rm -rf /"}}' | "$cpre" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["cancel"] is True' \
    || { echo "  FAIL: cline PreToolUse guard did not cancel rm -rf"; fail=1; }
  mkdir -p "$sb/h6/Documents/Cline/Rules/Hooks"
  printf '#!/bin/sh\necho user-hook\n' > "$sb/h6/Documents/Cline/Rules/Hooks/TaskStart"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h6"; CONSTITUTION=1; sync_agents >/dev/null )
  grep -q "user-hook" "$sb/h6/Documents/Cline/Rules/Hooks/TaskStart" \
    || { echo "  FAIL: foreign cline TaskStart clobbered"; fail=1; }

  rm -rf "$sb"
  if [ "$fail" = 0 ]; then
    echo "self-test OK — agents: symlinks + cline rule + skip-absent + idempotent + opencode + constitution(opt-in/hooks/migration-strip/preserve/idempotent/exec-verified)"
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
  --self-test) self_test; self_test_guard; self_test_agents; exit 0 ;;
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
