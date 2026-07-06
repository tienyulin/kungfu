#!/usr/bin/env bash
# verify.sh — one command to verify the repo in any environment.
#
# Mirrors CI exactly. Two modes:
#   bash verify.sh              full gate: lint + tests + validators (needs the
#                               lint toolchain — installs requirements.txt unless
#                               SKIP_INSTALL=1). Needs network for pip once.
#   bash verify.sh --tests-only  ONLY the unit tests — pure stdlib, zero installs,
#                               runs on any python3 (even offline / air-gapped).
#
# The skill scripts and tests are stdlib-only, so --tests-only never needs pip.
# Only the linters (black/flake8/mypy/pylint) come from requirements.txt.
#
# In a devcontainer the toolchain is already present: SKIP_INSTALL=1 bash verify.sh
set -euo pipefail
cd "$(dirname "$0")"

PY="${PYTHON:-python3}"

if [ "${1:-}" = "--tests-only" ]; then
  echo "== unit tests (stdlib, no deps) =="
  "$PY" -m unittest discover -s tests -t tests
  echo "✓ tests green"
  exit 0
fi

if [ "${SKIP_INSTALL:-0}" != 1 ]; then
  echo "== install lint toolchain =="
  "$PY" -m pip install -q -r requirements.txt
fi

echo "== black =="; black --check .
echo "== flake8 =="; flake8 .
echo "== mypy =="; mypy .
# shellcheck disable=SC2046
echo "== pylint =="; pylint $(find . -name "*.py")
echo "== unit tests =="; "$PY" -m unittest discover -s tests -t tests
echo "== validate skills =="; "$PY" skill-author/scripts/validate_skill.py
echo "== localize self-test =="; bash localize.sh --self-test
echo "✓ all green"
