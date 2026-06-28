#!/usr/bin/env bash
# skills-sync.sh — one command to install/update EVERY plugin in this marketplace:
# the local skills (wiki-doc-author / sop-to-spec / skill-author) AND the external
# mirror plugins (superpowers / andrej-karpathy-skills).
#
# The plugin list is read from marketplace.json — the single source of truth — so
# adding a skill there is enough; nobody has to remember to install it.
#
# Usage:
#   bash .claude/skills/skills-sync.sh              # add/update marketplace + install/update all plugins
#   bash .claude/skills/skills-sync.sh --self-test  # offline check of the bundle-skip filter
set -euo pipefail

# Swap GITLAB_URL for your internal GitLab mirror of this repo once it exists.
GITLAB_URL="https://gitlab.internal.example.com/mirrors/llm-wiki-skills.git"
MARKET="llm-wiki-skills"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKETPLACE_JSON="$SCRIPT_DIR/.claude-plugin/marketplace.json"

# Print the plugin names to install: every entry EXCEPT the bundle. The bundle is
# a local "./" source listing more than one skill; installing it AND its member
# skills would double-load the same skill. Everything else (the individual local
# skills and the external mirror plugins) gets installed.
plugins_to_install() {
  python3 - "$1" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for p in data.get("plugins", []):
    src = p.get("source")
    skills = p.get("skills", [])
    is_bundle = (src == "./" and isinstance(skills, list) and len(skills) > 1)
    if not is_bundle:
        print(p["name"])
PY
}

self_test() {
  tmp="$(mktemp -d)"
  cat > "$tmp/mp.json" <<'JSON'
{"plugins":[
  {"name":"wiki-doc-author","source":"./","skills":["./wiki-doc-author"]},
  {"name":"sop-to-spec","source":"./","skills":["./sop-to-spec"]},
  {"name":"skill-author","source":"./","skills":["./skill-author"]},
  {"name":"llm-wiki-skills","source":"./","skills":["./wiki-doc-author","./sop-to-spec","./skill-author"]},
  {"name":"superpowers","source":{"source":"url","url":"x"}},
  {"name":"andrej-karpathy-skills","source":{"source":"url","url":"y"}}
]}
JSON
  got="$(plugins_to_install "$tmp/mp.json" | sort | tr '\n' ' ')"
  rm -rf "$tmp"
  want="andrej-karpathy-skills skill-author sop-to-spec superpowers wiki-doc-author "
  if [ "$got" = "$want" ]; then
    echo "self-test OK — bundle skipped, 5 plugins selected"
  else
    echo "self-test FAIL"; echo "  got:  [$got]"; echo "  want: [$want]"; exit 1
  fi
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi

[ -f "$MARKETPLACE_JSON" ] || { echo "marketplace.json not found at $MARKETPLACE_JSON" >&2; exit 1; }

echo "→ marketplace: add or update ($MARKET)"
claude plugin marketplace add "$GITLAB_URL" 2>/dev/null || claude plugin marketplace update "$MARKET"

echo "→ install/update plugins listed in marketplace.json"
while IFS= read -r name; do
  [ -n "$name" ] || continue
  echo "  • $name"
  # install covers a fresh machine; update brings an already-installed one to latest.
  claude plugin install "$name@$MARKET" 2>/dev/null || true
  claude plugin update  "$name@$MARKET" 2>/dev/null || true
done < <(plugins_to_install "$MARKETPLACE_JSON")

echo "✓ done — run /reload-plugins or restart the session to apply"
