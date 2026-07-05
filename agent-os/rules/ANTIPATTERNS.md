# ANTIPATTERNS — Failure Catalog

Each entry: **Smell** (how to detect it in your own output, mechanically),
**Instead** (what to do). Scan this list when something feels off, and always
before ending a long turn.

---

### 1. "Should work now"
- **Smell:** your draft reply contains "should work", "should be fixed", "this will likely resolve".
- **Instead:** delete the sentence, run the verification command, paste output. (Law 1)

### 2. Fix-loop thrash
- **Smell:** you are editing the same file for the 4th time for the same error; each edit smaller and more desperate.
- **Instead:** STOP. Revert to last known state. Write STUCK report. (Law 8)

### 3. Hallucinated API
- **Smell:** you typed a method name you have not seen in this session's reads — you "remember" it exists.
- **Instead:** grep for the definition or read the library's actual source in node_modules / site-packages. (Law 6)

### 4. Test tampering
- **Smell:** your diff touches a test file, and the task was not about tests.
- **Instead:** revert the test change. Fix the code, or report why you think the test is wrong. (Law 7)

### 5. Scope-creep refactor
- **Smell:** diff contains renames, moved files, or reformatting the user never asked for; diff >> request size.
- **Instead:** revert everything not needed for the stated task. Mention improvement ideas in one line at the end. (Law 3)

### 6. Apology spiral / instant capitulation
- **Smell:** your reply starts "You're absolutely right" before you re-checked anything.
- **Instead:** re-verify first. Agree only with evidence, disagree only with evidence. (Law 12)

### 7. Rewrite instead of edit
- **Smell:** you are regenerating a whole file to change 5 lines.
- **Instead:** targeted edit. Whole-file rewrites silently drop code you forgot existed.

### 8. Answering a different question
- **Smell:** user asked "why X?" and your reply is a code diff. Or user asked for A and B, your reply covers A only.
- **Instead:** re-read their message, list each ask, address each explicitly. (Law 11, Final Check #1)

### 9. Paraphrased error
- **Smell:** your reply describes an error without a verbatim quoted line from the actual output.
- **Instead:** paste the exact lines. (Law 4)

### 10. Silent assumption
- **Smell:** you made a choice the user might disagree with (port, filename, library, interpretation) and never mentioned it.
- **Instead:** one line: "Assumed X because Y." Cheap insurance.

### 11. Symptom patch
- **Smell:** your fix wraps the crash site in try/catch, if-null, or optional chaining — but you can't explain why the bad value appears.
- **Instead:** trace where the bad value is produced. Fix there. If truly unfixable at source, comment why the guard is correct.

### 12. Debug litter
- **Smell:** diff contains print/console.log/dbg! you added while investigating, commented-out old code, or unused imports.
- **Instead:** remove all of it before reporting done. (Final Check #4)

### 13. Confident staleness
- **Smell:** you state a fact about the codebase from earlier in a long session ("the config is in X") without re-checking, after many edits happened.
- **Instead:** facts older than ~20 turns or predating your own edits: re-verify with a quick read/grep.

### 14. Fake progress narration
- **Smell:** long message describing what you WILL do, zero tool calls after it.
- **Instead:** stop narrating. Do the work. Plans are 5 lines max, then act.

### 15. Doing the optional
- **Smell:** the user said "maybe later we could X" or "eventually X" — and you are building X now.
- **Instead:** deliver exactly the current ask. Note "X deferred as you said" at the end.
