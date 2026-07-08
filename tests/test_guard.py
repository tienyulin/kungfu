"""Tests for the Guard (agent-rules/hooks/guard.py)."""

import contextlib
import io
import json
import sys
import unittest
from typing import Any

from _loader import load

guard: Any = load("agent-rules/hooks/guard.py")


def _run(agent: str, payload: object) -> Any:
    """Run guard.main() in-process for one agent+payload; return parsed stdout or None."""
    old_argv, old_stdin = sys.argv, sys.stdin
    sys.argv = ["guard.py", "--agent", agent]
    sys.stdin = io.StringIO(json.dumps(payload))
    out = io.StringIO()
    try:
        with contextlib.redirect_stdout(out):
            rc = guard.main()
    finally:
        sys.argv, sys.stdin = old_argv, old_stdin
    text = out.getvalue().strip()
    return rc, (json.loads(text) if text else None)


def _bash(cmd: str) -> dict:
    """A Claude/Codex Bash tool payload carrying cmd."""
    return {"tool_name": "Bash", "tool_input": {"command": cmd}}


class TestGuardBlocks(unittest.TestCase):
    """Destructive commands are blocked in each agent's dialect."""

    def test_claude_rm_rf_asks(self):
        """rm -rf → Claude 'ask'."""
        _, d = _run("claude", _bash("rm -rf /tmp/x"))
        self.assertEqual(d["hookSpecificOutput"]["permissionDecision"], "ask")

    def test_codex_force_push_denies(self):
        """git push -f → Codex 'deny'."""
        _, d = _run("codex", _bash("git push -f origin main"))
        self.assertEqual(d["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_gemini_sudo_denies(self):
        """sudo → Gemini deny."""
        payload = {"tool_name": "run_shell_command", "tool_input": {"command": "sudo rm x"}}
        _, d = _run("gemini", payload)
        self.assertEqual(d["decision"], "deny")

    def test_cline_drop_table_cancels(self):
        """DROP TABLE → Cline cancel."""
        payload = {"toolName": "exec", "parameters": {"command": "DROP TABLE users;"}}
        _, d = _run("cline", payload)
        self.assertTrue(d["cancel"])


class TestGuardPasses(unittest.TestCase):
    """Safe input is never blocked (no false positives)."""

    def test_safe_command_no_output(self):
        """A harmless command produces no verdict."""
        _, d = _run("claude", _bash("ls -la && git status"))
        self.assertIsNone(d)

    def test_non_shell_tool_ignored(self):
        """A dangerous string under a non-Bash tool is ignored."""
        _, d = _run("claude", {"tool_name": "Write", "tool_input": {"command": "rm -rf /"}})
        self.assertIsNone(d)

    def test_cline_content_key_not_scanned(self):
        """A file body (content key) is not treated as a command."""
        payload = {"toolName": "write_to_file", "parameters": {"content": "rm -rf build/"}}
        _, d = _run("cline", payload)
        self.assertFalse(d["cancel"])

    def test_delete_with_where_passes(self):
        """DELETE ... WHERE is allowed."""
        _, d = _run("claude", _bash('psql -c "DELETE FROM t WHERE id=1"'))
        self.assertIsNone(d)

    def test_delete_without_where_asks(self):
        """DELETE with no WHERE is blocked."""
        _, d = _run("claude", _bash('psql -c "DELETE FROM t"'))
        self.assertEqual(d["hookSpecificOutput"]["permissionDecision"], "ask")


class TestGuardFailOpen(unittest.TestCase):
    """A guard must never crash the host agent."""

    def test_malformed_stdin_exits_zero(self):
        """Garbage on stdin → exit 0, no output, no exception."""
        old_argv, old_stdin = sys.argv, sys.stdin
        sys.argv = ["guard.py", "--agent", "claude"]
        sys.stdin = io.StringIO("not json at all")
        try:
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(guard.main(), 0)
        finally:
            sys.argv, sys.stdin = old_argv, old_stdin


if __name__ == "__main__":
    unittest.main()
