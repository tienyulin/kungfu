---
name: agent-rules-feature
description: 加新功能的固定流程 — 先寫可驗收清單再寫碼、抄既有 pattern、做最小版本、逐項驗證。任何新增功能、新端點、新指令、新元件、「讓它能做 X」的任務都用。Triggers - "加功能"、"新增"、"實作"、"做一個"、"支援 X"、"add"、"build"、"implement"、"create"、"support"、"/agent-rules-feature"。
---

# agent-rules-feature

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 驗收清單（寫碼前）
- [ ] Step 2 找既有 pattern
- [ ] Step 3 最小版本實作
- [ ] Step 4 逐項驗證
- [ ] Step 5 完成報告
```

## Step 1 — 驗收清單先行（禁止先寫碼）

照格式寫：
```
DONE MEANS:
[ ] <可觀察行為 1>
[ ] <可觀察行為 2>
[ ] 既有測試全過
```
每一項都必須「跑某個東西就能檢查」；「程式碼乾淨」不是合格項目。
從需求寫不出清單 → 問**一個**問題並附 2-3 個具體選項，停下等回覆。

## Step 2 — 找既有 pattern

在 codebase 搜最相似的既有功能（相似 route、指令、元件），完整讀它。
輸出（二選一）：
- `PATTERN: copying the shape of <file>`
- `PATTERN: none found, using <做法>`

照既有形狀寫勝過自創更好的形狀。一致性 > 聰明。

## Step 3 — 最小版本

- 新 dependency：先提案＋附 stdlib 替代方案，問過才加。
- 沒人要求的 config/選項/抽象：不寫。
- 預設要處理的 edge cases：空輸入、null/缺值、重複提交、每個 I/O 呼叫的失敗路徑。
  「處理」＝明確行為，不是 silent swallow。
- 呼叫任何本 session 沒讀過的 API 前：先找到定義或文件；找不到就明說並去查。

## Step 4 — 逐項驗證（機器 gate）

清單**每一項**都跑一個東西驗證，在項目旁標指令＋結果打勾。
沒打勾的項目＝功能沒完成，照實說。
只准回報實際執行過的驗證並附輸出；沒跑的寫「未跑」。

## Step 5 — 完成報告（照抄填空）

```
ADDED: <一句話>
DONE MEANS:
[x] <項目> - VERIFIED: <指令> → <結果>
[x] <項目> - VERIFIED: <指令> → <結果>
FILES: <清單>
SKIPPED: <刻意沒做的 + 何時該補 - 沒有就寫 nothing>
```

## 完成定義
- [ ] 清單在寫碼前就存在
- [ ] 每項驗收有指令＋輸出
- [ ] 沒加未經同意的 dependency/抽象
