# ai-agent-skills

團隊共用的 **Claude Code / AI agent skills** 集散地，獨立成 repo 讓任何專案/agent 取用 ——
**不限 LLM Wiki**，各種 skill 都能放進來給大家用。這個 repo 本身就是一個 **Claude Code plugin
marketplace**，**公司內網 GitLab 也能用**（不需要 GitHub 或公開 marketplace）。

本 repo 自家的 skill：

| skill | 做什麼 |
|---|---|
| [`wiki-doc-author`](wiki-doc-author/SKILL.md) | 產出餵進 wiki processor 的源頭文件 —— API（README + openapi.json）、cronjob/worker/CLI、純知識，都一份 README 搞定。一個檔讀完就能做，附純 stdlib 工具（`scripts/`）。 |
| [`sop-to-spec`](sop-to-spec/SKILL.md) | 把維運 SOP（DBA runbook、infra 程序…）轉成「人能審、AI 能照著實作三層 FastAPI 服務」的 spec。 |
| [`skill-author`](skill-author/SKILL.md) | 在本 repo 新增/修改一個**可安裝**的 skill —— 照標準產 SKILL.md、註冊進 marketplace。讓 AI agent 自己會寫 skill。 |

加上**外部開源 skill**（mirror 進內網 GitLab）：`superpowers`、`andrej-karpathy-skills`
—— 見下方〈外部 / 第三方 skill〉。要放新的 skill（自家寫的或外部 mirror 的）都歡迎，見〈維護者〉。

---

# 使用者：團隊一鍵同步（推薦）

一條指令把**所有 skill 裝齊／更新到最新** —— 內建的 + 外部 mirror 全包。
**不用 clone 任何 repo**：`marketplace add` 會把整個 marketplace repo（含同步腳本）下載到
`~/.claude/plugins/marketplaces/ai-agent-skills/`，直接從那裡跑。

### 第一次設定

```bash
# 0) 前置（每台機器一次）：裝好 Claude Code、設好對內網 GitLab 的 git auth（token / SSH）
#    —— 跟平常 clone 公司 repo 一樣，背後就是 git clone。

# 1) 加 marketplace（會一併下載 skills-sync.sh）
claude plugin marketplace add https://gitlab.<你的公司>/<group>/ai-agent-skills.git

# 2) 一鍵裝齊全部 skill
bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh

# 3) 生效
/reload-plugins            # 在 claude session 裡；或重啟 claude

# 4) 確認
claude plugin list         # 應看到全部 skill plugin
```

### 之後更新：同一條

```bash
bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh
```

腳本內建 `marketplace add || update`，會**先 git-pull 刷新** marketplace（含 marketplace.json 和腳本本身），
再讀**新**清單裝/更新。所以：

- **裝跟更新是同一條**；fresh 機器會裝、已裝的 `plugin update` 帶到最新版。
- 清單**讀 `marketplace.json`**（唯一真相）→ marketplace 加了新 skill，大家重跑這條就自動補上，
  **不用記、不會漏**（即使你手上是舊腳本也一樣，因為它「先刷新再讀清單」）。bundle 會自動跳過，
  避免和它涵蓋的個別 skill 重複載入。
- 更新到的版本：本地 skill 跟 marketplace **每個新 commit**；外部 mirror 跟上游 **bump 的版本號**。
- 嫌路徑長可加 alias：`alias skills-sync='bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh'`。

### 跨 agent（Gemini CLI / Codex CLI / Cline）

同一條 `skills-sync.sh` 也會把**自家 skill** 同步給其他 agent —— 你不用為每個 agent 各維護一份。
**SKILL.md 是跨 agent 共用格式**（Claude Code、Codex CLI、Gemini CLI 都原生讀），所以做法是
**symlink 同一份來源**進各 agent 位置，內容零複製、改一處全動。腳本會**自動偵測**你機器上裝了哪些
agent（看家目錄），只同步偵測到的：

| agent | 同步到 | 怎麼吃 |
|---|---|---|
| Gemini CLI | `~/.agents/skills/<skill>`（symlink） | Gemini 原生把 `~/.agents/skills` 當 user skills 讀 |
| Codex CLI | `~/.codex/skills/<skill>`（symlink） | Codex 原生讀 SKILL.md |
| Cline | `~/.cline/rules/<skill>.md`（生成） | Cline 不讀 SKILL.md，故生一個 **pointer rule**（skill 名＋描述＋「需要時讀該 SKILL.md」），不內嵌全文以免脹 context |

- 只想同步 agent、不碰 Claude plugin：`bash skills-sync.sh agents`。
- 加新自家 skill（bare SKILL.md 目錄）會自動納入，不用改腳本。
- 範圍：只同步**本 repo 自家 skill**；外部 mirror（superpowers/karpathy）是整包 plugin，上游各自已支援多 agent，不由這裡轉。

### 進階：只裝某幾個 / 離線

```bash
# 精挑單裝（不想全裝時）
/plugin install wiki-doc-author@ai-agent-skills      # 只要寫 wiki 文件的
/plugin install ai-agent-skills@ai-agent-skills       # bundle：一次裝內建三個
```

- **bundle 或 granular 擇一**：裝了 bundle 就別再單裝裡面的個別 skill —— 會重複載入（不報錯，但重複）。
- **完全離線、不想用 plugin**：把需要的 skill 資料夾（含 `scripts/`）複製進專案的
  `.claude/skills/<name>/`，Claude Code 會自動載入。

---

# 維護者

### 換掉 placeholder（上線前一次性）

`skills-sync.sh` 開頭的 `GITLAB_URL`、`marketplace.json` 裡 external 的 placeholder URL，
都換成你們內網 GitLab mirror 的 `.git`。離線驗腳本篩選邏輯：`skills-sync.sh --self-test`。

### 外部 / 第三方 skill（內網 GitLab mirror）

`marketplace.json` 可以列**外部開源 skill**，團隊就能從同一個 marketplace 一次裝齊，不用各自去找上游。
作法：把上游 repo 拉成內網 GitLab 的 **pull mirror**，marketplace 指那個 mirror（不出公司）。

目前已收錄：

| plugin | 上游 | 說明 |
|---|---|---|
| `superpowers` | [obra/superpowers](https://github.com/obra/superpowers) | brainstorming、subagent 開發+code review、系統化 debug、red/green TDD、寫 skill。 |
| `andrej-karpathy-skills` | [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | 降低 LLM 常見 coding 錯誤的行為準則（Think Before Coding、Simplicity…）。 |

再加一個外部 skill，在 `marketplace.json` 的 `plugins` 加一筆，`source` 用 **`url` 形式**
指 mirror 的 `.git`（**不要**用 `github`+`repo`，那只給公開 GitHub）：

```jsonc
{
  "name": "<plugin-name>",
  "source": { "source": "url", "url": "https://gitlab.<你的公司>/<group>/<repo>.git" },
  "description": "External — …（註明 mirror 自哪個上游）",
  "author": { "name": "<上游作者>" },
  "category": "development",
  "homepage": "https://github.com/<上游>"
}
```

- **沒有 `skills` 欄**：外部 plugin 的 skill 由它自己的 repo 結構提供，本 repo 不列本地路徑。
- **沒設 `sha` = 跟 mirror 預設分支**；要鎖版本就加 `"sha": "<commit>"`（之後 update 不會自己往前，得手動改）。
- **更新鏈**：上游 GitHub → GitLab mirror 排程同步 → 團隊重跑 `skills-sync.sh`。
- 加完 `skills-sync.sh` 會自動納入（讀 marketplace.json），使用者不用改動作。

> ⚠️ 不 pin `sha` = 自動吃 mirror 同步到的任何 commit（含上游被改）。要穩定供應鏈就 pin。

### 寫新 skill

用 `skill-author` skill 讓 AI agent 照標準產出（含註冊 marketplace）；或人工照
[`CONTRIBUTING.md`](CONTRIBUTING.md) 的統一標準（官方 Agent Skills spec + 本 repo 慣例）寫。

### 企業 allow-list（給 IT，選用）

在 managed settings 用 regex（`strictKnownMarketplaces` 的 `hostPattern`）允許內網 GitLab host，
全公司即可安裝。參考官方「Manage plugins for your organization」。

---

# 設計原則

- **自包含**：每個 skill 一份 `SKILL.md` 讀完即可執行，不互相指來指去；工具放 `scripts/`（純 stdlib、無相依）。
- **通用**：不綁特定框架/語言/領域；新舊專案皆可。
- **安裝靠 plugin**：`.claude-plugin/marketplace.json` 把每個 skill 列為可安裝 plugin；skill 目錄放
  repo root，由 `skills` 自訂路徑指向。
- **清單即真相**：要裝什麼一律以 `marketplace.json` 為準，`skills-sync.sh` 讀它，不另維護名單。
