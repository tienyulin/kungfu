---
name: agent-rules-setup
description: 幫使用者跑 kungfu 的 skills-sync.sh —— 裝齊 skills、把 agent-rules 憲法與 SAFETY guard 接進其他 agent（Codex/Gemini/Cline/OpenCode）。使用者不需要知道腳本在哪，本 skill 自己找。使用者想安裝團隊 skills、同步到其他 agent、接憲法、設定 agent-rules 時用。Triggers - "接 agent-rules"、"裝團隊 skills"、"同步 skills 到其他 agent"、"setup agent rules"、"sync skills"、"install team skills"、"skills-sync"、"/agent-rules-setup"。
---

# agent-rules-setup

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 找到 skills-sync.sh
- [ ] Step 2 問使用者要哪種模式（除非已明說）
- [ ] Step 3 跑腳本、貼輸出
- [ ] Step 4 回報接了什麼
```

## Step 1 — 找到 skills-sync.sh（依序試，第一個中的就用）

1. `~/.claude/plugins/marketplaces/kungfu/skills-sync.sh`（`marketplace add` 的下載位置，成員機器的常態）
2. 目前專案的 `.claude/skills/skills-sync.sh`（把本 repo 當 submodule 用的專案）
3. 都沒有 → 使用者還沒加 marketplace。給他這條，跑完回到 1：
   ```bash
   claude plugin marketplace add https://gitlab.<公司>/<group>/kungfu.git
   ```
   （實際 URL 見團隊文件；不知道就問使用者，**不要猜**。）

驗證找對了：`bash <路徑> --self-test` 全部 `self-test OK` 才續行；有 FAIL → 貼輸出、停下問。

## Step 2 — 選模式（使用者已講明就跳過，不重複問）

| 使用者想要 | 指令 |
|---|---|
| 全套：Claude plugins ＋ 跨 agent skills ＋ 憲法 ＋ SAFETY guard | `bash <路徑> --constitution` |
| 全套但**不碰**其他 agent 的個人設定檔 | `bash <路徑>` |
| 只把 skills/憲法/guard 同步到其他 agent（不動 Claude plugins） | `bash <路徑> agents --constitution` |

只問一次、給這三個選項。`--constitution` 會寫使用者的個人 dotfile
（`~/.codex/hooks.json`、`~/.gemini/settings.json` 等）——問句要講明這點。

## Step 3 — 跑腳本（機器 gate）

跑選定指令，**貼完整輸出**。輸出裡每行「⚠」都要原文轉述給使用者並解釋下一步；
腳本 exit 非 0 → 貼錯誤原文、停下問，禁止自行重試其他指令。

## Step 4 — 回報

```
DONE: <跑了哪條指令>
WIRED: <輸出裡列到的每個 agent 與其機制，照抄>
SKIPPED/WARNINGS: <⚠ 行原文 - 沒有就寫 none>
NEXT: Claude 端 /reload-plugins 或重啟；其他 agent 重開 session 即生效
```

## 完成定義
- [ ] Step 1 用的是實際存在的路徑（跑過 --self-test 全綠）
- [ ] Step 3 貼了真實輸出，非轉述
- [ ] 警告一條不漏轉給使用者
