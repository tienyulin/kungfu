#!/usr/bin/env bash
# skills-sync.sh — run ONCE per machine; updates arrive automatically afterwards.
#
#  • Claude Code  : install the BUNDLE plugin (this repo's own skills as one plugin)
#                   plus the external mirror plugins, then enable marketplace
#                   auto-update. From then on every Claude Code startup refreshes the
#                   marketplace and updates installed plugins — a merged change OR a
#                   NEW skill (added to the bundle) reaches everyone with zero action.
#  • Gemini / Codex / Cline / OpenCode : this repo IS a superpowers-style adapter
#                   repo — own skills live in skills/, and per-agent adapters
#                   (gemini-extension.json, .codex-plugin/, .opencode/) sit at the
#                   root. Install kungfu-self into each agent via its native
#                   mechanism: Gemini `extensions link <repo>`, Codex `plugin
#                   marketplace add <repo>` + `plugin add kungfu@kungfu-dev`.
#                   OpenCode/Cline (no local native install) get skills/*/ dropped
#                   into the dir they read natively (~/.agents/skills, ~/.cline/skills).
#                   See wire_own_skills. Only a brand-new skill needs a re-run.
#  • --constitution (OPT-IN, default off): inject agent-rules/rules/CONSTITUTION.md
#                   into each detected agent at session start via its HOOK mechanism
#                   (content read from the marketplace file at session time → always
#                   fresh, mirroring Claude Code's own SessionStart hook plugin):
#                     Codex    ~/.codex/hooks.json           SessionStart command (stdout → context)
#                     Gemini   ~/.gemini/settings.json        SessionStart hook (JSON additionalContext)
#                     Cline    ~/Documents/Cline/Hooks/TaskStart  (contextModification;
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
#   bash skills-sync.sh --constitution        # same + write constitution/guard into agent configs
#   bash skills-sync.sh agents                # only the cross-agent sync step
#   bash skills-sync.sh agents --constitution # cross-agent sync + constitution
#   bash skills-sync.sh agents --cline         # force-provision Cline even if not detected yet
#                                              #   (devcontainer postCreate before the extension installs)
#   bash skills-sync.sh --no-external          # skip installing external-skills.json repos into other agents
#   bash skills-sync.sh --no-constitution     # turn the sticky constitution off (remove marker)
#   bash skills-sync.sh --self-test           # offline checks — delegates to skills-sync.test.sh
#
# The self-tests live in skills-sync.test.sh (it sources this file for the
# internal functions). This file is safe to source: the CLI dispatch at the
# bottom is guarded so only a direct run executes it.
#
# STICKY: --constitution once leaves a marker (~/.agents/.constitution-on); after
# that EVERY plain run keeps the constitution/guard hooks fresh, so you can't
# forget the flag on a re-run. --no-constitution removes the marker and stops.
set -euo pipefail

# Git URL of this marketplace repo. Default is the public GitHub repo; to point
# at an internal mirror, run localize.sh (config-driven) instead of editing here.
MARKETPLACE_URL="https://github.com/tienyulin/kungfu.git"
MARKET="kungfu"
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
  python3 - "$CLAUDE_SETTINGS_FILE" "$MARKET" "$MARKETPLACE_URL" <<'PY'
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
  for d in "$SCRIPT_DIR"/skills/*/; do
    [ -f "${d}SKILL.md" ] && basename "$d"
  done
}

# Does the workspace ASK for the Cline extension? In a devcontainer the extension
# is installed after the container starts, so at postCreate time it isn't on disk
# yet — but the config that requested it (devcontainer.json / extensions.json /
# *.code-workspace) already is. Grepping the id closes the "container up, extension
# still installing" race without needing a manual flag. Searches $PWD (the
# workspace root when the sync runs) — CLINE_EXT_ID is the marketplace identifier.
CLINE_EXT_ID="saoudrizwan.claude-dev"
cline_declared() {
  local f
  for f in "$PWD/.devcontainer/devcontainer.json" "$PWD/.devcontainer.json" \
           "$PWD"/.devcontainer/*/devcontainer.json \
           "$PWD/.vscode/extensions.json" "$PWD"/*.code-workspace; do
    [ -f "$f" ] && grep -q "$CLINE_EXT_ID" "$f" 2>/dev/null && return 0
  done
  return 1
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
# For a path under $HOME, return a form that RE-EXPANDS at the consumer's
# runtime, so a hook works unchanged on the host AND inside a container that
# mounts the same dir at its own HOME. Paths outside $HOME are returned as-is
# (a clone under /opt or a submodule workspace can't be made portable).
#   mode sh    -> literal "$HOME/..."  (a shell expands it; place inside "..")
#   mode tilde -> "~/..."              (python expanduser, or an LLM's file tool)
homeref() {  # <abs path> [sh|tilde]
  local p="$1" mode="${2:-sh}" rel
  case "$p" in
    "$HOME"/*)
      rel="${p#"$HOME"/}"
      if [ "$mode" = "tilde" ]; then printf '~/%s' "$rel"; else printf '$HOME/%s' "$rel"; fi
      ;;
    *) printf '%s' "$p" ;;
  esac
}

situational_paths_body() {
  local rules="$SCRIPT_DIR/agent-rules/rules" n
  echo "## 情境檔路徑（憲法「情境檔」節說何時讀，這裡是去哪讀 — 用讀檔工具開）"
  echo "（路徑以 ~ 開頭者代表你的家目錄；用讀檔工具開時自行展開。）"
  for n in DECISIONS SAFETY ANTIPATTERNS; do
    [ -f "$rules/$n.md" ] && echo "- $n: $(homeref "$rules/$n.md" tilde)"
  done
  # judgment bridge（可選）：通用判斷增量＋路由表。repo 不在（隊友沒裝）就靜默跳過。
  # 內容在 --constitution 執行時解析嵌入；INDEX.md 更新後重跑一次 --constitution。
  local j="${JUDGMENT_DIR:-$SCRIPT_DIR/agent-rules/judgment}"
  if [ -f "$j/INDEX.md" ]; then
    echo
    sed "s|@JUDGMENT@|$(homeref "$j" tilde)|g" "$j/INDEX.md"
  fi
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
# Constitution injection (SessionStart/TaskStart hooks) for the detected agents.
# Returns 1 (caller then skips the guard) if the constitution file is missing.
wire_constitution() {
  local home="$1" codex="$2" opencode="$3" cline_present="$4" cline_base="$5" cline_dir="$6"
  local const_src="$SCRIPT_DIR/agent-rules/rules/CONSTITUTION.md"
  if [ ! -f "$const_src" ]; then
    echo "  ⚠ --constitution：找不到 ${const_src}，跳過"
    return 1
  fi
  echo "→ 憲法（--constitution）：用各家 hook 在 session 開頭注入（讀 marketplace 檔，內容自動跟新）"

  # shared situational-paths file, regenerated on every run — read by the
  # hooks together with the constitution itself.
  local paths_file="$home/.agents/agent-rules-situational-paths.md"
  mkdir -p "$home/.agents"
  touch "$home/.agents/.constitution-on"   # sticky opt-in: later plain runs auto-enable
  situational_paths_body > "$paths_file"

  # HOME-relative forms baked into the hooks so they survive being mounted
  # into a container at a different absolute prefix (see homeref). sh form for
  # shell/JSON commands, tilde form for the python wrapper (expanduser).
  local const_ref paths_ref refresh_ref mkt_ref const_tilde paths_tilde refresh_tilde
  const_ref="$(homeref "$const_src" sh)"
  paths_ref="$(homeref "$paths_file" sh)"
  mkt_ref="$(homeref "$SCRIPT_DIR" sh)"
  const_tilde="$(homeref "$const_src" tilde)"
  paths_tilde="$(homeref "$paths_file" tilde)"

  # self-refresh helper: hooks call this so the marketplace clone stays fresh
  # even if the user never opens Claude Code (whose startup normally does the
  # pull). Throttled to once per 6h, pull runs in the BACKGROUND — adds ~ms to
  # hook time; the freshly pulled content is picked up from the next session.
  local refresh="$home/.agents/agent-rules-refresh.sh"
  refresh_ref="$(homeref "$refresh" sh)"
  refresh_tilde="$(homeref "$refresh" tilde)"
  cat > "$refresh" <<SHEOF
#!/usr/bin/env bash
# agent-rules managed - regenerated by skills-sync.sh --constitution
MKT="$mkt_ref"
STAMP="\$HOME/.agents/.agent-rules-refresh-stamp"
[ -d "\$MKT/.git" ] || exit 0
if [ ! -f "\$STAMP" ] || [ -n "\$(find "\$STAMP" -mmin +360 2>/dev/null)" ]; then
  touch "\$STAMP"
  ( cd "\$MKT" && git pull --quiet >/dev/null 2>&1 ) &
fi
exit 0
SHEOF
  chmod +x "$refresh"

  if [ "$codex" = 1 ]; then
    # SessionStart command hook; plain stdout becomes developer context.
    merge_json_hook "$home/.codex/hooks.json" "SessionStart" \
      "{\"matcher\":\"startup|resume\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash \\\"$refresh_ref\\\"; cat \\\"$const_ref\\\" \\\"$paths_ref\\\"\",\"statusMessage\":\"agent-rules constitution\",\"timeout\":30}]}"
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
import json, os, subprocess
subprocess.Popen(["bash", os.path.expanduser("$refresh_tilde")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
paths = [os.path.expanduser(p) for p in ["$const_tilde", "$paths_tilde"]]
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
  if [ "$cline_present" = 1 ]; then
    if [ -n "$cline_base" ]; then
      # global hooks dir is <base>/Hooks, SIBLING of Rules/Workflows (the app
      # scaffolds it; confirmed by cline#9994) — NOT Rules/Hooks as some blog
      # posts claim. Hooks are macOS/Linux only.
      local chooks="$cline_base/Hooks" cts
      # migrate our files out of the wrong dir earlier versions wrote to
      local oldhooks="$cline_base/Rules/Hooks" oldf
      for oldf in "$oldhooks/TaskStart" "$oldhooks/PreToolUse"; do
        [ -f "$oldf" ] && grep -q "agent-rules managed" "$oldf" && rm -f "$oldf"
      done
      rmdir "$oldhooks" 2>/dev/null || true
      mkdir -p "$chooks"; cts="$chooks/TaskStart"
      if [ -f "$cts" ] && ! grep -q "agent-rules managed" "$cts"; then
        echo "  ⚠ Cline：$cts 已存在且不是本腳本產生的（Cline 每個 hook 只能一支腳本）— 不覆蓋；請手動在你的 TaskStart 裡 cat "$const_ref""
      else
        cat > "$cts" <<SHEOF
#!/usr/bin/env bash
# agent-rules managed - regenerated by skills-sync.sh --constitution
cat >/dev/null
bash "$refresh_ref" 2>/dev/null || true
python3 - "$const_ref" "$paths_ref" <<'PY'
import json, os, sys
txt = "\n\n".join(open(p, encoding="utf-8").read() for p in sys.argv[1:] if os.path.exists(p))
print(json.dumps({"cancel": False, "contextModification": txt}))
PY
SHEOF
        chmod +x "$cts"
        # migrate off the old rules-dir symlink + paths file (hook replaces both)
        [ -n "$cline_dir" ] && rm -f "$cline_dir/agent-rules-constitution.md" "$cline_dir/agent-rules-situational-paths.md"
        echo "  Cline    → ${cts}（TaskStart hook，自動跟新）"
      fi
    else
      # ~/.cline-only layout: global hooks dir undocumented there → keep the
      # rules-dir symlink fallback (also auto-fresh, just not a hook).
      mkdir -p "$cline_dir"
      ln -sfn "$const_src" "$cline_dir/agent-rules-constitution.md"
      cp "$paths_file" "$cline_dir/agent-rules-situational-paths.md"
      echo "  Cline    → ${cline_dir}（無 Cline base 目錄佈局，退回 rules symlink，自動跟新）"
    fi
  fi
  return 0
}

# SAFETY guard (PreToolUse-level interception of destructive commands) for the
# detected agents — upgrades SAFETY.md §1 from "the model read the rule" to "the
# host blocks the call". Claude Code gets this from the agent-rules plugin itself.
wire_guard() {
  local home="$1" codex="$2" opencode="$3" cline_present="$4" cline_base="$5"
  local guard="$SCRIPT_DIR/agent-rules/hooks/guard.py" guard_ref
  guard_ref="$(homeref "$SCRIPT_DIR/agent-rules/hooks/guard.py" sh)"
  if [ ! -f "$guard" ]; then
    echo "  ⚠ 找不到 ${guard}，跳過 SAFETY guard"
    return 0
  fi
  echo "→ SAFETY guard（--constitution）：hook 層攔破壞性指令（pattern 清單＝SAFETY.md §1）"
  if [ "$codex" = 1 ]; then
    merge_json_hook "$home/.codex/hooks.json" "PreToolUse" \
      "{\"hooks\":[{\"type\":\"command\",\"command\":\"python3 \\\"$guard_ref\\\" --agent codex\",\"statusMessage\":\"agent-rules guard\",\"timeout\":15}]}"
    echo "  Codex    → ~/.codex/hooks.json PreToolUse（deny）"
  fi
  if [ -d "$home/.gemini" ]; then
    merge_json_hook "$home/.gemini/settings.json" "BeforeTool" \
      "{\"hooks\":[{\"type\":\"command\",\"command\":\"python3 \\\"$guard_ref\\\" --agent gemini\",\"name\":\"agent-rules-guard\",\"timeout\":10000}]}"
    echo "  Gemini   → ~/.gemini/settings.json BeforeTool（deny）"
  fi
  if [ "$cline_present" = 1 ] && [ -n "$cline_base" ]; then
    local cpre="$cline_base/Hooks/PreToolUse"
    mkdir -p "$cline_base/Hooks"
    if [ -f "$cpre" ] && ! grep -q "agent-rules managed" "$cpre"; then
      echo "  ⚠ Cline：$cpre 已存在且不是本腳本產生的 — 不覆蓋；請在你的 PreToolUse 裡自行呼叫 python3 "$guard_ref" --agent cline"
    else
      cat > "$cpre" <<SHEOF
#!/usr/bin/env bash
# agent-rules managed - regenerated by skills-sync.sh --constitution
exec python3 "$guard_ref" --agent cline
SHEOF
      chmod +x "$cpre"
      echo "  Cline    → ${cpre}（cancel）"
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
  return 0
}

# Read external-skills.json → "name<TAB>url<TAB>ref" lines. Missing/empty → nothing.
external_skill_list() {
  local f="$SCRIPT_DIR/external-skills.json"
  [ -f "$f" ] || return 0
  python3 - "$f" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(0)
for s in d.get("skills", []):
    n, u, r = s.get("name", ""), s.get("url", ""), s.get("ref", "")
    if n and u:
        print(f"{n}\t{u}\t{r or 'main'}")
PY
}

# owner/repo from a github git URL (for `codex plugin marketplace add`).
gh_owner_repo() {  # <url>
  local u="$1"; u="${u%.git}"; u="${u#https://github.com/}"; u="${u#git@github.com:}"
  printf '%s' "$u"
}

# Symlink each skills/<name>/ dir of a cloned repo into a target skills dir
# (whole dir, so co-located resource files travel). Used for agents with no
# native adapter for the repo (Cline always; plain-skill repos on Codex/OpenCode).
drop_skill_dirs() {  # <repo-clone> <target-skills-dir>
  local clone="$1" dst="$2" d
  [ -d "$clone/skills" ] || return 1
  mkdir -p "$dst"
  for d in "$clone/skills"/*/; do
    [ -f "${d}SKILL.md" ] && ln -sfn "${d%/}" "$dst/$(basename "$d")"
  done
  return 0
}

# Install the external (third-party) skill repos listed in external-skills.json
# into the detected NON-Claude agents. superpowers-style repos ship a native
# adapter per agent (gemini-extension.json / .opencode / .codex-plugin) → use that
# agent's native installer so the session-start bootstrap loads (upstream rejects
# plain symlink shims). Plain-skill repos (no adapter, e.g. karpathy) → drop their
# SKILL.md dirs into the agent's skills path. Claude Code gets these via its own
# marketplace plugin path, not here. Best-effort: a failing install logs, never aborts.
sync_external_skills() {  # <home> <cline_present> <cline_skills>
  [ "${NO_EXTERNAL:-0}" = 1 ] && return 0
  local home="$1" cline_present="$2" cline_skills="$3"
  local list; list="$(external_skill_list)"
  [ -n "$list" ] || return 0

  local has_gemini=0 has_codex=0 has_opencode=0
  command -v gemini   >/dev/null 2>&1 && has_gemini=1
  { command -v codex    >/dev/null 2>&1 || [ -d "$home/.codex" ]; } && has_codex=1
  { command -v opencode >/dev/null 2>&1 || [ -d "$home/.config/opencode" ]; } && has_opencode=1
  [ "$has_gemini$has_codex$has_opencode$cline_present" = "0000" ] && return 0

  echo "→ external skills（external-skills.json）：裝進偵測到的非 Claude agent"
  local ext_root="$home/.agents/external"; mkdir -p "$ext_root"
  local name url ref clone has_g has_o has_c sel
  while IFS=$'\t' read -r name url ref; do
    [ -n "$name" ] || continue
    echo "  • $name"
    clone="$ext_root/$name"
    if [ -d "$clone/.git" ]; then
      ( cd "$clone" && git fetch -q origin "$ref" 2>/dev/null && git checkout -q "$ref" 2>/dev/null && git pull -q 2>/dev/null ) || true
    else
      git clone -q --branch "$ref" --depth 1 "$url" "$clone" 2>/dev/null \
        || git clone -q "$url" "$clone" 2>/dev/null || { echo "    ⚠ clone 失敗，跳過"; continue; }
    fi
    has_g=0; has_o=0; has_c=0
    [ -f "$clone/gemini-extension.json" ] && has_g=1
    [ -d "$clone/.opencode" ] && has_o=1
    { [ -d "$clone/.codex-plugin" ] || [ -f "$clone/.agents/plugins/marketplace.json" ]; } && has_c=1

    # Gemini — native extension (its manifest can carry the skills) or skip.
    # Idempotency + success are judged by the installed dir (~/.gemini/extensions/
    # <name>), NOT the CLI: `yes` answers the multiple trust/third-party prompts but
    # under `set -o pipefail` the pipeline returns SIGPIPE(141) even on success, and
    # `gemini extensions list` misbehaves in a fresh HOME. Filesystem is truth.
    if [ "$has_gemini" = 1 ]; then
      if [ "$has_g" != 1 ]; then
        echo "    Gemini   略過（無 gemini-extension.json；純 skill 當不了 extension）"
      elif [ -d "$home/.gemini/extensions/$name" ]; then
        echo "    Gemini   已裝，跳過"
      else
        ( set +o pipefail; yes | gemini extensions install "$url" >/dev/null 2>&1 ) || true
        [ -d "$home/.gemini/extensions/$name" ] \
          && echo "    Gemini   → extension 裝好" || echo "    ⚠ Gemini extension 裝失敗"
      fi
    fi

    # OpenCode — native JS plugin (opencode.jsonc) or skill-drop for plain skills.
    if [ "$has_opencode" = 1 ]; then
      if [ "$has_o" = 1 ] && command -v opencode >/dev/null 2>&1; then
        if grep -qs "$name@git" "$home/.config/opencode/opencode.jsonc" "$home/.config/opencode/opencode.json"; then
          echo "    OpenCode 已裝，跳過"
        else
          opencode plugin "$name@git+$url" --global </dev/null >/dev/null 2>&1 \
            && echo "    OpenCode → plugin 裝好" || echo "    ⚠ OpenCode plugin 裝失敗"
        fi
      else
        drop_skill_dirs "$clone" "$home/.agents/skills" && echo "    OpenCode → skill-drop ~/.agents/skills"
      fi
    fi

    # Codex — native plugin via marketplace, or skill-drop (reads ~/.agents/skills).
    if [ "$has_codex" = 1 ] && command -v codex >/dev/null 2>&1 && [ "$has_c" = 1 ]; then
      codex plugin marketplace add "$(gh_owner_repo "$url")" --ref "$ref" </dev/null >/dev/null 2>&1 || true
      sel="$(codex plugin list 2>/dev/null | grep -oE "[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+" | grep "^${name}@" | head -1)"
      if [ -n "$sel" ]; then
        # STATUS column is "not installed" or "installed, enabled" — test for the
        # former ("installed" alone would also match "not installed").
        if codex plugin list 2>/dev/null | grep -F "$sel" | grep -q "not installed"; then
          codex plugin add "$sel" </dev/null >/dev/null 2>&1 \
            && echo "    Codex    → plugin 裝好" || echo "    ⚠ Codex plugin 裝失敗"
        else
          echo "    Codex    已裝，跳過"
        fi
      else
        echo "    ⚠ Codex marketplace 找不到 ${name}"
      fi
    elif [ "$has_codex" = 1 ]; then
      drop_skill_dirs "$clone" "$home/.agents/skills" && echo "    Codex    → skill-drop ~/.agents/skills"
    fi

    # Cline — no native install → skill-drop into its Skills dir.
    if [ "$cline_present" = 1 ] && [ -n "$cline_skills" ]; then
      drop_skill_dirs "$clone" "$cline_skills" && echo "    Cline    → skill-drop $cline_skills"
    fi
  done <<< "$list"
}

# remove OUR stale symlinks (skill renamed/removed) from a skills dir — only
# symlinks pointing into this repo whose target vanished; user files stay.
prune_own_dead() {  # <dir>
  local d="$1" link
  [ -n "$d" ] && [ -d "$d" ] || return 0
  for link in "$d"/*; do
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in "$SCRIPT_DIR"/*) [ -e "$(readlink "$link")" ] || rm -f "$link" ;; esac
  done
}

# Install THIS repo (kungfu — it ships committed per-agent adapters at its root)
# into each detected non-Claude agent using that agent's native mechanism, so own
# skills reach the agent the same way an external adapter repo does. Claude Code
# gets them via the marketplace bundle, not here. Replaces the pre-adapter approach
# (hand-symlinking each skill + a generated Gemini extension).
wire_own_skills() {  # <home> <cline_present> <cline_skills>
  local home="$1" cline_present="$2" cline_skills="$3" repo="$SCRIPT_DIR" link
  echo "→ 自家 skill：把 kungfu 裝進偵測到的非 Claude agent（committed adapter）"

  # Gemini — committed gemini-extension.json → link the repo (live). Judge by
  # ~/.gemini/extensions/kungfu (link creates it), not the flaky `list`.
  if command -v gemini >/dev/null 2>&1; then
    # migrate off #65's generated extension
    [ -d "$home/.gemini/extensions/kungfu-skills" ] && \
      { ( set +o pipefail; yes | gemini extensions uninstall kungfu-skills >/dev/null 2>&1 ) || true; }
    rm -rf "$home/.agents/gemini-kungfu"
    if [ -d "$home/.gemini/extensions/kungfu" ]; then
      echo "  Gemini   → kungfu extension 已連結（更新自動反映）"
    else
      ( set +o pipefail; yes | gemini extensions link "$repo" >/dev/null 2>&1 ) || true
      [ -d "$home/.gemini/extensions/kungfu" ] \
        && echo "  Gemini   → kungfu extension 連結（committed adapter）" \
        || echo "  ⚠ Gemini：kungfu extension 連結失敗"
    fi
  fi

  # Codex — committed .codex-plugin + .agents marketplace → marketplace add + add.
  if command -v codex >/dev/null 2>&1; then
    # migrate: own skills now come via the plugin, drop old ~/.codex/skills symlinks
    if [ -d "$home/.codex/skills" ]; then
      for link in "$home/.codex/skills"/*; do
        [ -L "$link" ] || continue
        case "$(readlink "$link")" in "$SCRIPT_DIR"/*) rm -f "$link" ;; esac
      done
    fi
    codex plugin marketplace add "$repo" </dev/null >/dev/null 2>&1 || true
    if codex plugin list 2>/dev/null | grep -F "kungfu@kungfu-dev" | grep -q "not installed"; then
      codex plugin add kungfu@kungfu-dev </dev/null >/dev/null 2>&1 \
        && echo "  Codex    → kungfu plugin 裝好" || echo "  ⚠ Codex：kungfu plugin 裝失敗"
    elif codex plugin list 2>/dev/null | grep -q "kungfu@kungfu-dev"; then
      echo "  Codex    → kungfu plugin 已裝"
    else
      echo "  ⚠ Codex：marketplace 找不到 kungfu"
    fi
  fi

  # OpenCode — reads ~/.agents/skills natively → skill-drop (the .opencode plugin
  # path needs an npm-published package; out of scope for the local sync).
  if command -v opencode >/dev/null 2>&1 || [ -d "$home/.config/opencode" ]; then
    drop_skill_dirs "$repo" "$home/.agents/skills" && echo "  OpenCode → skill-drop ~/.agents/skills"
    prune_own_dead "$home/.agents/skills"
  fi

  # Cline — no native install → skill-drop into its Skills dir.
  if [ "$cline_present" = 1 ] && [ -n "$cline_skills" ]; then
    drop_skill_dirs "$repo" "$cline_skills" && echo "  Cline    → skill-drop $cline_skills"
    prune_own_dead "$cline_skills"
  fi
}

sync_agents() {
  local home="$HOME" did=0
  local gemini=0 codex=0 opencode=0 cline_dir=""

  # Detect agents by dir presence (marks did + ensures the neutral ~/.agents/skills
  # that OpenCode reads; Gemini reaches skills via its extension, not this dir).
  if [ -d "$home/.gemini" ] || [ -d "$home/.agents" ]; then
    gemini=1
  fi
  if [ -d "$home/.config/opencode" ]; then
    opencode=1
  fi
  if [ "$gemini" = 1 ] || [ "$opencode" = 1 ]; then
    mkdir -p "$home/.agents/skills"; did=1
  fi
  # Codex CLI: ~/.codex/skills
  if [ -d "$home/.codex" ]; then
    mkdir -p "$home/.codex/skills"; codex=1; did=1
  fi
  # Cline: detect by INSTALL, not by its data dir. The data dir (~/Documents/Cline
  # on macOS, ~/Cline on Linux/WSL — cline#9994) only appears after the first
  # launch, so keying on it means a fresh sync (devcontainer postCreate, or a host
  # where you've installed the extension but not opened it yet) silently skips
  # Cline until you open it and re-run. The VS Code extension folder
  # (saoudrizwan.claude-dev) is on disk the moment it's installed, so we detect
  # that too and provision in one run. No Cline anywhere → nothing created.
  local cline_base="" cline_present=0 cline_skills="" cline_dir=""
  if [ -d "$home/Documents/Cline" ]; then
    cline_base="$home/Documents/Cline"
  elif [ -d "$home/Cline" ]; then
    cline_base="$home/Cline"
  fi
  local extfound=0 g
  for g in "$home"/.vscode*/extensions/"$CLINE_EXT_ID"* \
           "$home"/.cursor*/extensions/"$CLINE_EXT_ID"* \
           "$home"/.windsurf*/extensions/"$CLINE_EXT_ID"*; do
    [ -e "$g" ] && { extfound=1; break; }
  done
  # Cline is "present" if ANY signal fires — data dir, CLI state dir, the
  # installed extension, the workspace config that requests it (closes the
  # devcontainer "still installing" race), or an explicit --cline. No signal at
  # all → nothing is created. --cline is the last-resort manual override.
  local declared=0; cline_declared && declared=1
  if [ -n "$cline_base" ] || [ "$extfound" = 1 ] || [ -d "$home/.cline" ] \
     || [ "$declared" = 1 ] || [ "${FORCE_CLINE:-0}" = 1 ]; then
    cline_present=1; did=1
    # Skills use Cline's native on-demand Skills (>=3.48): a SKILL.md dir under
    # the global skills path, loaded via use_skill only when relevant — so they
    # don't sit in the always-on context the way the old pointer rules did.
    cline_skills="$home/.cline/skills"; mkdir -p "$cline_skills"
    # Rules/Hooks (constitution + guard) need the app-layout base. Default it by
    # OS when Cline is coming (extension/declared/forced) but never opened, so
    # first-run wiring lands where the extension will read once launched.
    if [ -z "$cline_base" ] \
       && { [ "$extfound" = 1 ] || [ "$declared" = 1 ] || [ "${FORCE_CLINE:-0}" = 1 ]; }; then
      case "$(uname -s)" in
        Darwin) cline_base="$home/Documents/Cline" ;;
        *)      cline_base="$home/Cline" ;;
      esac
    fi
    # CLI-only (~/.cline, no app base): constitution falls back to a rules-dir
    # symlink there (the CLI has no Hooks layout).
    [ -z "$cline_base" ] && [ -d "$home/.cline" ] && cline_dir="$home/.cline/rules"
  fi

  if [ "$did" = 0 ]; then
    echo "→ 跨 agent：未偵測到 Gemini / Codex / Cline / OpenCode，略過（只處理了 Claude）"
    return 0
  fi

  # Own skills → detected non-Claude agents, via kungfu's committed adapters
  # (Gemini extension / Codex plugin) or skill-drop (OpenCode/Cline).
  wire_own_skills "$home" "$cline_present" "$cline_skills"

  # migrate off the pre-3.48 approach: we used to write an always-on pointer .md
  # per skill into Cline's Rules dir (and older builds into ~/.cline/rules). Now
  # that Cline has native on-demand Skills those cards are obsolete — remove OURS
  # (constitution/paths files + the pointer cards); the user's own rules stay.
  local rd f
  for rd in "$cline_base/Rules" "$home/.cline/rules"; do
    [ -n "$rd" ] && [ -d "$rd" ] || continue
    for f in "$rd"/*.md; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in
        agent-rules-constitution.md|agent-rules-situational-paths.md)
          rm -f "$f"; echo "  − $(basename "$f")（改用 hook 注入，移除舊檔）" ;;
        *) grep -q "kungfu 的指標規則" "$f" 2>/dev/null \
             && { rm -f "$f"; echo "  − $(basename "$f")（改用原生 Cline Skills，移除舊指標卡）"; } ;;
      esac
    done
    rmdir "$rd" 2>/dev/null || true
  done

  # External third-party skill repos (external-skills.json) → detected non-Claude
  # agents, via each agent's native installer (or skill-drop). Default on; --no-external skips.
  sync_external_skills "$home" "$cline_present" "$cline_skills"

  # Constitution + guard: OPT-IN — these are personal dotfiles, so nothing is
  # written unless --constitution was passed. Each is wired via the agent's own
  # HOOK mechanism (reads the marketplace file at session time → always fresh),
  # mirroring the Claude Code hook plugin. If the constitution file is missing,
  # wire_constitution returns non-zero and we skip the guard too.
  if [ "$CONSTITUTION" = 1 ]; then
    wire_constitution "$home" "$codex" "$opencode" "$cline_present" "$cline_base" "$cline_dir" \
      || return 0
    wire_guard "$home" "$codex" "$opencode" "$cline_present" "$cline_base"
  fi
}


# Everything below is the CLI dispatch. Skip it when this file is SOURCED (the
# test harness sources it to reach the internal functions above).
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then return 0; fi

MODE=""
NOCON=0
for arg in "$@"; do
  case "$arg" in
    --constitution)      CONSTITUTION=1 ;;
    --no-constitution)   NOCON=1 ;;
    --cline)             FORCE_CLINE=1 ;;
    --no-external)       NO_EXTERNAL=1 ;;
    --self-test|agents)  MODE="$arg" ;;
    *) echo "unknown argument: ${arg}（可用：agents、--constitution、--no-constitution、--cline、--no-external、--self-test）" >&2; exit 1 ;;
  esac
done
export FORCE_CLINE="${FORCE_CLINE:-0}"
export NO_EXTERNAL="${NO_EXTERNAL:-0}"

# Sticky opt-in: --constitution once leaves a marker so later PLAIN runs keep the
# constitution/guard hooks fresh (easy to forget the flag on a re-run). The
# marker records that YOU already consented to writing agent dotfiles.
# --no-constitution turns it off and removes the marker.
CON_MARKER="$HOME/.agents/.constitution-on"
if [ "$NOCON" = 1 ]; then
  CONSTITUTION=0
  rm -f "$CON_MARKER"
elif [ "$CONSTITUTION" != 1 ] && [ -f "$CON_MARKER" ]; then
  CONSTITUTION=1
  echo "→ 沿用上次的 --constitution（偵測到 ${CON_MARKER}；要關用 --no-constitution）"
fi

case "$MODE" in
  --self-test) exec bash "$SCRIPT_DIR/skills-sync.test.sh" ;;
  agents)      sync_agents; exit 0 ;;
esac

[ -f "$MARKETPLACE_JSON" ] || { echo "marketplace.json not found at $MARKETPLACE_JSON" >&2; exit 1; }

# No Claude Code on this machine (Cline/Codex/Gemini-only teammate): the whole
# Claude-plugin section needs the `claude` CLI, but cross-agent sync and the
# constitution/guard wiring don't — run just those and exit cleanly. The hooks
# point into THIS clone and self-refresh it, so freshness works without Claude.
if ! command -v claude >/dev/null 2>&1; then
  echo "→ 找不到 claude CLI —— 跳過 Claude plugin 安裝（純 Cline/Codex/Gemini 成員模式）"
  sync_agents
  echo "✓ done — 其他 agent 重開 session 即生效；之後裝了 Claude Code 再重跑本腳本補上 plugin 部分"
  exit 0
fi

echo "→ marketplace: add or update ($MARKET)"
claude plugin marketplace add "$MARKETPLACE_URL" 2>/dev/null || claude plugin marketplace update "$MARKET"

echo "→ plugins（bundle 取代逐裝；舊逐裝的先移除避免同 skill 雙載）"
while IFS=' ' read -r action name; do
  [ -n "$name" ] || continue
  if [ "$action" = "RETIRE" ]; then
    # migration from the pre-bundle layout; a no-op when it was never installed.
    claude plugin uninstall "$name@$MARKET" 2>/dev/null \
      && echo "  − ${name}（改由 bundle 提供）"
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
