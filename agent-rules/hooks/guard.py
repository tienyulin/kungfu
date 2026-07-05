#!/usr/bin/env python3
"""agent-rules SAFETY guard — PreToolUse-level enforcement of SAFETY.md §1.

Reads the agent's hook payload from stdin, extracts the shell command, and if
it matches a destructive pattern answers with that agent's block/ask response.
Pure stdlib. Always exits 0 — the decision travels in the JSON, and a guard
crash must never take the agent down with it.

Usage: guard.py --agent claude|codex|gemini|cline

NOTE: the pattern list below is mirrored in the generated OpenCode plugin
(agent-rules-guard.js, written by skills-sync.sh --constitution). Change one →
change both.
"""
import json
import re
import sys

PATTERNS = [
    (re.compile(r"\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r)\b"), "rm -rf"),
    (re.compile(r"\bgit\s+reset\s+--hard\b"), "git reset --hard"),
    (re.compile(r"\bgit\s+push\b[^|;&]*(\s--force(-with-lease)?\b|\s-f\b)"), "git push --force"),
    (re.compile(r"\bgit\s+clean\s+-[a-zA-Z]*f"), "git clean -f"),
    (re.compile(r"\bgit\s+checkout\s+--\s+\."), "git checkout -- ."),
    (re.compile(r"\bgit\s+restore\s+\.(\s|$)"), "git restore ."),
    (re.compile(r"\bdrop\s+(table|database)\b", re.I), "DROP TABLE/DATABASE"),
    (re.compile(r"\btruncate\s+table\b", re.I), "TRUNCATE TABLE"),
    (re.compile(r"\bdelete\s+from\b(?![\s\S]*\bwhere\b)", re.I), "DELETE without WHERE"),
    (re.compile(r"(^|[;&|]\s*)sudo\b"), "sudo"),
    (re.compile(r"\b(chmod|chown)\s+-[a-zA-Z]*R[a-zA-Z]*\s+[^ ]*\s*(/|~)(\s|$)", re.I), "recursive chmod/chown on / or ~"),
]

REASON_PREFIX = "agent-rules SAFETY hook: 命中破壞性指令 pattern"
REASON_SUFFIX = (
    "。SAFETY.md §1：把完整指令與影響範圍亮給使用者，取得同一回合的明確同意再執行，"
    "或請使用者自己跑。"
)


def find_commands(payload, agent):
    """Extract candidate command strings from the agent-specific payload."""
    if agent in ("claude", "codex"):
        if payload.get("tool_name") != "Bash":
            return []
        cmd = (payload.get("tool_input") or {}).get("command")
        return [cmd] if isinstance(cmd, str) else []
    if agent == "gemini":
        if payload.get("tool_name") != "run_shell_command":
            return []
        cmd = (payload.get("tool_input") or {}).get("command")
        return [cmd] if isinstance(cmd, str) else []
    # cline: PreToolUse input schema is undocumented — scan every string value
    # sitting under a command-ish key, so file contents (content/diff keys)
    # never false-positive.
    found = []

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(value, str) and re.search(r"command|cmd", key, re.I):
                    found.append(value)
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(payload)
    return found


def main():
    agent = "claude"
    if "--agent" in sys.argv:
        agent = sys.argv[sys.argv.index("--agent") + 1]
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # malformed/empty input: never block, never crash the agent

    hits = []
    for cmd in find_commands(payload, agent):
        for rx, label in PATTERNS:
            if rx.search(cmd):
                hits.append(label)
                break
    if not hits:
        if agent == "cline":
            print(json.dumps({"cancel": False}))
        return 0

    reason = REASON_PREFIX + "（" + ", ".join(hits) + "）" + REASON_SUFFIX
    if agent == "claude":
        # "ask" surfaces a confirmation prompt to the user — exactly Law 9.
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": reason,
        }}, ensure_ascii=False))
    elif agent == "codex":
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}, ensure_ascii=False))
    elif agent == "gemini":
        print(json.dumps({"decision": "deny", "reason": reason}, ensure_ascii=False))
    elif agent == "cline":
        print(json.dumps({"cancel": True, "errorMessage": reason}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
