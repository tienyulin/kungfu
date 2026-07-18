---
name: sop-to-spec
description: Convert an operations SOP (any domain — DBA runbooks, infra procedures, deployment checklists) into an API spec that BOTH a human approver can read and an AI agent can implement a three-layer FastAPI service from. Triggers - "SOP 轉 spec", "convert SOP", "/sop-to-spec <path>", or when the user wants to turn a procedure document into an API.
---

# SOP → Implementation Spec

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 萃取五清單（草稿）
- [ ] Step 2 風險分級表
- [ ] Step 3 spec 寫完（先 Part A 後 Part B；照抄區塊逐字；逼問清單每題每端點過完）
- [ ] Step 4 自檢清單全勾
- [ ] Step 5 盲審 spawn（prompt 照抄）→ 分流 → REVIEWS.md → HIGH=0
- [ ] （實作發生後）Step 6 歸因
```

把人類操作 SOP 轉成一份 API spec。spec 有**兩個讀者，缺一不可**：

| 讀者 | 需要什麼 | spec 對應部分 |
|------|---------|--------------|
| **人類審批者** | 白話看懂這 API 做什麼、風險在哪、哪些不自動化 | **Part A 審批摘要**（先寫，放最前面） |
| **實作 agent** | 零猜測的精確規格（驗收準則、schema、mock 狀態） | **Part B 實作規格** |

三條鐵律：

1. **spec 是唯一交接物** —— 實作 agent 只讀 spec，不回讀 SOP；SOP 裡實作需要的資訊全部 inline
2. **自足** —— 禁止引用 SOP 與自身以外的檔案/慣例（「比照 xxx 服務」不行），全新 repo 也要能照 spec 開工
3. **未定義行為 = spec 的 bug** —— 實作中發現就回報修 spec，不是 code 自由發揮

## 輸入 / 輸出 / 語言

- 輸入：SOP 檔案路徑（`$ARGUMENTS` 或使用者指定；檔案不存在就停下問，不要猜路徑）。
  SOP 由不懂技術的人（PM）寫的 → 先請他照 [references/sop-authoring-guide.md](references/sop-authoring-guide.md)
  ＋空白骨架 [references/sop-template.md](references/sop-template.md) 填，SOP 品質夠了再轉 spec
- 輸出：`specs/<sop-slug>-api.spec.md`（`specs/` = SOP 所在 repo 根下，不存在就建）；
  `<sop-slug>` = SOP 檔名去副檔名
- 語言：spec 跟 SOP 同語言（審批者讀 SOP 的語言 = 讀得懂 Part A 的語言）；拿不準就問使用者。
  所有「照抄」素材（模板區塊、盲審/實作 spawn prompt、REVIEWS.md 表頭）**可整塊翻譯成
  spec 語言**（翻譯 ≠ 改寫；不得增刪條目、改順序、改語意）

**產 spec 途中發現 SOP 缺資訊**（沒有錯誤碼表、回退步驟不明…）：先分辨缺的是哪種——
**業務判斷**（危險分級、失敗處理、成功判準）只有寫 SOP 的人知道 → 回
[references/sop-authoring-guide.md](references/sop-authoring-guide.md) 的對應欄請他補；
**系統機械面**（登入、格式驗證、冪等、並發、None 行為）→ 照 §0 自補，不必回問 PM。
能問使用者就問；不能問就在 spec 開頭「未決事項」節列出假設與依據 —— 但 irreversible 操作的關鍵參數
（confirm 條件、審批要求）**不得自行發明**，一律留在未決事項等人補。未決事項的
**暫行假設一律取更嚴的方向**（審計/防護寧多勿少，例：SOP 說「變更單號必填」但範圍
不明 → 暫行值 = 全部 mutation 必填，等人放寬）。

## 流程（六步，依序）

| Step | 做什麼 | 細節 |
|------|--------|------|
| 1 萃取 | 讀 SOP 列五張清單：查詢類→GET、變更類→POST/PUT/PATCH/DELETE（依語意）、前置條件、錯誤對照表、審計欄位。清單是工作草稿，不進 spec | — |
| 2 風險分級 | 每個操作分 `read` / `reversible` / `irreversible`（SOP 有「警告/需審批/無法復原」→ 一律 irreversible） | [references/spec-template.md](references/spec-template.md) §風險分級 |
| 3 產 spec | 先寫 Part A（給人），再照模板填 Part B（給 agent），逐端點過完逼問清單 | 模板：[references/spec-template.md](references/spec-template.md)；逼問清單：[references/checklists.md](references/checklists.md) |
| 4 自檢 | 跑完自檢清單（含 fresh-repo 測試、Part A 白話測試） | [references/checklists.md](references/checklists.md) |
| 5 盲審閘門 | 用 subagent 機制 spawn 一個乾淨 context 的 subagent 盲審 spec（完整 prompt 與隔離規則見 checklists）；**HIGH > 0 不准寫 code**；發現與處置記入 `specs/REVIEWS.md`（格式見 checklists） | [references/checklists.md](references/checklists.md) |
| 6 實作回饋 | 實作階段發現缺陷 → 歸因（SOP/skill/spec/code）修對應層，不是只修 code | [references/checklists.md](references/checklists.md) §歸因表 |

## 本 skill 的邊界

**本次呼叫交付到「spec 通過盲審」為止（Step 1–5）。** 實作是另一件事：本 agent 已讀
SOP，自己實作會違反鐵律 1。使用者要求實作時，用 subagent 機制 spawn 新 agent
（Claude Code 是 Agent 工具；其他 agent 用各自的 sub-task／subagent 功能），prompt
**整段照抄**（`<spec 路徑>` 換掉）：

> 你是實作 agent。**唯一的規格來源是 `<spec 路徑>`，先完整讀它。禁止讀 SOP、
> 其他 spec 或任何「參考既有做法」—— spec 沒寫的就是沒定義。** 照 spec §10 的
> 交付要求實作；實作中發現 spec 未定義的行為，停下來回報該處，不要自行發明。

實作交付要求（三層式 FastAPI、mock、README、未定義行為回報義務）已寫在 spec 模板
§10，spec 自帶。Step 6 在實作發生後才觸發。
