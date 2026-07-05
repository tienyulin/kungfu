---
name: agent-rules-investigate
description: 回答問題/調查的固定流程 — 交付物是帶 file:line 證據的答案，不是程式碼改動；答案附信心等級，查到的問題只回報不修。使用者問為什麼、怎麼運作、在哪裡、安不安全、查一下時用。Triggers - "為什麼"、"怎麼運作"、"在哪裡"、"查一下"、"看一下是不是"、"why"、"how does"、"explain"、"where is"、"is it safe"、"find out"、"/agent-rules-investigate"。
---

# agent-rules-investigate

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

鐵律：交付物是**答案**，不是改動。**禁止編輯任何檔案。**

```
進度：
- [ ] Step 1 分類問題（三選一）
- [ ] Step 2 蒐證（讀真碼/跑真指令）
- [ ] Step 3 照模板作答
- [ ] Step 4 停（不順手修）
```

## Step 1 — 分類問題（三選一）

| 類型 | 判別 | 答案需要什麼 |
|---|---|---|
| 事實型 | 「X 在哪 / X 是什麼」 | file:line 證據 |
| 行為型 | 「如果 Y 會發生什麼」 | 最好：實際跑一次；次好：讀完整程式路徑 |
| 判斷型 | 「這樣好嗎 / 安全嗎 / 夠快嗎」 | 判準 + 證據 + 一個明確建議 |

三類都不像 → 問使用者想知道什麼，停。

## Step 2 — 蒐證

讀實際程式碼、跑實際指令。「這框架通常怎樣」是假設不是證據。
答案裡每個宣稱都要能追到**本 session 讀過或跑過**的東西。

## Step 3 — 作答（照抄填空）

```
ANSWER: <直接答案 1-2 句 - 放最前面>

EVIDENCE:
- <file:line> - <它顯示什麼>
- <指令> → <輸出關鍵行> - <它顯示什麼>

CONFIDENCE: <verified | read-but-not-run | partly inferred>  <什麼能再提高信心>
```

品質判準：使用者問「為什麼」，答案必須有一個由 file:line 或輸出撐腰的 BECAUSE。
只有合理故事、沒有證據 → 必須標注「hypothesis, unverified」。

## Step 4 — 停

查案中發現的問題**不修**。照格式回報後結束回合，等使用者指示：
```
FOUND WHILE LOOKING: <file:line> - <問題>. Want me to fix it?
```

## 完成定義
- [ ] 零檔案編輯
- [ ] ANSWER 在最前、EVIDENCE 每條有出處、CONFIDENCE 有標
- [ ] 發現的問題只回報未修
