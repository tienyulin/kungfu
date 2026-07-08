---
name: dev-loop
description: 一個 coding 需求的端到端自主迭代圈（goal-based loop）—— 先判斷需不需要開圈，intent 鎖定一次、機器 gate 確立後，agent 自己繞「做→觀察→調整」直到 gate 全綠才開 PR，中途不再問人；審查交給 fresh-context reviewer，重複失敗編回系統，卡住走三振升級而不是無限重試。使用者丟一個完整需求要 agent 自己做到好、不想逐步下指令時用。Triggers - "跑 loop"、"自己做到好"、"做到測試過"、"一路做到 PR"、"run the loop"、"loop this"、"/dev-loop <需求>"。
---

# dev-loop

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

心智模型：人設計圈（目標、gate、停止規則），你繞圈。**gate 的失敗輸出不是錯誤
訊息，是下一輪的新 context。** 出圈只有三種方式：全綠、三振升級、預算耗盡。

定位：這是 **goal-based loop**——觸發＝一個完整需求，停止＝DONE MEANS 全綠或輪數
上限。圈本身有成本，不是每個需求都需要（Step 0 先判斷）。Claude Code 使用者另有
原生 `/goal` 可把同一份 DONE MEANS 掛成外部 evaluator（防提前收工），與本 skill
可疊加；本 skill 是不挑 agent 的可攜實作。

```
進度：
- [ ] Step 0 規模判斷 + Intent 鎖定（DONE MEANS 清單）
- [ ] Step 1 Gate 確立（含來源標注）
- [ ] Step 2 內圈執行（路由 playbook；批量先 pilot）
- [ ] Step 3 迭代圈（RUNLOG 逐輪）
- [ ] Step 4 審查（fresh-context reviewer 優先）
- [ ] Step 5 交付（branch → PR）
- [ ] Step 6 報告 + 系統回饋
```

## Step 0 — 規模判斷 + Intent 鎖定（圈內唯一一次可以問人的機會）

**先選對工具**（成本要配需求，二分流）：
- 需求一眼可解（改動 ≤2 檔、驗證指令明顯、預期一輪內全綠）→ **不開圈**。寫一行
  `NO LOOP: 單回合可完成`，直接照對應 playbook 做完＋驗證交付。做到一半發現低估
  （第一次 gate 紅）→ 回到這裡補齊 DONE MEANS 正式進圈。
- 其餘（預期多輪迭代、跨多檔、行為驗證複雜）→ 進圈，往下走。

寫出：
```
INTENT: <需求一句話>
DONE MEANS:
[ ] <可觀察行為 1 - 有指令可驗>
[ ] <可觀察行為 2>
[ ] <至少一項「非測試」觀察 - 實際跑起來看行為，防 overfitting to tests>
[ ] 既有測試全過
LOOP BUDGET: <上限輪數，預設 5>
```
每項寫成**量化判準**（exit code、數字門檻、統計行、HTTP 狀態）——判準越量化，
你越無從對自己放水。從需求寫不出 DONE MEANS → 問使用者**一次**（附 2-3 個具體選項）。
此後**圈內不再問人**——遇到歧義照 DECISIONS 表 1（便宜的選簡單解並標注 Assumed）。

## Step 1 — Gate 確立（observation 的來源，優先序取第一個成立的）

1. 使用者明講的驗證指令。
2. repo root 的 `VERIFY.md`（格式見 [references/verify-format.md](references/verify-format.md)）。
3. 從 CI 設定／Makefile／package.json／pyproject 推導。

輸出（來源必標）：
```
GATES:
- <名稱>: `<指令>` （來源: user | VERIFY.md | 推導自 <檔案>）
```
推導不出任何 gate → 停，問一次「這個 repo 怎麼驗？」。**沒有 gate 就沒有圈。**

## Step 2 — 內圈執行

照需求型路由（同 DECISIONS 表 5）：修壞的 → `dev-bugfix`；加新的 → `dev-feature`；
整理 → `dev-refactor`；補測試 → `dev-test`。輸出（必填，先寫再動手）：
```
ROUTE: <playbook 名> （原因: <需求屬於哪型，一句>）
```
照該 playbook 的步驟做出**第一版**。
禁止跳過 playbook 自由發揮——「怎麼做」是它們的事，本 skill 只管「圈」。

兩條 token 紀律（進圈前定好，圈內照做）：
- **批量先 pilot**：需求是同 pattern 重複多處（migration、批次改寫）→ 先挑 1-2 處
  代表樣本走完一輪 Step 3 全綠，確認做法對了再放大到全部。禁止第一輪就全面鋪開。
- **確定性步驟寫成 script**：每輪都要重複的機械步驟（產測資、格式轉換、批次替換）
  → 第一輪就寫成 script 之後每輪跑它——跑 script 比每輪重新推理便宜也穩定。

## Step 3 — 迭代圈（核心）

```
每一輪：
1. 跑全部 GATES，貼逐字輸出。
2. 全綠 → 出圈，去 Step 4。
3. 有紅 → 失敗輸出＝新 context：
   a. 逐字引用關鍵錯誤行（Constitution Law 4）。
   b. 寫一行新假設；一次只改一個東西（Law 5），沒效先 revert。
   c. 同一個障礙（同一 gate 同類錯誤）第 3 次紅 → 出圈，走 LOOP ESCALATED（Law 8）。
   d. 輪數用完（LOOP BUDGET）→ 出圈，走 LOOP ESCALATED。
4. 每輪結束 append 一行 RUNLOG（照抄格式）：
   ROUND n/N | hypothesis: <一句> | change: <檔案:行 或 revert> | gates: <綠/紅 哪個>
```

每輪自檢一眼 [references/loop-failure-modes.md](references/loop-failure-modes.md) 的
四種氣味（thrash／overfit／drift／unsafe）——中了照表處置。

## Step 4 — 審查（fresh context 優先）

二分流：
- **有 subagent 能力**（如 Claude Code 的 Agent tool）→ spawn 一個獨立 reviewer：
  只給它 diff＋DONE MEANS＋`dev-review` 的獵錯優先序，**不給你的推理過程與 RUNLOG**
  ——fresh context 的 reviewer 不會被你的假設帶著走，抓得到你自己看不到的盲點。
- **沒有** → 自審 fallback：照 `dev-review` 優先序（correctness > 資料損失/安全 >
  失敗路徑 > breaking change）掃自己的 diff。

發現 finding → 回 Step 3 再繞（算輪數）。零 finding → 續行。

## Step 5 — 交付

branch → commit → PR（**永不直推 main**）。PR body 必含：
DONE MEANS 逐項打勾（各附指令＋結果）、GATES 最終綠輸出逐字、完整 RUNLOG。

## Step 6 — 報告 + 系統回饋（照抄填空，二選一）

```
LOOP DONE: <需求> | ROUNDS: n/N | GATES: <最終綠輸出關鍵行> | PR: <url>
SYSTEM FEEDBACK: none 或 <提案一句>
```
```
LOOP ESCALATED: <卡點一句話>
TRIED: <RUNLOG 全文>
ERROR (逐字): <最後一輪失敗輸出>
BEST HYPOTHESIS: <目前最佳猜測>
NEED FROM YOU: <一個具體問題>
SYSTEM FEEDBACK: none 或 <提案一句>
```
升級是成果不是失敗（Constitution Law 8）——絕不用第 6 輪硬凹。

**系統回饋規則**：RUNLOG 裡**同類失敗出現 ≥2 輪** → 不要只修那一次——提案把它
編進系統讓之後每個圈受惠：一條新 gate 進該 repo 的 `VERIFY.md`，或一條 antipattern
／慣例註記。**只提案**（寫進報告與 PR body），不擅自改共用規則檔。

## 完成定義
- [ ] Step 0 規模判斷有寫（NO LOOP 或進圈，二選一）
- [ ] Step 0 之後沒有再問過人（或有標注 Assumed）
- [ ] 每輪 RUNLOG 都在，gate 輸出全逐字
- [ ] 審查走過獨立 reviewer，或標明 fallback 自審
- [ ] 出圈方式是三種合法之一，報告用對應模板
- [ ] PR body 含 DONE MEANS 打勾＋RUNLOG（DONE 路徑）
- [ ] SYSTEM FEEDBACK 有寫（none 也要寫）
