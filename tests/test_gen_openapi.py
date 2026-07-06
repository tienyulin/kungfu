"""Tests for gen_openapi.py (wiki-doc-author/scripts/gen_openapi.py)."""

import contextlib
import io
import json
import os
import sys
import tempfile
import types
import unittest
from typing import Any

from _loader import load

gen: Any = load("wiki-doc-author/scripts/gen_openapi.py")


def _run(args: list) -> int:
    """Call gen.main() with the given CLI args, swallow stdout, return the exit code."""
    old = sys.argv
    sys.argv = ["gen_openapi.py"] + args
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return gen.main()
    finally:
        sys.argv = old


def _register(name: str, app: object) -> None:
    """Expose a fake ASGI app as an importable module for --app to find."""
    mod = types.ModuleType(name)
    mod.app = app  # type: ignore[attr-defined]
    sys.modules[name] = mod


class TestGenOpenapiSkip(unittest.TestCase):
    """The hook exits 0 without writing when it doesn't apply."""

    def test_missing_colon(self):
        """--app without module:attr is skipped."""
        self.assertEqual(_run(["--app", "noattr"]), 0)

    def test_unimportable_module(self):
        """An unimportable target is skipped."""
        self.assertEqual(_run(["--app", "does.not.exist:app"]), 0)

    def test_object_without_openapi(self):
        """An app object lacking .openapi() is skipped."""
        _register("gen_fake_noop", object())
        self.assertEqual(_run(["--app", "gen_fake_noop:app"]), 0)


class TestGenOpenapiWriteAndError(unittest.TestCase):
    """The write and error branches behave as documented."""

    def test_writes_sorted_spec(self):
        """An app with .openapi() writes a sorted-key spec and exits 0."""

        class _App:  # pylint: disable=too-few-public-methods
            """Fake app returning out-of-order paths to prove sort_keys."""

            def openapi(self):
                """Return a minimal spec."""
                return {"openapi": "3.1.0", "paths": {"/b": {}, "/a": {}}}

        _register("gen_fake_ok", _App())
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "openapi.json")
            self.assertEqual(_run(["--app", "gen_fake_ok:app", "--out", out]), 0)
            with open(out, encoding="utf-8") as f:
                data = json.load(f)
            self.assertEqual(list(data["paths"]), ["/a", "/b"])

    def test_openapi_raises_exits_one(self):
        """An .openapi() that raises is a real error → exit 1."""

        class _Bad:  # pylint: disable=too-few-public-methods
            """Fake app whose .openapi() raises."""

            def openapi(self):
                """Always raise."""
                raise RuntimeError("boom")

        _register("gen_fake_bad", _Bad())
        self.assertEqual(_run(["--app", "gen_fake_bad:app"]), 1)


if __name__ == "__main__":
    unittest.main()
