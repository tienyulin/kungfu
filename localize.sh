#!/usr/bin/env bash
# localize.sh — point this marketplace at an internal git host in one run.
#
# The repo ships with public GitHub URLs (works out of the box). To move it
# in-house, copy localize.config.example -> localize.config, fill in your
# internal URLs, then run this. It rewrites the default URLs to yours across a
# fixed file set. Idempotent: once a default is replaced it's gone, so a second
# run is a no-op. To re-target: `git checkout -- <files>` first, then re-run.
#
# Usage:
#   bash localize.sh [config]        # apply (default config: ./localize.config)
#   bash localize.sh --dry-run [cfg] # show what would change, write nothing
#   bash localize.sh --self-test     # offline check of the replace logic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# default (public) URL  ->  config var holding the replacement
#   MARKETPLACE_URL / SUPERPOWERS_URL / KARPATHY_URL
DEFAULT_MARKETPLACE="https://github.com/tienyulin/kungfu.git"
DEFAULT_SUPERPOWERS="https://github.com/obra/superpowers.git"
DEFAULT_KARPATHY="https://github.com/forrestchang/andrej-karpathy-skills.git"

FILES=(
  "README.md"
  "skills-sync.sh"
  ".claude-plugin/marketplace.json"
  "agent-rules-setup/SKILL.md"
)

self_test() {
  local tmp; tmp="$(mktemp -d)" fail=0
  printf 'add %s\nclone %s\n' "$DEFAULT_MARKETPLACE" "$DEFAULT_MARKETPLACE" > "$tmp/README.md"
  printf 'url %s\n' "$DEFAULT_SUPERPOWERS" > "$tmp/skills-sync.sh"
  ( cd "$tmp"
    FILES=("README.md" "skills-sync.sh")
    apply "https://git.corp/x/kungfu.git" "https://git.corp/m/sp.git" "" )
  grep -q "https://git.corp/x/kungfu.git" "$tmp/README.md" || { echo "  FAIL: marketplace not replaced"; fail=1; }
  [ "$(grep -c "https://git.corp/x/kungfu.git" "$tmp/README.md")" = 2 ] || { echo "  FAIL: not all occurrences replaced"; fail=1; }
  grep -q "$DEFAULT_MARKETPLACE" "$tmp/README.md" && { echo "  FAIL: default URL still present"; fail=1; }
  grep -q "https://git.corp/m/sp.git" "$tmp/skills-sync.sh" || { echo "  FAIL: superpowers not replaced"; fail=1; }
  # idempotent: a second run over the already-localized file changes nothing
  before="$(cat "$tmp/README.md")"
  ( cd "$tmp"; FILES=("README.md"); apply "https://git.corp/x/kungfu.git" "" "" )
  [ "$before" = "$(cat "$tmp/README.md")" ] || { echo "  FAIL: not idempotent"; fail=1; }
  rm -rf "$tmp"
  [ "$fail" = 0 ] && echo "self-test OK — localize: replace all occurrences + skip-empty + no-default-left + idempotent" || exit 1
}

# portable in-place sed (GNU has --version; BSD/macOS does not)
sed_i() {  # sed_i <expr> <file>
  if sed --version >/dev/null 2>&1; then LC_ALL=C sed -i "$1" "$2"; else LC_ALL=C sed -i '' "$1" "$2"; fi
}

# apply <marketplace_url> <superpowers_url> <karpathy_url>  (empty = keep default)
apply() {
  local mkt="$1" sp="$2" kp="$3" f
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    [ -n "$mkt" ] && [ "$mkt" != "$DEFAULT_MARKETPLACE" ] && sed_i "s|$DEFAULT_MARKETPLACE|$mkt|g" "$f"
    [ -n "$sp" ]  && [ "$sp"  != "$DEFAULT_SUPERPOWERS" ] && sed_i "s|$DEFAULT_SUPERPOWERS|$sp|g" "$f"
    [ -n "$kp" ]  && [ "$kp"  != "$DEFAULT_KARPATHY" ]    && sed_i "s|$DEFAULT_KARPATHY|$kp|g" "$f"
  done
  return 0
}

case "${1:-}" in
  --self-test) self_test; exit 0 ;;
esac

DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
CFG="${1:-$SCRIPT_DIR/localize.config}"

if [ ! -f "$CFG" ]; then
  echo "找不到 config: $CFG" >&2
  echo "先複製 localize.config.example → localize.config 並填入你的內部 URL。" >&2
  exit 1
fi
# shellcheck disable=SC1090
MARKETPLACE_URL="" SUPERPOWERS_URL="" KARPATHY_URL=""
. "$CFG"

cd "$SCRIPT_DIR"

echo "→ localize：把預設公開 URL 換成 config 內的值"
for pair in \
  "marketplace|$DEFAULT_MARKETPLACE|${MARKETPLACE_URL:-}" \
  "superpowers|$DEFAULT_SUPERPOWERS|${SUPERPOWERS_URL:-}" \
  "karpathy|$DEFAULT_KARPATHY|${KARPATHY_URL:-}"; do
  IFS='|' read -r name def val <<<"$pair"
  if [ -z "$val" ] || [ "$val" = "$def" ]; then
    echo "  · $name：保持預設（config 未設或相同）"
    continue
  fi
  n=0
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    c=$(grep -c "$def" "$f" 2>/dev/null || true); n=$((n + c))
  done
  echo "  · $name：$def → $val（$n 處）"
done

if [ "$DRY" = 1 ]; then
  echo "（--dry-run，未寫入。移除 --dry-run 實際套用。）"
  exit 0
fi

apply "${MARKETPLACE_URL:-}" "${SUPERPOWERS_URL:-}" "${KARPATHY_URL:-}"
echo "✓ done —— 建議接著跑 bash skills-sync.sh --self-test 確認三套全綠，再 commit。"
