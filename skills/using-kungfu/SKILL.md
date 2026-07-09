---
name: using-kungfu
description: Use at the very start of any task to reach for the right kungfu skill before acting — check the available skills, invoke the one that matches, and follow it exactly. This is skill-usage discipline; it complements (does not repeat) the agent-rules constitution, which covers work discipline. Triggers - "開始任務"、"動手前"、"start a task"、"before I begin"、任何 coding/文件/除錯任務開頭。
---

# Using kungfu skills

You have **kungfu** installed: a set of skills (fixed, fill-in procedures) plus —
separately, injected at session start via a hook — the **agent-rules constitution**
(12 hard laws of work discipline). This skill is about *reaching for the skills*.

## The rule

Before acting on a task, **look at the skills you actually have and check whether one
fits.** If one plausibly does (even a ~1% chance), **invoke it and follow it exactly** —
announce `Using <skill> to <purpose>`, then do one step at a time. Process skills run
before implementation skills.

## Find the skill — read your live list, don't guess

Your harness already surfaces every installed skill by name + description (in your skill
tool / skills list). **Scan that list and match by description** — it is the source of
truth, not any list written here. It includes:

- **kungfu's own** — coding procedures (`dev-bugfix` reproduce→root cause→minimal
  fix→verify, `dev-feature`, `dev-refactor`, `dev-investigate`, `dev-review`, `dev-test`
  kill-proof tests, `dev-loop` whole-requirement autonomous loop) and authoring skills
  (`wiki-doc-author`, `sop-to-spec`, `skill-author`, `dev-api-template`).
- **anything installed alongside kungfu** — external skill sets (e.g. superpowers,
  karpathy) dropped into the same skills dir show up in the SAME list. Reach for those
  too; don't assume kungfu's are the only skills you have.

## Red flags — stop and pick a skill

"This is simple, I'll just do it" · "Let me explore the code first" · "I remember how
that skill goes" · "The user only asked a quick question". If a matching skill exists,
these are rationalizations — use the skill.

## Boundaries

- **User instructions and the constitution win** over this skill.
- This is *skill-usage* discipline. Work discipline (evidence before claims, minimal
  diff, reproduce before fix, three-strike stop) lives in the constitution — don't
  restate it here; both are active together.
