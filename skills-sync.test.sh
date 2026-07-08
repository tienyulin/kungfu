#!/usr/bin/env bash
# Offline self-tests for skills-sync.sh — moved out of the main script to keep it
# lean. Sources the script (which does NOT run its CLI dispatch when sourced) to
# reach the internal functions, then exercises them. No network, so this works on
# an air-gapped intranet. Run directly, or via `skills-sync.sh --self-test`.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=skills-sync.sh
source "$DIR/skills-sync.sh"

self_test() {
  # lint: `$var` immediately followed by a multibyte char breaks bash 3.2
  # varname lexing under CJK UTF-8 locales (the char is absorbed into the
  # name -> set -u explodes at runtime, e.g. `cline_dir（: unbound variable`).
  # Always write `${var}` before non-ASCII text. Locale-independent check.
  local lint
  lint="$(python3 - "$SCRIPT_DIR/skills-sync.sh" <<'PYLINT'
import re, sys
pat = re.compile(r'\$[a-zA-Z_][a-zA-Z0-9_]*[^\x00-\x7f]')
hits = [f"  line {i}: {l.strip()[:70]}" for i, l in enumerate(open(sys.argv[1], encoding='utf-8'), 1) if pat.search(l)]
print("\n".join(hits))
PYLINT
)"
  if [ -n "$lint" ]; then
    echo "self-test FAIL (unbraced \$var directly before a multibyte char):"
    echo "$lint"
    exit 1
  fi

  local tmp; tmp="$(mktemp -d)"
  cat > "$tmp/mp.json" <<'JSON'
{"plugins":[
  {"name":"wiki-doc-author","source":"./","skills":["./wiki-doc-author"]},
  {"name":"sop-to-spec","source":"./","skills":["./sop-to-spec"]},
  {"name":"skill-author","source":"./","skills":["./skill-author"]},
  {"name":"loner","source":"./","skills":["./loner"]},
  {"name":"kungfu","source":"./","skills":["./wiki-doc-author","./sop-to-spec","./skill-author"]},
  {"name":"superpowers","source":{"source":"url","url":"x"}},
  {"name":"andrej-karpathy-skills","source":{"source":"url","url":"y"}}
]}
JSON
  local got want
  got="$(plugin_plan "$tmp/mp.json" | sort | tr '\n' ';')"
  want="INSTALL andrej-karpathy-skills;INSTALL kungfu;INSTALL loner;INSTALL superpowers;RETIRE skill-author;RETIRE sop-to-spec;RETIRE wiki-doc-author;"
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
mk = s["extraKnownMarketplaces"]["kungfu"]
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
  mkdir -p "$sb/src/skills/demo-skill" "$sb/src/agent-rules/rules" "$sb/src/agent-rules/hooks"
  cp "$SCRIPT_DIR/agent-rules/hooks/guard.py" "$sb/src/agent-rules/hooks/guard.py"
  printf -- '---\nname: demo-skill\ndescription: 測試用 skill。\n---\n# body\n' > "$sb/src/skills/demo-skill/SKILL.md"
  printf -- '# 憲法\nLAW-MARKER-42\n' > "$sb/src/agent-rules/rules/CONSTITUTION.md"
  printf -- '# D\n' > "$sb/src/agent-rules/rules/DECISIONS.md"
  printf -- '# S\n' > "$sb/src/agent-rules/rules/SAFETY.md"
  printf -- '# A\n' > "$sb/src/agent-rules/rules/ANTIPATTERNS.md"

  # Stub the agent CLIs so wire_own_skills (from sync_agents) never hits the real
  # tools: gemini `extensions link` → creates ~/.gemini/extensions/kungfu; codex
  # `plugin list` reports kungfu "not installed" and `plugin add` logs a marker;
  # opencode just needs to exist (its skill-drop is filesystem).
  local stub="$sb/stub"; mkdir -p "$stub"
  cat > "$stub/gemini" <<'EOF'
#!/bin/sh
[ "$1 $2" = "extensions link" ] && mkdir -p "$HOME/.gemini/extensions/kungfu"
exit 0
EOF
  cat > "$stub/codex" <<EOF
#!/bin/sh
[ "\$1 \$2 \$3" = "plugin add kungfu@kungfu-dev" ] && : > "$sb/.codex-added"
[ "\$1 \$2" = "plugin list" ] && echo "kungfu@kungfu-dev  not installed  0.0  /x"
exit 0
EOF
  printf '#!/bin/sh\nexit 0\n' > "$stub/opencode"
  chmod +x "$stub"/gemini "$stub"/codex "$stub"/opencode
  export PATH="$stub:$PATH"

  # case 1: gemini + codex + cline homes present (constitution OFF by default).
  # Own skills reach agents via committed adapters (gemini extension, codex plugin)
  # or skill-drop (opencode ~/.agents, cline ~/.cline).
  mkdir -p "$sb/h1/.gemini" "$sb/h1/.codex" "$sb/h1/.cline"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ -d "$sb/h1/.gemini/extensions/kungfu" ] || { echo "  FAIL: gemini kungfu extension not linked"; fail=1; }
  [ -f "$sb/.codex-added" ] || { echo "  FAIL: codex kungfu plugin not installed"; fail=1; }
  [ "$(readlink "$sb/h1/.cline/skills/demo-skill" 2>/dev/null)" = "$sb/src/skills/demo-skill" ] \
    || { echo "  FAIL: cline skill-drop"; fail=1; }
  [ -L "$sb/h1/.agents/skills/demo-skill" ] || { echo "  FAIL: opencode ~/.agents skill-drop"; fail=1; }
  [ -e "$sb/h1/.codex/AGENTS.md" ] && { echo "  FAIL: constitution written without --constitution"; fail=1; }
  [ -e "$sb/h1/.gemini/GEMINI.md" ] && { echo "  FAIL: gemini constitution written without flag"; fail=1; }

  # case 2: no agent homes → nothing created
  mkdir -p "$sb/h2"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h2"; sync_agents >/dev/null )
  [ -e "$sb/h2/.agents" ] && { echo "  FAIL: created agent dir when none detected"; fail=1; }

  # case 3: idempotent — re-run, skill-drop symlink still valid (not nested)
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ "$(readlink "$sb/h1/.cline/skills/demo-skill" 2>/dev/null)" = "$sb/src/skills/demo-skill" ] \
    || { echo "  FAIL: not idempotent"; fail=1; }

  # case 3b: stale prune (renamed skill) in the skill-drop dirs + pre-3.48 pointer
  # card migration; a user's own symlink / rule stays.
  ln -s "$sb/src/skills/renamed-away" "$sb/h1/.cline/skills/renamed-away"
  ln -s "$sb/elsewhere/thing" "$sb/h1/.cline/skills/users-own"
  mkdir -p "$sb/h1/.cline/rules"
  printf '# Skill: gone\n\ngone.\n\n完整步驟在 `%s/skills/gone/SKILL.md`。（這是指向 kungfu 的指標規則）\n' "$sb/src" > "$sb/h1/.cline/rules/gone-skill.md"
  printf '# my note\n' > "$sb/h1/.cline/rules/my-note.md"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h1"; sync_agents >/dev/null )
  [ -L "$sb/h1/.cline/skills/renamed-away" ] && { echo "  FAIL: stale cline skill symlink not pruned"; fail=1; }
  [ -L "$sb/h1/.cline/skills/users-own" ] || { echo "  FAIL: user's own symlink pruned"; fail=1; }
  [ -f "$sb/h1/.cline/rules/gone-skill.md" ] && { echo "  FAIL: old pointer card not migrated away"; fail=1; }
  [ -f "$sb/h1/.cline/rules/my-note.md" ] || { echo "  FAIL: user's own cline rule pruned"; fail=1; }

  # case 4: OpenCode detected via ~/.config/opencode → shares ~/.agents/skills
  mkdir -p "$sb/h3/.config/opencode"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h3"; sync_agents >/dev/null )
  [ -L "$sb/h3/.agents/skills/demo-skill" ] || { echo "  FAIL: opencode ~/.agents symlink"; fail=1; }

  # case 4b: BOTH Cline layouts (~/.cline CLI state + Documents/Cline app base).
  # Native skills land in ~/.cline/skills; a leftover pre-3.48 pointer card in
  # ~/.cline/rules migrates away; the user's own rule there is kept; and we no
  # longer write skill pointer cards into Documents/Cline/Rules.
  mkdir -p "$sb/h9/Documents/Cline" "$sb/h9/.cline/rules"
  printf '# Skill: old\n\nold.\n\n完整步驟在 `%s/demo-skill/SKILL.md`。（這是指向 kungfu 的指標規則）\n' "$sb/src" > "$sb/h9/.cline/rules/demo-skill.md"
  printf '# my own cline rule\n' > "$sb/h9/.cline/rules/keep-me.md"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h9"; sync_agents >/dev/null )
  [ "$(readlink "$sb/h9/.cline/skills/demo-skill" 2>/dev/null)" = "$sb/src/skills/demo-skill" ] \
    || { echo "  FAIL: both-layouts native skill symlink"; fail=1; }
  [ -f "$sb/h9/.cline/rules/demo-skill.md" ] \
    && { echo "  FAIL: old pointer card not migrated out of ~/.cline/rules"; fail=1; }
  [ -f "$sb/h9/.cline/rules/keep-me.md" ] \
    || { echo "  FAIL: user's own ~/.cline rule removed"; fail=1; }
  [ -e "$sb/h9/Documents/Cline/Rules/demo-skill.md" ] \
    && { echo "  FAIL: should not write pointer card into Documents/Cline/Rules"; fail=1; }

  # case 4c: extension installed but Cline NEVER opened (no data dir) — detected
  # via the extension folder, skills provisioned in ONE run (the "run twice" fix).
  mkdir -p "$sb/h10/.vscode-server/extensions/${CLINE_EXT_ID}-3.99.0"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h10"; sync_agents >/dev/null )
  [ -L "$sb/h10/.cline/skills/demo-skill" ] || { echo "  FAIL: extension-only Cline not provisioned"; fail=1; }

  # case 4d: devcontainer DECLARES the extension but it's not installed yet (the
  # race) — detected via the workspace config, so one postCreate sync wires it.
  mkdir -p "$sb/ws/.devcontainer" "$sb/h11"
  printf '{"customizations":{"vscode":{"extensions":["%s"]}}}\n' "$CLINE_EXT_ID" > "$sb/ws/.devcontainer/devcontainer.json"
  ( cd "$sb/ws"; SCRIPT_DIR="$sb/src"; HOME="$sb/h11"; sync_agents >/dev/null )
  [ -L "$sb/h11/.cline/skills/demo-skill" ] || { echo "  FAIL: declared-in-devcontainer Cline not provisioned"; fail=1; }

  # case 4e: no Cline signal anywhere (clean cwd) → nothing created for Cline
  mkdir -p "$sb/ws2" "$sb/h12"
  ( cd "$sb/ws2"; SCRIPT_DIR="$sb/src"; HOME="$sb/h12"; sync_agents >/dev/null )
  [ -e "$sb/h12/.cline" ] && { echo "  FAIL: created ~/.cline when no Cline signal present"; fail=1; }

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
  # judgment bridge fixture: 有 INDEX.md → 解析後嵌入 paths file；placeholder 換成實路徑
  mkdir -p "$sb/jm"
  printf '# INDEX\nroute: @JUDGMENT@/domains/DEMO.md\n' > "$sb/jm/INDEX.md"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; JUDGMENT_DIR="$sb/jm"; sync_agents >/dev/null )
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h4"; CONSTITUTION=1; JUDGMENT_DIR="$sb/jm"; sync_agents >/dev/null )
  grep -q "route: $sb/jm/domains/DEMO.md" "$sb/h4/.agents/agent-rules-situational-paths.md" 2>/dev/null \
    || { echo "  FAIL: judgment bridge not embedded/resolved in paths file"; fail=1; }
  grep -q "@JUDGMENT@" "$sb/h4/.agents/agent-rules-situational-paths.md" 2>/dev/null \
    && { echo "  FAIL: judgment placeholder not resolved"; fail=1; }
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
  # self-refresh helper: generated, executable, throttled-stamp on git src,
  # silent no-op twice in a row (throttle), codex hook command invokes it
  [ -x "$sb/h4/.agents/agent-rules-refresh.sh" ] || { echo "  FAIL: refresh helper missing"; fail=1; }
  git -C "$sb/src" init -q 2>/dev/null
  ( HOME="$sb/h4"; bash "$sb/h4/.agents/agent-rules-refresh.sh" && bash "$sb/h4/.agents/agent-rules-refresh.sh" ) \
    || { echo "  FAIL: refresh helper errored"; fail=1; }
  sleep 0.2   # pull is backgrounded; give the stamp a beat
  [ -f "$sb/h4/.agents/.agent-rules-refresh-stamp" ] || { echo "  FAIL: refresh stamp not created"; fail=1; }
  grep -q "agent-rules-refresh.sh" "$sb/h4/.codex/hooks.json" \
    || { echo "  FAIL: codex hook does not invoke refresh"; fail=1; }

  # case 6: Cline with Documents/Cline layout → hooks land in <base>/Hooks
  # (sibling of Rules, per cline#9994), run correctly, and our files in the
  # old wrong dir (Rules/Hooks) are migrated away; foreign TaskStart never
  # clobbered.
  mkdir -p "$sb/h5/Documents/Cline/Rules/Hooks"
  printf '#!/bin/sh\n# agent-rules managed\necho old\n' > "$sb/h5/Documents/Cline/Rules/Hooks/TaskStart"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h5"; CONSTITUTION=1; sync_agents >/dev/null )
  cts="$sb/h5/Documents/Cline/Hooks/TaskStart"
  [ -x "$cts" ] || { echo "  FAIL: cline TaskStart hook missing or not executable"; fail=1; }
  echo '{}' | "$cts" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["cancel"] is False and "LAW-MARKER-42" in d["contextModification"]' \
    || { echo "  FAIL: cline TaskStart output wrong"; fail=1; }
  cpre="$sb/h5/Documents/Cline/Hooks/PreToolUse"
  [ -x "$cpre" ] || { echo "  FAIL: cline PreToolUse guard missing or not executable"; fail=1; }
  echo '{"toolName":"executeCommand","parameters":{"command":"rm -rf /"}}' | "$cpre" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["cancel"] is True' \
    || { echo "  FAIL: cline PreToolUse guard did not cancel rm -rf"; fail=1; }
  [ -e "$sb/h5/Documents/Cline/Rules/Hooks/TaskStart" ] \
    && { echo "  FAIL: our file in old wrong hooks dir not migrated away"; fail=1; }
  mkdir -p "$sb/h6/Documents/Cline/Hooks"
  printf '#!/bin/sh\necho user-hook\n' > "$sb/h6/Documents/Cline/Hooks/TaskStart"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h6"; CONSTITUTION=1; sync_agents >/dev/null )
  grep -q "user-hook" "$sb/h6/Documents/Cline/Hooks/TaskStart" \
    || { echo "  FAIL: foreign cline TaskStart clobbered"; fail=1; }

  # case 7b: no `claude` CLI on PATH → main flow degrades to agents-only sync,
  # exits 0 with the skip message, writes nothing without agent dirs
  mkdir -p "$sb/h8"
  out="$(HOME="$sb/h8" PATH="/usr/bin:/bin" bash "$SCRIPT_DIR/skills-sync.sh" 2>&1)" \
    || { echo "  FAIL: no-claude flow exited non-zero"; fail=1; }
  echo "$out" | grep -q "找不到 claude CLI" || { echo "  FAIL: no-claude skip message missing"; fail=1; }
  [ -e "$sb/h8/.agents" ] && { echo "  FAIL: no-claude flow created agent dirs"; fail=1; }

  # case 7: Linux layout (~/Cline, no Documents) → hooks land in ~/Cline/Hooks,
  # rules in ~/Cline/Rules
  mkdir -p "$sb/h7/Cline"
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h7"; CONSTITUTION=1; sync_agents >/dev/null )
  [ -x "$sb/h7/Cline/Hooks/TaskStart" ] || { echo "  FAIL: linux-layout TaskStart missing"; fail=1; }
  [ -x "$sb/h7/Cline/Hooks/PreToolUse" ] || { echo "  FAIL: linux-layout PreToolUse missing"; fail=1; }
  [ -L "$sb/h7/.cline/skills/demo-skill" ] \
    || { echo "  FAIL: linux-layout native skill symlink missing"; fail=1; }
  echo '{"toolName":"executeCommand","parameters":{"command":"sudo rm x"}}' | "$sb/h7/Cline/Hooks/PreToolUse" \
    | python3 -c 'import json,sys; assert json.load(sys.stdin)["cancel"] is True' \
    || { echo "  FAIL: linux-layout guard did not cancel"; fail=1; }

  # case 8: HOME-relative portability — clone UNDER the home dir → generated
  # hooks bake literal $HOME (not the expanded prefix); copying the home into a
  # DIFFERENT home (a container mount) and running the hook there still resolves.
  local H1="$sb/hrel"
  mkdir -p "$H1/kungfu/agent-rules/rules" "$H1/kungfu/agent-rules/hooks" "$H1/Cline"
  printf '# 憲法\nLAW-MARKER-42\n' > "$H1/kungfu/agent-rules/rules/CONSTITUTION.md"
  for r in DECISIONS SAFETY ANTIPATTERNS; do printf '# %s\n' "$r" > "$H1/kungfu/agent-rules/rules/$r.md"; done
  cp "$SCRIPT_DIR/agent-rules/hooks/guard.py" "$H1/kungfu/agent-rules/hooks/guard.py"
  ( SCRIPT_DIR="$H1/kungfu"; HOME="$H1"; CONSTITUTION=1; sync_agents >/dev/null )
  cts="$H1/Cline/Hooks/TaskStart"
  # baked with literal $HOME, NOT the expanded /…/hrel prefix
  grep -q '\$HOME/kungfu/agent-rules/rules/CONSTITUTION.md' "$cts" \
    || { echo "  FAIL: TaskStart not HOME-relative"; fail=1; }
  grep -q "$H1/kungfu/agent-rules/rules/CONSTITUTION.md" "$cts" \
    && { echo "  FAIL: TaskStart still has expanded absolute path"; fail=1; }
  grep -q '~/kungfu/agent-rules/rules/DECISIONS.md' "$H1/.agents/agent-rules-situational-paths.md" \
    || { echo "  FAIL: situational paths not tilde"; fail=1; }
  # simulate a container: mount = copy the home tree to a different HOME, run there
  local HC="$sb/hcontainer"
  mkdir -p "$HC"; cp -R "$H1/." "$HC/"
  out="$(echo '{}' | HOME="$HC" bash "$HC/Cline/Hooks/TaskStart")"
  printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert "LAW-MARKER-42" in d["contextModification"]' \
    || { echo "  FAIL: hook does not resolve under a different HOME (not portable)"; fail=1; }

  # case 9: sticky --constitution — opt in once → marker; later PLAIN run
  # auto-enables; --no-constitution removes the marker. Runs the real script.
  mkdir -p "$sb/hs/Cline"
  ( HOME="$sb/hs"; bash "$SCRIPT_DIR/skills-sync.sh" agents --no-external --constitution >/dev/null 2>&1 )
  [ -f "$sb/hs/.agents/.constitution-on" ] || { echo "  FAIL: marker not written on --constitution"; fail=1; }
  rm -f "$sb/hs/Cline/Hooks/TaskStart"
  ( HOME="$sb/hs"; bash "$SCRIPT_DIR/skills-sync.sh" agents --no-external >/dev/null 2>&1 )   # plain, no flag
  [ -f "$sb/hs/Cline/Hooks/TaskStart" ] \
    || { echo "  FAIL: plain run did not auto-enable via marker"; fail=1; }
  ( HOME="$sb/hs"; bash "$SCRIPT_DIR/skills-sync.sh" agents --no-external --no-constitution >/dev/null 2>&1 )
  [ -e "$sb/hs/.agents/.constitution-on" ] && { echo "  FAIL: --no-constitution left the marker"; fail=1; }

  rm -rf "$sb"
  if [ "$fail" = 0 ]; then
    echo "self-test OK — agents: own-skills-via-adapters(gemini ext / codex plugin / opencode+cline drop) + cline detect(ext/declared/forced, one-run) + pointer-card migration + skip-absent + idempotent + opencode + constitution(opt-in/sticky/hooks/migration-strip/preserve/idempotent/exec-verified/home-relative-portable)"
  else
    exit 1
  fi
}

# External skills: adapter repo → native install per agent (stub CLIs record the
# calls); plain-skill repo → skill-drop; Cline always skill-drop; --no-external skips.
self_test_external() {
  local sb; sb="$(mktemp -d)" fail=0
  mk_repo() {  # <dir> <skillname> [adapters]
    local r="$1" sk="$2"; mkdir -p "$r/skills/$sk"
    printf -- '---\nname: %s\ndescription: x\n---\n# body\n' "$sk" > "$r/skills/$sk/SKILL.md"
    if [ "${3:-}" = adapters ]; then
      printf '{}' > "$r/gemini-extension.json"
      mkdir -p "$r/.opencode" "$r/.codex-plugin" "$r/.claude-plugin"
      printf '//x\n' > "$r/.opencode/plugin.js"      # non-empty: git tracks the dir
      printf '{}\n'   > "$r/.codex-plugin/plugin.json"
      # Claude marketplace adapter: repo is its own marketplace (superpowers-like)
      printf '{"name":"%s-mkt","plugins":[{"name":"%s-plugin"}]}\n' "$2" "$2" > "$r/.claude-plugin/marketplace.json"
    fi
    ( cd "$r" && git init -q -b main && git add -A \
        && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null 2>&1
  }
  mk_repo "$sb/repoA" aa adapters   # superpowers-like (has adapters)
  mk_repo "$sb/repoB" bb            # karpathy-like (plain skill only)

  mkdir -p "$sb/src"
  cat > "$sb/src/external-skills.json" <<JSON
{"skills":[{"name":"repoA","url":"$sb/repoA","ref":"main"},{"name":"repoB","url":"$sb/repoB","ref":"main"}]}
JSON

  # stub CLIs on PATH — record every call; codex list reports repoA "not installed".
  local bin="$sb/bin" log="$sb/calls.log"; mkdir -p "$bin"
  cat > "$bin/gemini"   <<EOF
#!/bin/sh
echo "gemini \$*" >> "$log"; exit 0
EOF
  cat > "$bin/codex"    <<EOF
#!/bin/sh
echo "codex \$*" >> "$log"
[ "\$*" = "plugin list" ] && echo "repoA@fakemkt  not installed  1.0  /x"
exit 0
EOF
  cat > "$bin/opencode" <<EOF
#!/bin/sh
echo "opencode \$*" >> "$log"; exit 0
EOF
  cat > "$bin/claude"   <<EOF
#!/bin/sh
echo "claude \$*" >> "$log"; exit 0
EOF
  chmod +x "$bin"/*

  local h="$sb/h"; mkdir -p "$h/.cline/skills" "$h/.config/opencode"
  ( SCRIPT_DIR="$sb/src"; HOME="$h"; PATH="$bin:$PATH"
    sync_external_skills "$h" 1 "$h/.cline/skills" ) >/dev/null 2>&1

  [ -d "$h/.agents/external/repoA/.git" ] || { echo "  FAIL: repoA not cloned"; fail=1; }
  # adapter repo → native installs invoked
  grep -q "gemini extensions install $sb/repoA" "$log" || { echo "  FAIL: gemini install not called (adapter repo)"; fail=1; }
  grep -q "opencode plugin repoA@git" "$log"           || { echo "  FAIL: opencode plugin not called"; fail=1; }
  grep -q "codex plugin marketplace add $sb/repoA" "$log" || { echo "  FAIL: codex marketplace add not called"; fail=1; }
  grep -q "codex plugin add repoA@fakemkt" "$log"      || { echo "  FAIL: codex plugin add not called"; fail=1; }
  # adapter repo NOT skill-dropped into ~/.agents/skills (native install handles it)
  [ -L "$h/.agents/skills/aa" ] && { echo "  FAIL: adapter repo wrongly skill-dropped to ~/.agents/skills"; fail=1; }
  # adapter repo IS dropped into Cline (no native install there)
  [ -L "$h/.cline/skills/aa" ] || { echo "  FAIL: repoA skill not dropped into cline"; fail=1; }
  # plain repo → skill-drop to ~/.agents/skills + cline; gemini NOT installed for it
  [ -L "$h/.agents/skills/bb" ] || { echo "  FAIL: repoB not dropped into ~/.agents/skills"; fail=1; }
  [ -L "$h/.cline/skills/bb" ]  || { echo "  FAIL: repoB not dropped into cline"; fail=1; }
  grep -q "gemini extensions install $sb/repoB" "$log" && { echo "  FAIL: gemini install wrongly called for plain repo"; fail=1; }
  # Claude: adapter repo (its own .claude-plugin/marketplace.json) → marketplace add + install
  grep -q "claude plugin marketplace add $sb/repoA" "$log" || { echo "  FAIL: claude marketplace add not called (adapter repo)"; fail=1; }
  grep -q "claude plugin install aa-plugin@aa-mkt" "$log"   || { echo "  FAIL: claude plugin install not called"; fail=1; }
  [ -L "$h/.claude/skills/aa" ] && { echo "  FAIL: adapter repo wrongly skill-dropped to ~/.claude/skills"; fail=1; }
  # Claude: plain repo (no Claude marketplace) → skill-drop into ~/.claude/skills
  [ -L "$h/.claude/skills/bb" ] || { echo "  FAIL: repoB not dropped into ~/.claude/skills"; fail=1; }

  # --no-external skips entirely
  ( SCRIPT_DIR="$sb/src"; HOME="$sb/h2"; PATH="$bin:$PATH"; NO_EXTERNAL=1
    sync_external_skills "$sb/h2" 0 "" ) >/dev/null 2>&1
  [ -e "$sb/h2/.agents/external" ] && { echo "  FAIL: --no-external still ran"; fail=1; }

  rm -rf "$sb"
  [ "$fail" = 0 ] && echo "self-test OK — external: clone + native-install(gemini/opencode/codex/claude) for adapter repos + skill-drop(plain + cline + claude) + no-external opt-out" || return 1
}

self_test
self_test_guard
self_test_agents
self_test_external
