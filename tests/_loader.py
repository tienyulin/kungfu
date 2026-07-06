"""Load repo scripts by path so tests need no packaging (stdlib only)."""

import importlib.util
from pathlib import Path
from types import ModuleType

_ROOT = Path(__file__).resolve().parent.parent


def load(relpath: str) -> ModuleType:
    """Import the script at <repo root>/<relpath> and return it as a module."""
    path = _ROOT / relpath
    spec = importlib.util.spec_from_file_location(path.stem, path)
    assert spec and spec.loader, relpath
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
