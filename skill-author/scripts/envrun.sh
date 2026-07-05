#!/usr/bin/env bash
# envrun.sh — run a command in the right environment, deterministically.
#
# Decision tree (first match wins):
#   1. Already inside a container (/.dockerenv, $REMOTE_CONTAINERS, $DEVCONTAINER)
#      -> run directly (covers "Claude attached inside a VS Code dev container").
#      Assumption: whatever container we're in IS the intended environment —
#      envrun cannot tell one container from another from the inside.
#   2. No .devcontainer/devcontainer.json (nor .devcontainer.json) found in cwd
#      or any parent up to the git root -> repo doesn't use devcontainers; run
#      directly on the host.
#   3. ENVRUN_HOST=1 -> explicit opt-out; run directly on the host.
#   4. A container for the workspace folder is running (found via the
#      devcontainer.local_folder label, set by both VS Code and the
#      devcontainer CLI) -> exec inside it, cd'd to the subdir matching cwd.
#   5. devcontainer CLI available -> `devcontainer up`, then exec inside.
#   6. Otherwise exit 2 and print the options (install CLI / start via
#      VS Code / ENVRUN_HOST=1). Never silently falls back to the host.
#
# Usage: bash scripts/envrun.sh <command...>
#        bash scripts/envrun.sh --self-test
# Env vars for the command must be passed as arguments, not as a prefix:
#   bash scripts/envrun.sh env K=V <command...>     # works in every branch
#   K=V bash scripts/envrun.sh <command...>         # LOST when exec'ing into a container
#
# NOTE: identical copies of this file live in several skills' scripts/ dirs;
# validate_skill.py enforces they stay byte-identical (within the skills repo —
# copies pasted into target repos are unmanaged). Edit one, copy to all.
set -euo pipefail

self_test() {
  local script rc out
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  t="$(mktemp -d)"  # not local: the EXIT trap fires after the function returns
  trap 'rm -rf "${t:-}"' EXIT

  # 1) no devcontainer config anywhere up the tree -> host passthrough
  #    (.git marks the walk-up boundary so a config above the repo can't leak in)
  mkdir -p "$t/plain/.git"
  out="$(cd "$t/plain" && bash "$script" echo ok)"
  [ "$out" = ok ] || { echo "FAIL: host passthrough"; exit 1; }

  mkdir -p "$t/repo/.git" "$t/repo/.devcontainer" "$t/repo/svc"
  echo '{}' >"$t/repo/.devcontainer/devcontainer.json"

  # 2) inside-container marker -> direct exec even with a config present
  out="$(cd "$t/repo" && DEVCONTAINER=1 bash "$script" echo ok)"
  [ "$out" = ok ] || { echo "FAIL: inside-container direct exec"; exit 1; }

  # 3) explicit host opt-out
  out="$(cd "$t/repo" && ENVRUN_HOST=1 bash "$script" echo ok)"
  [ "$out" = ok ] || { echo "FAIL: ENVRUN_HOST opt-out"; exit 1; }

  # 4+5) config present but no usable docker/CLI -> exit 2, command NOT
  #    executed — also from a subdir (monorepo walk-up must find the root
  #    config instead of silently running on the host). Inside a container
  #    the inside-marker short-circuits first, so skip there.
  if [ ! -f /.dockerenv ] && [ -z "${REMOTE_CONTAINERS:-}" ] && [ -z "${DEVCONTAINER:-}" ]; then
    for dir in "$t/repo" "$t/repo/svc"; do
      rc=0
      out="$(cd "$dir" && PATH=/nonexistent /bin/bash "$script" echo leaked 2>/dev/null)" || rc=$?
      { [ "$rc" -eq 2 ] && [ -z "$out" ]; } || {
        echo "FAIL: expected exit 2 and no output without docker/CLI in $dir, got rc=$rc out='$out'"
        exit 1
      }
    done
  fi

  echo "envrun self-test: OK"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit 0
fi
[ $# -ge 1 ] || { echo "usage: bash envrun.sh <command...>" >&2; exit 64; }

# 1) already inside a container
if [ -f /.dockerenv ] || [ -n "${REMOTE_CONTAINERS:-}" ] || [ -n "${DEVCONTAINER:-}" ]; then
  exec "$@"
fi

# Find the workspace folder: walk up from cwd to the git root (or /) looking
# for a devcontainer config. Monorepos define it at the repo root while
# commands run in a service subdir — cwd alone would miss it.
here="$(pwd -P)"
ws=""
sub=0
# builtins only in this loop: it must reach a verdict even on a crippled PATH
d="$here"
while :; do
  if [ -f "$d/.devcontainer/devcontainer.json" ] || [ -f "$d/.devcontainer.json" ]; then
    ws="$d"
    break
  fi
  if compgen -G "$d/.devcontainer/*/devcontainer.json" >/dev/null 2>&1; then
    ws="$d" # spec-legal multi-config layout: usable if running, can't auto-pick to start
    sub=1
    break
  fi
  if [ -e "$d/.git" ] || [ "$d" = "/" ]; then
    break
  fi
  d="${d%/*}"
  [ -n "$d" ] || d="/"
done

# 2) repo doesn't define a devcontainer
[ -n "$ws" ] || exec "$@"

# 3) explicit opt-out
if [ "${ENVRUN_HOST:-}" = "1" ]; then
  exec "$@"
fi

rel="${here#"$ws"}" # e.g. "/services/api", or "" when cwd == workspace folder

# exec inside via the CLI, restoring the relative cwd inside the container
cli_exec() {
  if [ -z "$rel" ]; then
    exec devcontainer exec --workspace-folder "$ws" "$@"
  fi
  exec devcontainer exec --workspace-folder "$ws" \
    bash -c 'cd -- ".$0" && exec "$@"' "$rel" "$@"
}

if ! docker info >/dev/null 2>&1; then
  echo "envrun: repo 定義了 devcontainer，但 Docker daemon 沒在跑（或沒裝 docker）。" >&2
  echo "起 Docker 後重跑；或 ENVRUN_HOST=1 前綴明示改用 host 環境。" >&2
  exit 2
fi

# 4) a container for the workspace folder is already running (VS Code or CLI)
cid="$(docker ps -q --filter "label=devcontainer.local_folder=$ws" | head -n1)"

if [ -n "$cid" ]; then
  if command -v devcontainer >/dev/null 2>&1; then
    cli_exec "$@"
  fi
  # CLI missing but the container runs (VS Code case): docker exec with the
  # container's remoteUser and the mount destination matching the workspace.
  # Known limitation: not a login shell — user-level installs (~/.local/bin)
  # may be off PATH.
  if ! command -v python3 >/dev/null 2>&1; then
    echo "envrun: 找到跑著的 devcontainer，但沒裝 devcontainer CLI，而解析容器資訊需要 host python3（也沒有）。裝其一後重跑。" >&2
    exit 2
  fi
  info="$(docker inspect "$cid" | WS="$ws" python3 -c '
import json, os, sys
c = json.load(sys.stdin)[0]
ws = os.environ["WS"]
dest = next((m["Destination"] for m in c.get("Mounts", []) if m.get("Source") == ws), "")
user = ""
try:
    for entry in json.loads(c["Config"]["Labels"].get("devcontainer.metadata", "[]")):
        if isinstance(entry, dict) and entry.get("remoteUser"):
            user = entry["remoteUser"]
except (KeyError, ValueError, TypeError):
    pass
user = user or c.get("Config", {}).get("User", "")
print(dest + "\t" + user)
')"
  dest="${info%%$'\t'*}"
  cuser="${info#*$'\t'}"
  [ -n "$dest" ] || dest="/workspaces/$(basename "$ws")"
  # shellcheck disable=SC2086
  exec docker exec -w "$dest$rel" ${cuser:+-u "$cuser"} "$cid" "$@"
fi

# 5) not running: start it if the CLI is here (single-config layouts only)
if [ "$sub" -eq 0 ] && command -v devcontainer >/dev/null 2>&1; then
  echo "envrun: devcontainer 沒在跑，現在起（$ws）… 首次 build 會花幾分鐘。" >&2
  devcontainer up --workspace-folder "$ws" >/dev/null
  cli_exec "$@"
fi

# 6) can't proceed without inventing an environment — stop and ask
if [ "$sub" -eq 1 ]; then
  echo "envrun: 這個 repo 用多資料夾 devcontainer 設定（.devcontainer/<名字>/devcontainer.json），envrun 無法自動選一個起。" >&2
  echo "用 VS Code「Reopen in Container」選定設定起容器後重跑；或 ENVRUN_HOST=1 明示改用 host。" >&2
  exit 2
fi
cat >&2 <<'EOF'
envrun: repo 定義了 devcontainer，但沒在跑、也沒裝 devcontainer CLI。選項（轉述給使用者選，不要代跑）：
  1) npm install -g @devcontainers/cli   # 之後重跑，envrun 會自動起容器
  2) 用 VS Code「Reopen in Container」把容器起起來，再重跑
  3) ENVRUN_HOST=1 <原指令>              # 明示同意直接用 host 環境
EOF
exit 2
