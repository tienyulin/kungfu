# VERIFY.md 慣例 — repo 的「怎麼驗」寫成機器可發現

每個 repo root 放一份 `VERIFY.md`，dev-loop（與任何 agent）就不用人教怎麼驗。
格式：一個 gate 一節，**指令要可直接複製執行**，通過判準要可觀察。

```markdown
# VERIFY

## unit
- run: `<測試指令，例如 pytest -q>`
- pass: exit 0，結尾統計行無 failed

## lint
- run: `<lint 指令>`
- pass: exit 0

## smoke（非測試觀察 — 防 overfitting to tests）
- run: `<啟動/呼叫一次真行為的指令，例如 curl 健康檢查>`
- pass: <可觀察判準，例如 HTTP 200 且 body 含 "ok">
```

規則：
- 至少一個 `unit` 類 gate＋至少一個 `smoke` 類（非測試觀察）。
- 通過判準越**量化**越好（exit code、數字門檻、統計行、HTTP 狀態）——量化判準
  agent 才能自驗，無從放水。
- 指令假設在 repo root 執行；要環境（container/env var）就把前置寫進 run 裡。
- 改了驗證方式 → 同 PR 更新 VERIFY.md（清單即真相）。
