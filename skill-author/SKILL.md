---
name: skill-author
description: 在這個 ai-agent-skills repo 裡新增或修改一個 Claude Code skill，並讓它可被安裝。照官方 Agent Skills spec + 本 repo 慣例產出合規 SKILL.md、scripts/references，並註冊進 .claude-plugin/marketplace.json。開發者想加/改 skill 時用。Triggers - "寫一個 skill"、"新增 skill"、"author a skill"、"add a skill to ai-agent-skills"、"/skill-author"。
---

# skill-author

教 agent 在本 repo 新增一個**可安裝**的 skill。一份讀完就能做（自包含）；完整人類版規範另見 repo 根的
`CONTRIBUTING.md`，但照本檔做即可。

> 心智模型：一個 skill = 一個資料夾（`<name>/SKILL.md` + 選填 `scripts/`/`references/`/`assets/`）放在
> **repo root**，再在 `.claude-plugin/marketplace.json` 註冊成 plugin。安裝走 `/plugin install`。

## Step 1 — 命名 + 建目錄
- `name`：kebab-case、≤64 字、只小寫英數+連字號、不可頭尾/連續連字號、**須等於目錄名**。
- `mkdir <name>`（在 repo root），裡面放 `SKILL.md`（＋需要時 `scripts/`、`references/`）。

## Step 2 — 寫 SKILL.md（frontmatter + body）
frontmatter（官方欄位）：
```yaml
---
name: <name>                 # = 目錄名
description: <做什麼 + 何時用 + 觸發詞>。Triggers - "<中文觸發>"、"<english>"、"/<name>"。
# 選填：license、compatibility（≤500，僅特殊環境需求才寫）、metadata（版本不放這，見 Step 4）
---
```
- **description（最關鍵）**：≤1024 字，講 *what + when*，**第三人稱、稍微 pushy**（Claude 易 under-trigger），
  結尾統一 `Triggers -` 列具體中英觸發句。它決定 skill 會不會被選中。
- **body**：≤500 行 / <5000 tokens。寫到讀完即可執行 —— 決策樹/步驟、輸入輸出範例、邊界、完成定義。
  - 太長 → 拆進 `references/`（agent 需要才載）；引用用**相對路徑、只深一層**（`references/X.md`），不要 `../`、不要深鏈。
  - **prose 用中文**，專有名詞英文＋首次出現一句解釋。
- **scripts/**（若需工具）：**純 stdlib、零相依**、錯誤訊息清楚；安裝時隨 plugin 複製，**不可引用 skill 目錄外**的檔。

## Step 3 — 自包含檢查
skill 不靠 repo 其他檔也能運作（工具在自己的 `scripts/`、細節在自己的 `references/`）。不要互相指來指去。

## Step 4 — 註冊進 marketplace（**必做，否則裝不到**）
編輯 `.claude-plugin/marketplace.json`：在 `plugins` 陣列加一個項目，**並**把 `"./<name>"` 加進 bundle
plugin `ai-agent-skills` 的 `skills`：
```jsonc
{
  "name": "<name>",
  "source": "./",
  "strict": false,
  "description": "...",
  "author": { "name": "tienyulin" },           // 不設 version → 每次 commit 自動算新版（用 git SHA）
  "keywords": ["..."],
  "category": "workflow",
  "skills": ["./<name>"]
}
```

## Step 5 — 驗證
```bash
# 1) 離線驗證器（純 stdlib、無外連）— frontmatter/命名/marketplace 註冊一起檢查
python skill-author/scripts/validate_skill.py <name>      # 或不帶參數驗全部
#   （官方 skills-ref 是 pip 套件、需外網，內網不適用；上面這支不需要。）

# 2) 本地安裝實測（測完移除，別污染設定）
claude plugin marketplace add "$PWD"
claude plugin install <name>@ai-agent-skills
claude plugin list | grep <name>          # 應 enabled
claude plugin marketplace remove ai-agent-skills
```

## 完成定義
- 目錄名 = `name` = kebab；`skills-ref validate` 過。
- description 有 what+when+`Triggers -`、第三人稱、稍 pushy。
- SKILL.md ≤500 行、自包含；scripts 純 stdlib。
- 已加進 `marketplace.json`（自身 plugin + bundle）—— **不設 `version`**，commit 即更新。
- 本地 install 實測 enabled。
