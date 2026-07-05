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
| `agent-rules-*`（[bugfix](agent-rules-bugfix/SKILL.md)、[feature](agent-rules-feature/SKILL.md)、[refactor](agent-rules-refactor/SKILL.md)、[investigate](agent-rules-investigate/SKILL.md)、[review](agent-rules-review/SKILL.md)） | 五種任務的**固定作業流程（playbook）**：每步有必填輸出模板、封閉分流、機器 gate 驗證，寫到最弱的模型也走得完。依任務關鍵字自動觸發。 |

外加一個**常駐 plugin**（不是 skill）：

| plugin | 做什麼 |
|---|---|
| [`agent-rules`](agent-rules/rules/CONSTITUTION.md) | **SessionStart hook** 每個 session 開頭自動注入 12 條硬規則憲法（證據先於宣稱、先重現再修、最小 diff、三振停手…）＋回合終檢，另附三個情境檔（[DECISIONS](agent-rules/rules/DECISIONS.md)／[SAFETY](agent-rules/rules/SAFETY.md)／[ANTIPATTERNS](agent-rules/rules/ANTIPATTERNS.md)）。做成 hook 而非 skill 是因為 skill 不保證被載入、hook 保證。由 Claude Fable 5 session 蒸餾而成，目標是讓較弱的模型也守紀律。 |

加上**外部開源 skill**（mirror 進內網 GitLab）：`superpowers`、`andrej-karpathy-skills`
—— 見下方〈外部 / 第三方 skill〉。要放新的 skill（自家寫的或外部 mirror 的）都歡迎，見〈維護者〉。

---

# 使用者：跑一次，之後全自動（推薦）

一條指令跑**一次**，把所有 skill 裝齊 + 打開自動更新 —— 之後 marketplace 有**修改或新增**
skill，你什麼都不用做，**每次開新 Claude Code session 自動帶到最新**。
**不用 clone 任何 repo**：`marketplace add` 會把整個 marketplace repo（含同步腳本）下載到
`~/.claude/plugins/marketplaces/ai-agent-skills/`，直接從那裡跑。

### 第一次設定（每台機器一次）

```bash
# 0) 前置：裝好 Claude Code、設好對內網 GitLab 的 git auth（token / SSH）
#    —— 跟平常 clone 公司 repo 一樣，背後就是 git clone。

# 1) 加 marketplace（會一併下載 skills-sync.sh）
claude plugin marketplace add https://gitlab.<你的公司>/<group>/ai-agent-skills.git

# 2) 一鍵裝齊 + 開自動更新
bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh

# 3) 生效
/reload-plugins            # 在 claude session 裡；或重啟 claude

# 4) 確認
claude plugin list         # 應看到 bundle + 外部 mirror plugins
```

### 之後更新：不用動作

腳本做了兩件事，讓更新從此自動：

- **裝的是 bundle plugin**（`ai-agent-skills` = 本 repo 自家 skill 整包）而不是逐個 skill。
  bundle 的內容清單住在 marketplace 裡 → repo **新增**一個 skill，隨 marketplace 刷新
  自動出現在你這，**不需要任何安裝動作**（逐裝做不到這點：auto-update 只更新已裝的，
  新 plugin 不會自己裝進來）。舊逐裝的使用者重跑一次腳本會自動遷移（移除逐裝、改裝 bundle）。
- **開了 marketplace auto-update**（寫進你的 `~/.claude/settings.json` 的
  `extraKnownMarketplaces` 條目；第三方 marketplace 預設是關的）。之後**每次 Claude Code
  啟動**自動 git-pull marketplace + 更新已裝 plugins；有更新會提示跑 `/reload-plugins`。

重跑 `bash skills-sync.sh` 只剩三個情境：**新機器初裝**、**要把 skills 同步到新的
agent**（Gemini/Codex/Cline/OpenCode，見下節）、marketplace **新收錄 bundle 以外的新 plugin**
（外部 mirror 或常駐 hook plugin 如 `agent-rules`——新 plugin 不會自己裝，bundle 只涵蓋
自家 skill；腳本讀 marketplace.json 會自動補裝）。自家 skill 的新增/修改**永遠不用重跑**；
憲法改版也不用——各家都走 hook/引用，session 開頭現讀 marketplace 檔（見下節）。

### 版本策略

- 本 repo 的 plugin **沒有 `version` 欄位** → git commit SHA 就是版本 → **每個 merge 進
  main 的 commit 都算新版**，auto-update 直接帶到 HEAD。「人人最新」就是這樣達成的。
- 日後若要**受控發版**（不想每個 commit 都推到全隊）：給 bundle 加 `version` 欄位，
  merge 時手動 bump 才算新版 —— 一個欄位切換兩種模式。
- 要 **org-wide 強制**（成員不可自行關掉）：請 IT 在 managed-settings.json 部署
  `extraKnownMarketplaces`（含 `"autoUpdate": true`）+ `enabledPlugins`，見官方
  「Manage plugins for your organization」。

### 跨 agent（Gemini CLI / Codex CLI / Cline / OpenCode）

同一條 `skills-sync.sh` 也會把**自家 skill** 同步給其他 agent —— 你不用為每個 agent 各維護一份。
**SKILL.md 是跨 agent 共用格式**（Claude Code、Codex CLI、Gemini CLI、OpenCode 都原生讀），所以做法是
**symlink 同一份來源**進各 agent 位置，內容零複製、改一處全動。腳本會**自動偵測**你機器上裝了哪些
agent（看家目錄），只同步偵測到的：

| agent | 同步到 | 怎麼吃 |
|---|---|---|
| Gemini CLI | `~/.agents/skills/<skill>`（symlink） | Gemini 原生把 `~/.agents/skills` 當 user skills 讀 |
| OpenCode | `~/.agents/skills/<skill>`（同一份 symlink） | OpenCode 原生讀 `~/.agents/skills`（也讀 `~/.config/opencode/skills`），與 Gemini 共用零成本；偵測依據 `~/.config/opencode` 存在 |
| Codex CLI | `~/.codex/skills/<skill>`（symlink） | Codex 原生讀 SKILL.md |
| Cline | `~/.cline/rules/<skill>.md`（生成） | Cline 不讀 SKILL.md，故生一個 **pointer rule**（skill 名＋描述＋「需要時讀該 SKILL.md」），不內嵌全文以免脹 context |

- 只想同步 agent、不碰 Claude plugin：`bash skills-sync.sh agents`。
- 加新自家 skill（bare SKILL.md 目錄）會自動納入，不用改腳本。
- **更新怎麼跟**：symlink 指向 marketplace 下載目錄 → marketplace 自動更新後,Gemini/Codex
  讀到的內容**跟著新**,不用重跑。只有 repo **新增** skill 時需要重跑一次（補新 symlink /
  Cline rule）—— 這是跨 agent 端唯一的手動情境。
- 範圍：只同步**本 repo 自家 skill**；外部 mirror（superpowers/karpathy）是整包 plugin，上游各自已支援多 agent，不由這裡轉。
- `agent-rules` 憲法在 Claude Code 走 **hook 機制**（自動）；其他 agent 預設只拿到五個
  playbook skills。要讓其他 agent 也吃憲法，加 **`--constitution`** 旗標（**opt-in，預設不做**
  ——因為要寫你的個人 dotfile）：

  ```bash
  bash skills-sync.sh --constitution          # 完整流程 + 憲法
  bash skills-sync.sh agents --constitution   # 只跨 agent + 憲法
  ```

  只碰偵測到的 agent，**用各家 hook 機制在 session 開頭注入**——跟 Claude Code 的
  hook plugin 同架構：hook 在 session 開始時**讀 marketplace 裡的憲法檔**，所以
  marketplace 更新後內容一律**自動跟新**，零快照：

  | agent | 機制 | 備註 |
  |---|---|---|
  | Codex | `~/.codex/hooks.json` SessionStart hook（`cat` 憲法＋情境路徑，stdout 進 context） | 舊版嵌在 AGENTS.md 的 block 會自動清掉 |
  | Gemini | `~/.gemini/settings.json` SessionStart hook（呼叫生成的 wrapper，輸出 `additionalContext` JSON） | 舊版 GEMINI.md 的 @import block 會自動清掉 |
  | Cline | `~/Documents/Cline/Rules/Hooks/TaskStart` hook script（`contextModification`） | Cline hooks 限 macOS/Linux；你自己已有 TaskStart 時**不覆蓋**、印手動指引；只有 `~/.cline` 的佈局退回 rules symlink |
  | OpenCode | `opencode.json` 的 `instructions[]`（**它的 plugin API 沒有 session-start 注入 hook**，instructions 就是官方常駐機制） | AGENTS.md 完全不碰 |

  所有 JSON merge 都**冪等**、不動你自己的任何 key 與 hook。情境檔
  （DECISIONS / SAFETY / ANTIPATTERNS）照設計按需讀、不常駐——隨憲法一起注入的只有
  **絕對路徑清單**（生成在 `~/.agents/agent-rules-situational-paths.md`），agent 要用時
  照路徑自己開（跟 Claude hook 報路徑同一招）。不想用旗標也可以手動貼
  [`agent-rules/rules/CONSTITUTION.md`](agent-rules/rules/CONSTITUTION.md)。

  **SAFETY guard（隨 `--constitution` 一起接線）**：SAFETY.md §1 的破壞性指令清單
  （`rm -rf`、`git push --force`、`git reset --hard`、`DROP TABLE`、無 WHERE 的
  DELETE、`sudo`…）由 [`agent-rules/hooks/guard.py`](agent-rules/hooks/guard.py) 在
  **hook 層機械攔截**——模型自不自覺都過不了關，這是 rules（勸）跟 hook（擋）的本質差異：

  | agent | 攔截點 | 效果 |
  |---|---|---|
  | Claude Code | plugin 內建 PreToolUse（裝 `agent-rules` plugin 就有，**不用旗標**） | `ask`——彈出確認讓使用者放行 |
  | Codex | `~/.codex/hooks.json` PreToolUse | deny＋理由回給 agent |
  | Gemini | `~/.gemini/settings.json` BeforeTool | deny＋理由回給 agent |
  | Cline | `Hooks/PreToolUse` script（同樣不覆蓋你既有的） | cancel＋errorMessage |
  | OpenCode | 生成 `plugins/agent-rules-guard.js`（`tool.execute.before` throw） | 擋下＋錯誤訊息 |

  被擋不是終點：理由文字會引導 agent 走 SAFETY.md §1 協定（亮指令→使用者同意→使用者跑）。
  pattern 清單改動要同步兩處：`guard.py` 與 skills-sync 生成的 OpenCode JS。

### 進階：只裝某幾個 / 離線

```bash
# 精挑單裝（不想全裝時）
/plugin install wiki-doc-author@ai-agent-skills      # 只要寫 wiki 文件的
```

- **bundle 或 granular 擇一**：裝了 bundle（腳本預設）就別再單裝裡面的個別 skill ——
  會重複載入（不報錯，但重複）。單裝的 plugin 更新照樣自動，但 repo **新增**的 skill
  不會自己出現（那是 bundle 的特權）。
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
- **更新鏈**：上游 GitHub → GitLab mirror 排程同步 → 成員的 marketplace auto-update 自動帶到
  （已裝該 plugin 的人）。**新收錄**的外部 plugin 是新 plugin，auto-update 不會自己裝 ——
  請成員跑一次 `skills-sync.sh`（腳本讀 marketplace.json 自動補裝）。

> ⚠️ 不 pin `sha` = 自動吃 mirror 同步到的任何 commit（含上游被改）。要穩定供應鏈就 pin。

### 寫新 skill

用 `skill-author` skill 讓 AI agent 照標準產出（含註冊 marketplace）；或人工照
[`CONTRIBUTING.md`](CONTRIBUTING.md) 的統一標準（官方 Agent Skills spec + 本 repo 慣例）寫。

### 開發環境（devcontainer）

本 repo 帶 `.devcontainer/`（python 3.14 + `requirements.txt` 的 lint/測試工具鏈，
跟 CI 同款）——寫/改 skill 的驗證（validator、lint）就在隔離環境跑。VS Code
「Reopen in Container」或 `devcontainer up --workspace-folder .` 即可用；不想手動管，
驗證指令一律 `bash skill-author/scripts/envrun.sh <指令>` —— 它自動判定
「已在容器內 / 容器在跑 / 沒起（自動起）/ repo 沒 devcontainer（host 直跑）」，
起不了會 exit 2 印選項。

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
