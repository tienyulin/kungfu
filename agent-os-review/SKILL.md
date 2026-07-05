---
name: agent-os-review
description: Code review 的固定流程 — 只看真 diff、按正確性>安全>失敗路徑>相容>可維護優先序獵錯、每個 finding 要有具體觸發條件才准回報、一行一 finding、零讚美填充。使用者要 review、檢查程式碼、audit、看一下有沒有問題時用。Triggers - "review"、"幫我看 code"、"檢查一下"、"有沒有問題"、"audit"、"check my code"、"look over"、"/agent-os-review"。
---

# agent-os-review

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

鐵律：只回報 findings，**不動手改**——除非使用者說「fix them」。

```
進度：
- [ ] Step 1 拿到真 diff / 讀完整檔
- [ ] Step 2 按優先序獵錯
- [ ] Step 3 逐條驗證 finding（有具體觸發才留）
- [ ] Step 4 照格式回報 + VERDICT
```

## Step 1 — 拿到真東西

- Review 改動 → 拿實際 diff（`git diff`、PR files）。
- Review 檔案 → 完整讀該檔。
- 禁止根據使用者對程式碼的**描述**做 review。

## Step 2 — 按優先序獵錯（高到低）

1. **正確性** - 邏輯錯、off-by-one、運算子錯、條件反了、漏 await、race、用錯變數
2. **資料損失/安全** - 信任邊界沒驗輸入、injection、密鑰入碼、破壞性操作沒防護、漏 auth 檢查
3. **失敗路徑** - I/O 失敗會怎樣？輸入空/null/0 筆/10^6 筆？被吞掉的 exception？
4. **相容破壞** - API/schema 改動炸到呼叫方——去查誰在呼叫
5. **可維護性** - 只在「會造成真實未來 bug」時列；純品味不列

格式、命名品味、「我會寫不一樣」→ **不是 finding，跳過**。

## Step 3 — 逐條驗證（防假 finding）

每個疑似 bug：重讀周邊程式碼，能不能說出**具體的輸入/狀態**會觸發它？
- 說得出 → 保留。
- 說不出 → 降級成 QUESTION 或直接刪。
假 finding 毀掉 review 公信力，寧缺勿濫。

## Step 4 — 回報（照抄格式，最嚴重排最前）

```
<file>:<line> [CRITICAL|BUG|RISK|QUESTION] <一句話問題>. Trigger: <具體輸入/狀態>. Fix: <一行建議>.
```

結尾只放一行：
```
VERDICT: <safe to merge | fix CRITICAL/BUG items first>
```

- 禁止讚美填充、禁止「overall looks great!」。
- 零 findings 時照抄：「No findings above the bar. Checked: correctness, security,
  failure paths, contracts.」——列出查過什麼，空 review 才可信。

## 完成定義
- [ ] 每條 finding 有 file:line + Trigger + Fix
- [ ] 零改動（除非被要求 fix）
- [ ] 結尾有 VERDICT 一行
