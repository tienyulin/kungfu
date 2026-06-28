#!/usr/bin/env python3
"""Offline skill validator — pure stdlib, no deps, no network.

Checks each skill against the Agent Skills spec + this repo's conventions, and
that it's registered in .claude-plugin/marketplace.json. Replaces the external
`skills-ref` tool so it works on an air-gapped intranet.

Usage (from repo root):
  python skill-author/scripts/validate_skill.py            # all skills + marketplace
  python skill-author/scripts/validate_skill.py <skill>    # one skill dir
"""

import json
import os
import re
import sys

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")  # kebab, no leading/trailing/consecutive hyphen
MAX_NAME = 64
MAX_DESC = 1024
MAX_LINES = 500
SKIP = {"template", "scripts", "references", "assets", ".git", ".claude-plugin"}


def _frontmatter(path):
    """Tiny YAML-subset parse of the leading --- block: top-level 'key: value'."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.startswith("---"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm = {}
    for line in text[3:end].splitlines():
        if ":" in line and not line.startswith((" ", "\t", "#")):
            k, v = line.split(":", 1)
            fm[k.strip()] = v.strip().strip('"').strip("'")
    body = text[end + 4 :]
    return fm, body


def _check_name(skill_dir, name, name_dir):
    """Validate the frontmatter name against the kebab/length/dir-match rules."""
    if not name:
        return [f"{skill_dir}: frontmatter 缺 name"]
    errs = []
    if not NAME_RE.match(name):
        errs.append(f"{skill_dir}: name '{name}' 須 kebab-case（小寫英數+單連字號）")
    if len(name) > MAX_NAME:
        errs.append(f"{skill_dir}: name >{MAX_NAME} 字")
    if name != name_dir:
        errs.append(f"{skill_dir}: name '{name}' != 目錄名 '{name_dir}'")
    return errs


def _check_desc(skill_dir, desc):
    """Validate the frontmatter description; returns (errs, warns)."""
    if not desc:
        return [f"{skill_dir}: frontmatter 缺 description"], []
    if len(desc) > MAX_DESC:
        return [f"{skill_dir}: description >{MAX_DESC} 字"], []
    if "Triggers -" not in desc and "Triggers-" not in desc:
        return [], [f"{skill_dir}: description 建議用 `Triggers -` 標籤列觸發句"]
    return [], []


def validate_skill(skill_dir):
    """Validate one skill dir against the spec; returns (errs, warns)."""
    warns: list[str] = []
    name_dir = os.path.basename(skill_dir.rstrip("/"))
    md = os.path.join(skill_dir, "SKILL.md")
    if not os.path.isfile(md):
        return [f"{skill_dir}: 缺 SKILL.md"], warns
    fm, body = _frontmatter(md)
    errs = _check_name(skill_dir, fm.get("name", ""), name_dir)
    desc_errs, desc_warns = _check_desc(skill_dir, fm.get("description", ""))
    errs += desc_errs
    warns += desc_warns
    n = body.count("\n") + 1
    if n > MAX_LINES:
        warns.append(f"{skill_dir}: SKILL.md body {n} 行 > {MAX_LINES}，考慮拆進 references/")
    return errs, warns


def _check_marketplace(root, skills):
    """Check every skill is registered in marketplace.json and paths resolve; returns errs."""
    mp = os.path.join(root, ".claude-plugin", "marketplace.json")
    if not os.path.isfile(mp):
        return []
    try:
        with open(mp, encoding="utf-8") as f:
            m = json.load(f)
    except (OSError, json.JSONDecodeError) as ex:
        return [f"marketplace.json 不是合法 JSON: {ex}"]
    errs = []
    registered = set()
    for p in m.get("plugins", []):
        for sp in p.get("skills", []):
            registered.add(sp.lstrip("./").rstrip("/"))
            if not os.path.isfile(os.path.join(sp, "SKILL.md")):
                errs.append(f"marketplace plugin '{p.get('name')}': skills 路徑 {sp} 無 SKILL.md")
    for s in skills:
        if s not in registered:
            errs.append(f"{s}: 未註冊進 marketplace.json（加一個 plugin + 進 bundle）")
    return errs


def main(argv):
    """Validate all skills (or one named dir) + marketplace registration; return exit code."""
    root = os.getcwd()
    errs, warns = [], []

    if len(argv) > 1:
        skills = [argv[1].rstrip("/")]
    else:
        skills = [
            d
            for d in sorted(os.listdir(root))
            if os.path.isdir(d) and d not in SKIP and os.path.isfile(os.path.join(d, "SKILL.md"))
        ]

    for s in skills:
        e, w = validate_skill(s)
        errs += e
        warns += w

    # marketplace registration (only on a full run from repo root)
    if len(argv) <= 1:
        errs += _check_marketplace(root, skills)

    for w in warns:
        print(f"  ⚠ {w}")
    if errs:
        for e in errs:
            print(f"  ✗ {e}")
        print(f"\n{len(errs)} 個錯誤。")
        return 1
    print(f"validate: OK（{len(skills)} skill{'s' if len(skills) != 1 else ''}）")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
