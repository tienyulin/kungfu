#!/usr/bin/env python3
"""pre-commit hook: regenerate openapi.json from the app's code — stdlib only.

The OpenAPI spec is generated FROM your code (routes/params/Pydantic models), so
this keeps committed openapi.json always in sync. Import the app object and call
.openapi(); no server needed.

Usage (in .pre-commit-config.yaml, see docs/guides/authoring-source-docs.md):
  entry: python scripts/gen_openapi.py --app app.main:app
or set env APP_MODULE=app.main:app. Output defaults to ./openapi.json.

If the target isn't importable or has no .openapi() (not FastAPI / can't produce
a spec), exit 0 WITHOUT writing — this hook simply doesn't apply (use Mode B,
hand-written markdown). It never blocks a commit for that reason.
"""

import argparse
import contextlib
import importlib
import io
import json
import os
import sys
import tempfile
import types


def _run(args):
    """Call main() with the given CLI args, swallow stdout, return the exit code."""
    old = sys.argv
    sys.argv = ["gen_openapi.py"] + args
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            return main()
    finally:
        sys.argv = old


def _self_test():
    """Exercise the skip / write / error branches with fake ASGI apps (stdlib only)."""
    # --app without ':' → not a module:attr target → skip, exit 0
    assert _run(["--app", "noattr"]) == 0
    # unimportable module → hook doesn't apply → skip, exit 0
    assert _run(["--app", "does.not.exist:app"]) == 0

    # object without a callable .openapi() → skip, exit 0
    m_noop = types.ModuleType("gen_openapi_fake_noop")
    m_noop.app = object()  # type: ignore[attr-defined]
    sys.modules["gen_openapi_fake_noop"] = m_noop
    assert _run(["--app", "gen_openapi_fake_noop:app"]) == 0

    # app WITH .openapi() → writes a sorted-key spec, exit 0
    class _App:  # pylint: disable=too-few-public-methods
        """Fake FastAPI-ish app whose .openapi() returns a spec."""

        def openapi(self):
            """Return a minimal spec with out-of-order paths to prove sort_keys."""
            return {"openapi": "3.1.0", "paths": {"/b": {}, "/a": {}}}

    m_ok = types.ModuleType("gen_openapi_fake_ok")
    m_ok.app = _App()  # type: ignore[attr-defined]
    sys.modules["gen_openapi_fake_ok"] = m_ok
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, "openapi.json")
        assert _run(["--app", "gen_openapi_fake_ok:app", "--out", out]) == 0
        with open(out, encoding="utf-8") as f:
            data = json.load(f)
        assert list(data["paths"]) == ["/a", "/b"], data["paths"]  # sort_keys=True

    # .openapi() that raises → real error → exit 1
    class _Bad:  # pylint: disable=too-few-public-methods
        """Fake app whose .openapi() raises, to exercise the error branch."""

        def openapi(self):
            """Always raise, standing in for a broken spec build."""
            raise RuntimeError("boom")

    m_bad = types.ModuleType("gen_openapi_fake_bad")
    m_bad.app = _Bad()  # type: ignore[attr-defined]
    sys.modules["gen_openapi_fake_bad"] = m_bad
    assert _run(["--app", "gen_openapi_fake_bad:app"]) == 1

    print("gen_openapi self-test: OK")


def main():
    """Import the ASGI app and write its OpenAPI spec; skip gracefully if not applicable."""
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--app",
        default=os.environ.get("APP_MODULE", "app.main:app"),
        help="ASGI app target as module:attr (uvicorn style)",
    )
    ap.add_argument("--out", default="openapi.json")
    ap.add_argument("--self-test", action="store_true", help="run offline self-checks and exit")
    args = ap.parse_args()

    if args.self_test:
        _self_test()
        return 0

    if ":" not in args.app:
        print(f"[gen-openapi] --app 需為 module:attr，收到 '{args.app}' → 跳過")
        return 0
    mod_name, attr = args.app.split(":", 1)
    try:
        mod = importlib.import_module(mod_name)
        app = getattr(mod, attr)
    except Exception as e:  # pylint: disable=broad-exception-caught
        # Any import/attr failure means this hook doesn't apply (Mode B) — never block.
        print(f"[gen-openapi] 無法 import {args.app}（{type(e).__name__}）→ 跳過（走 Mode B 手寫）")
        return 0
    if not hasattr(app, "openapi") or not callable(app.openapi):
        print(f"[gen-openapi] {args.app} 沒有 .openapi()（非 FastAPI/不能產）→ 跳過")
        return 0

    try:
        spec = app.openapi()
    except Exception as e:  # pylint: disable=broad-exception-caught
        # .openapi() can raise anything; report and fail this hook (real error).
        print(f"[gen-openapi] app.openapi() 失敗：{e}")
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(spec, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"[gen-openapi] 已寫 {args.out}（{len(spec.get('paths', {}))} paths）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
