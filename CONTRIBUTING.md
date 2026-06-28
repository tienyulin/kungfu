# 寫一個新 skill — 統一標準

本 repo 的 skill 一律遵守**官方 Agent Skills spec**（<https://agentskills.io/specification>）＋下面的本 repo 慣例。
照這份寫 `SKILL.md`、放工具、加進 `.claude-plugin/marketplace.json`，就完成。

> 這份是給人看的。**要讓 AI agent 幫你寫 skill**：用 `skill-author` skill（它把同一套標準做成可執行流程，
> 含 frontmatter 範本與註冊 marketplace 的步驟）。本檔與該 skill 同一套規範。

## 1. 目錄結構（官方）

```
<skill-name>/
├── SKILL.md          # 必要：frontmatter + 指示
├── scripts/          # 選填：可執行工具（純 stdlib、無相依）
├── references/       # 選填：漸進揭露的細節文件
└── assets/           # 選填：範本/資源
```

- skill 目錄放在 **repo root**（不是 `skills/` 子目錄）—— `marketplace.json` 的 `skills` 用自訂路徑
  指向它們，安裝走 plugin（見 §5）。

## 2. SKILL.md frontmatter（官方欄位）

| 欄位 | 必填 | 規則 |
|---|---|---|
| `name` | 是 | ≤64 字、小寫英數+連字號、**須等於目錄名**、不可頭尾/連續連字號 |
| `description` | 是 | ≤1024 字。講 **what + when + 觸發詞**，第三人稱，**稍微 pushy**（Claude 傾向 under-trigger） |
| `license` | 否 | 短字串或指向 bundled license 檔 |
| `compatibility` | 否 | ≤500 字。只有特殊環境需求才寫（如 `Requires Python 3.14+`） |
| `metadata` | 否 | 字串 map。**版本不放這**（版本以 `marketplace.json` 為單一真相，見 §5） |

**description 慣例**：結尾用統一標籤 `Triggers - "<中文觸發語>"、"<english trigger>"、"/<skill-name>"`，
列具體觸發句（中英都給）。範例見現有 `wiki-doc-author`、`sop-to-spec`。

## 3. body（指示）

- **≤ 500 行 / < 5000 tokens**。寫得讀完就能做。
- 太長 → 拆進 `references/`（漸進揭露：agent 需要才載）。檔案引用用**相對路徑、只深一層**
  （`references/REFERENCE.md`、`scripts/foo.py`），不要 `../`、不要深層鏈。
- 結構建議：決策樹/步驟、輸入輸出範例、邊界情況。
- **語言：prose 用中文**（團隊慣例），專有名詞英文＋首次出現加一句解釋。

## 4. scripts / references / assets（本 repo 慣例）

- `scripts/`：**純 stdlib、零相依**，安裝時隨 plugin 複製（不可引用 skill 目錄外的檔）。錯誤訊息要清楚。
- `references/`：每檔聚焦單一主題，越小越省 context。
- `assets/`：範本/schema/資料檔。

## 5. 註冊進 marketplace（必做，否則裝不到）

在 `.claude-plugin/marketplace.json` 的 `plugins` 加一個項目，並加進 `ai-agent-skills` bundle：

```jsonc
{
  "name": "<skill-name>",          // = 目錄名 = SKILL.md 的 name
  "source": "./",
  "strict": false,
  "description": "...",            // 可與 SKILL.md description 相近
  "author": { "name": "tienyulin" },           // 不設 version → 每次 commit 自動算新版（git SHA）

  "keywords": ["..."],
  "category": "workflow",
  "skills": ["./<skill-name>"]
}
```
- 同時把 `"./<skill-name>"` 加進 bundle plugin `ai-agent-skills` 的 `skills` 陣列
  （這樣全裝 bundle 的 user，update 後就會自動拿到這個新 skill）。
- **不要設 `version`** —— 省略它，Claude 就用 git commit SHA 當版本：每次 push 都算新版，user
  `/plugin marketplace update` + update 即拿最新，零手動 bump。（設了 version 反而要每次手動改，漏改 = 收不到更新。）
- **跨 agent 自動納入**：只要 skill 是 repo root 下含 `SKILL.md` 的目錄，`skills-sync.sh` 的跨 agent
  step 會自動 symlink 給 Gemini/Codex、並為 Cline 生 pointer rule —— 不用另外設定。

## 6. 驗證（提交前）

```bash
# 離線驗證器（純 stdlib、無外連）— frontmatter/命名/marketplace 註冊
python skill-author/scripts/validate_skill.py            # 驗全部，或帶 <skill-name> 驗單一

# 本地安裝實測（測完移除，別污染設定）
claude plugin marketplace add "$PWD"
claude plugin install <skill-name>@ai-agent-skills
claude plugin marketplace remove ai-agent-skills
```
> 官方 `skills-ref`（<https://github.com/agentskills/agentskills>）是 pip 套件、需外網安裝，**內網不適用**；
> 上面這支自帶驗證器涵蓋同樣檢查、零相依。本檔的規則都已內聯，不需要連 agentskills.io 也能照做。

## Checklist（新 skill）
- [ ] 目錄名 = `name` = kebab-case
- [ ] description 有 what+when+`Triggers -`（中英觸發句）、第三人稱、稍 pushy
- [ ] SKILL.md ≤500 行；超出移到 `references/`
- [ ] `scripts/` 純 stdlib；引用相對、只深一層
- [ ] prose 中文、專有名詞英文+解釋
- [ ] 加進 `marketplace.json`（自身 plugin + bundle）—— 不設 `version`（commit 即更新）
- [ ] `skills-ref validate` 過、本地 install 實測過
