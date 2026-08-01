#!/usr/bin/env python3
"""README 地標存在性檢查（anchor lint）。

抽出 markdown 裡 backtick 的兩類地標，逐一驗證，防文件過期：
  1. 路徑（含 "/" 或指向現存檔名的 token）→ 必須存在於 repo
  2. ENV_NAME（全大寫底線字）→ 必須在 repo 的程式/設定檔裡 grep 得到

用法：python3 lint_anchors.py README.md [其他.md ...] [--repo-root PATH]
綠 = exit 0；有失效地標 = exit 1 並逐條列出。
跳過單行：該行加上 anchors-skip（例如放在行尾註解）。
純 stdlib。
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

BACKTICK = re.compile(r"`([^`\n]+)`")
ENV_NAME = re.compile(r"^[A-Z][A-Z0-9_]{2,}$")
# 長得像路徑：含 / 且只有路徑常見字元；或單一檔名帶副檔名
PATHISH = re.compile(r"^[\w.\-/]+$")
# 行號引用（「行 149–158」「line 42」「lines 10-20」）——會爛，禁用
LINE_REF = re.compile(r"(第?\s?行\s?\d+|\d+\s?行|lines?\s+\d+)", re.IGNORECASE)
SKIP_MARK = "anchors-skip"

# 不當地標驗的 token：佔位符、URL、指令、glob
def is_placeholder(tok: str) -> bool:
    # "/" 開頭＝slash command 或絕對路徑，不是 repo 相對地標
    return any(c in tok for c in "<>*$ {}|") or tok.startswith(("http", "/"))


def iter_tokens(md_text: str):
    in_fence = False
    for line in md_text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or SKIP_MARK in line:
            continue  # 圍欄內是指令/範例輸出，不當地標
        for tok in BACKTICK.findall(line):
            yield tok.strip()


def env_greppable(name: str, root: Path) -> bool:
    try:
        r = subprocess.run(
            ["git", "grep", "-l", "--fixed-strings", name],
            cwd=root, capture_output=True, text=True, timeout=30,
        )
        if r.returncode in (0, 1):
            return r.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        pass
    # 非 git repo 的 fallback：走檔案（限常見文字檔，防大 repo 掃太久）
    exts = {".py", ".ts", ".js", ".go", ".java", ".rb", ".sh", ".yml", ".yaml",
            ".toml", ".ini", ".env", ".cfg", ".json", ".md", ".txt", ".tf"}
    for p in root.rglob("*"):
        if p.is_file() and p.suffix in exts and ".git" not in p.parts:
            try:
                if name in p.read_text(errors="ignore"):
                    return True
            except OSError:
                continue
    return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--repo-root", default=".")
    args = ap.parse_args()
    root = Path(args.repo_root).resolve()

    failures = []
    for f in args.files:
        md = Path(f)
        text = md.read_text(encoding="utf-8")
        in_fence = False
        for i, line in enumerate(text.splitlines(), 1):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if not in_fence and SKIP_MARK not in line and LINE_REF.search(line):
                failures.append(f"{md}:{i}: 行號引用（會爛，改用符號名）→ {line.strip()[:60]}")
        seen = set()
        for tok in iter_tokens(text):
            if tok in seen or is_placeholder(tok):
                continue
            seen.add(tok)
            if "/" in tok and PATHISH.match(tok):
                if not (root / tok).exists():
                    failures.append(f"{md}: 路徑不存在 → `{tok}`")
            elif ENV_NAME.match(tok):
                if not env_greppable(tok, root):
                    failures.append(f"{md}: repo 裡 grep 不到 → `{tok}`")

    if failures:
        print("anchor lint FAIL：以下地標失效（文件過期或寫錯）")
        for line in failures:
            print("  " + line)
        return 1
    print("anchor lint OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
