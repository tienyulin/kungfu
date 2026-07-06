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

# default public repo (owner/repo) -> config var holding the replacement
#   MARKETPLACE_URL / SUPERPOWERS_URL / KARPATHY_URL
# Both the https and ssh `.git` install-URL forms are recognized and replaced:
#   https://github.com/<owner>/<repo>.git   and   git@github.com:<owner>/<repo>.git
# Bare forms (no .git) are left alone on purpose — those are the human-readable
# attribution links in the "上游" table, not install sources.
DEFAULT_MARKETPLACE="tienyulin/kungfu"
DEFAULT_SUPERPOWERS="obra/superpowers"
DEFAULT_KARPATHY="forrestchang/andrej-karpathy-skills"

FILES=(
  "README.md"
  "skills-sync.sh"
  ".claude-plugin/marketplace.json"
  "agent-rules-setup/SKILL.md"
)

self_test() {
  local tmp fail=0 before H S
  tmp="$(mktemp -d)"
  H="$(gh_https "$DEFAULT_MARKETPLACE")"; S="$(gh_ssh "$DEFAULT_MARKETPLACE")"
  # 2 https install URLs, 1 ssh install URL, and 1 BARE attribution link (no .git)
  printf 'add %s\nclone %s\nssh %s\nsee https://github.com/%s\n' \
    "$H" "$H" "$S" "$DEFAULT_MARKETPLACE" > "$tmp/README.md"
  printf 'url %s\n' "$(gh_https "$DEFAULT_SUPERPOWERS")" > "$tmp/skills-sync.sh"
  ( cd "$tmp"; FILES=("README.md" "skills-sync.sh"); apply "https://git.corp/x/kf.git" "https://git.corp/m/sp.git" "" )
  # both https(2) and ssh(1) install forms became the target = 3 occurrences
  [ "$(grep -Fo "https://git.corp/x/kf.git" "$tmp/README.md" | wc -l | tr -d ' ')" = 3 ] \
    || { echo "  FAIL: https+ssh install forms not all replaced"; fail=1; }
  grep -qF "$H" "$tmp/README.md" && { echo "  FAIL: https default left"; fail=1; }
  grep -qF "$S" "$tmp/README.md" && { echo "  FAIL: ssh default left"; fail=1; }
  # bare attribution link (no .git) must survive untouched
  grep -qF "see https://github.com/$DEFAULT_MARKETPLACE" "$tmp/README.md" \
    || { echo "  FAIL: bare attribution link clobbered"; fail=1; }
  grep -qF "https://git.corp/m/sp.git" "$tmp/skills-sync.sh" || { echo "  FAIL: superpowers not replaced"; fail=1; }
  # idempotent: a second run changes nothing
  before="$(cat "$tmp/README.md")"
  ( cd "$tmp"; FILES=("README.md"); apply "https://git.corp/x/kf.git" "" "" )
  [ "$before" = "$(cat "$tmp/README.md")" ] || { echo "  FAIL: not idempotent"; fail=1; }
  rm -rf "$tmp"
  [ "$fail" = 0 ] && echo "self-test OK — localize: https+ssh forms replaced, bare attribution kept, skip-empty, idempotent" || exit 1
}

# portable in-place sed (GNU has --version; BSD/macOS does not)
sed_i() {  # sed_i <expr> <file>
  if sed --version >/dev/null 2>&1; then LC_ALL=C sed -i "$1" "$2"; else LC_ALL=C sed -i '' "$1" "$2"; fi
}

# the two install-URL forms of a github owner/repo (both end in .git)
gh_https() { printf 'https://github.com/%s.git' "$1"; }
gh_ssh()   { printf 'git@github.com:%s.git' "$1"; }
# escape BRE-special chars so a URL is matched literally by sed
esc() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }

# replace both https and ssh .git forms of one repo with the target URL in a file
replace_repo() {  # <owner/repo default> <target url> <file>
  local def="$1" val="$2" f="$3" h s
  [ -z "$val" ] && return 0
  h="$(gh_https "$def")"; s="$(gh_ssh "$def")"
  [ "$val" != "$h" ] && sed_i "s|$(esc "$h")|$val|g" "$f"
  [ "$val" != "$s" ] && sed_i "s|$(esc "$s")|$val|g" "$f"
  return 0
}

# count occurrences of both forms of a repo across FILES
count_repo() {  # <owner/repo default>
  local def="$1" h s n=0 f c
  h="$(gh_https "$def")"; s="$(gh_ssh "$def")"
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    c=$(grep -Fo "$h" "$f" 2>/dev/null | wc -l); n=$((n + c))
    c=$(grep -Fo "$s" "$f" 2>/dev/null | wc -l); n=$((n + c))
  done
  echo "$n"
}

# apply <marketplace_url> <superpowers_url> <karpathy_url>  (empty = keep default)
apply() {
  local mkt="$1" sp="$2" kp="$3" f
  for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    replace_repo "$DEFAULT_MARKETPLACE" "$mkt" "$f"
    replace_repo "$DEFAULT_SUPERPOWERS" "$sp" "$f"
    replace_repo "$DEFAULT_KARPATHY" "$kp" "$f"
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

echo "→ localize：把預設公開 URL（https 與 ssh 兩形式）換成 config 內的值"
for pair in \
  "marketplace|$DEFAULT_MARKETPLACE|${MARKETPLACE_URL:-}" \
  "superpowers|$DEFAULT_SUPERPOWERS|${SUPERPOWERS_URL:-}" \
  "karpathy|$DEFAULT_KARPATHY|${KARPATHY_URL:-}"; do
  IFS='|' read -r name def val <<<"$pair"
  if [ -z "$val" ]; then
    echo "  · $name：保持預設（config 未設）"
    continue
  fi
  echo "  · $name：github.com/$def（.git，https+ssh）→ $val（$(count_repo "$def") 處）"
done

if [ "$DRY" = 1 ]; then
  echo "（--dry-run，未寫入。移除 --dry-run 實際套用。）"
  exit 0
fi

apply "${MARKETPLACE_URL:-}" "${SUPERPOWERS_URL:-}" "${KARPATHY_URL:-}"
echo "✓ done —— 建議接著跑 bash skills-sync.sh --self-test 確認三套全綠，再 commit。"
