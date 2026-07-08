---
name: dev-test
description: 為既有程式碼補測試的固定流程 —— 列可觀察行為清單、一次寫一條、每條都要 test-the-test（弄壞實作必轉紅）證明會抓錯，防「永綠假測試」。補測試、加 coverage、寫 characterization tests、refactor 前建安全網時用。Triggers - "補測試"、"寫測試"、"加測試"、"加 coverage"、"characterization test"、"write tests"、"add tests"、"/dev-test"。
---

# dev-test

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

鐵律：**沒有 kill-proof 的測試不算測試**——一條測試若「把實作弄壞它還是綠」，
它鎖不住任何行為，只是儀式。

```
進度：
- [ ] Step 0 範圍與 DONE MEANS
- [ ] Step 1 盤點既有測試慣例
- [ ] Step 2 行為清單
- [ ] Step 3 一次一條 + kill-proof
- [ ] Step 4 全套 gate
- [ ] Step 5 報告
```

## Step 0 — 範圍

```
SCOPE: 為 <模組/函式/端點> 補測試
DONE MEANS:
[ ] 行為清單每項有至少一條測試
[ ] 每條測試有 kill-proof（見 Step 3）
[ ] 全套測試套件綠
```
使用者沒指定範圍 → 問一次，附 2-3 個候選（例：最近改動最多的模組、
dev-refactor 指過來的目標）。

## Step 1 — 盤點既有測試慣例

找 repo 的測試框架、目錄結構、命名、fixture 寫法，**抄既有 pattern**。
輸出：`PATTERN: 照 <某測試檔> 的寫法` 。
完全沒有測試框架 → 停，二選一問使用者：pytest（標準）或 plain assert 腳本（零依賴）。

## Step 2 — 行為清單

列要鎖住的**可觀察行為**（輸入 → 輸出/副作用），照抄格式：
```
BEHAVIORS:
1. <正常輸入> → <預期輸出>          （happy path）
2. <空輸入/null/缺值> → <預期>       （edge）
3. <重複提交/邊界值> → <預期>        （edge）
4. <I/O 或依賴失敗> → <預期錯誤行為> （failure path）
```
- 只列**行為**，不列實作細節：private 函式、內部呼叫次數、log 字串——都不測。
- 目的是 refactor 安全網（characterization tests）→ 行為＝「現在實際的行為」，
  照現狀寫，不照理想寫；發現現狀疑似 bug → 記進報告 NOTES，不順手改。

## Step 3 — 一次一條 ＋ kill-proof（機器 gate）

每條測試照這個循環，禁止一次寫完全部再驗：
```
1. 寫一條測試 → 跑 → 必須綠（現行程式碼上）。貼輸出。
2. kill-proof：暫時弄壞對應實作（改掉一個運算子/回傳值），重跑 → 必須紅。貼輸出。
3. 還原實作，重跑 → 回綠。貼輸出。
```
步驟 2 沒紅 ＝ 這條測試抓不到錯 → 重寫斷言，不准留下。
（這就是 dev-loop「overfitting to tests」防呆的來源：測試自己先被測過。）

## Step 4 — 全套 gate

跑完整測試套件（不是只跑新檔），貼結尾統計行。紅 → 修到綠才准報告
（動到的若是既有測試，照 Constitution Law 7：不准弱化，回報原因）。

## Step 5 — 報告（照抄填空）

```
TESTS ADDED: <n 條> @ <測試檔路徑>
BEHAVIORS: <清單各項 → 對應測試名>
KILL-PROOF: <每條一行：弄壞什麼 → 紅輸出關鍵行 → 還原回綠>
SUITE: <全套統計行，逐字>
NOTES: <發現的疑似 bug、假設 - 沒有寫 none>
```

## 完成定義
- [ ] 每條新測試三段輸出齊全（綠→紅→綠）
- [ ] 沒有測實作細節的條目
- [ ] 全套統計行是綠的、逐字貼上
