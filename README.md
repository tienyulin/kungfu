# ai-agent-skills

團隊共用的 **AI agent skills marketplace**。一個 repo、兩件事：

1. **Skills** —— 可安裝的工作流程（wiki 文件、SOP 轉 spec、API template 開發…），
   Claude Code 之外也同步給 Gemini / Codex / Cline / OpenCode。
2. **agent-rules** —— AI 工作紀律系統：常駐憲法＋固定作業 playbook＋破壞性指令
   機械攔截，讓**任何等級的模型**（含較弱的）都守同一套紀律。

本 repo 就是一個 **Claude Code plugin marketplace**，公司內網 GitLab 即可用，
不需要 GitHub 或公開 marketplace。

---

# 快速開始（使用者，每台機器一次）

```bash
# 0) 前置：裝好 Claude Code、設好對內網 GitLab 的 git auth（token / SSH）

# 1) 加 marketplace（會把整個 repo 含同步腳本下載到
#    ~/.claude/plugins/marketplaces/ai-agent-skills/，不用自己 clone）
claude plugin marketplace add https://gitlab.<你的公司>/<group>/ai-agent-skills.git

# 2) 一鍵裝齊 + 開自動更新
bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh

# 3) 生效與確認
/reload-plugins            # 在 claude session 裡；或重啟 claude
claude plugin list         # 應看到 bundle + agent-rules + 外部 mirror plugins
```

到這裡 **Claude Code 端已完整**：全部 skills＋憲法常駐＋SAFETY guard。

**還想接其他 agent**（Gemini / Codex / Cline / OpenCode）？之後任何時候跟 Claude 說
**`/agent-rules-setup`**，它自己知道腳本在哪、會問你要接多深。手動派：
`bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh --constitution`。

之後**不用再動**：marketplace auto-update 讓每次開新 session 自動帶到最新
（機制見〈更新怎麼跟〉）。

---

# 裡面有什麼

### 自家 skills（裝 bundle 全拿）

| skill | 做什麼 |
|---|---|
| [`wiki-doc-author`](wiki-doc-author/SKILL.md) | 產出餵進 wiki processor 的源頭文件 —— API（README + openapi.json）、cronjob/worker/CLI、純知識，都一份 README 搞定。附純 stdlib 工具。 |
| [`sop-to-spec`](sop-to-spec/SKILL.md) | 把維運 SOP（DBA runbook、infra 程序…）轉成「人能審、AI 能照著實作三層 FastAPI 服務」的 spec。 |
| [`api-template-dev`](api-template-dev/SKILL.md) | 照公司 API template 開三層式 FastAPI 服務：clone 起手、照層加端點、用內建工具不重造。 |
| [`skill-author`](skill-author/SKILL.md) | 在本 repo 新增/修改一個**可安裝**的 skill —— 照標準產 SKILL.md、註冊進 marketplace。 |
| `agent-rules-*` 五本 playbook | 見下方〈agent-rules〉。 |
| [`agent-rules-setup`](agent-rules-setup/SKILL.md) | 叫 Claude 代跑 skills-sync —— 找腳本、選模式、跑、轉述警告。**使用者不用知道腳本在哪。** |

### 常駐 plugin（不是 skill，要單獨裝一次——`skills-sync.sh` 會自動裝）

| plugin | 做什麼 |
|---|---|
| [`agent-rules`](agent-rules/rules/CONSTITUTION.md) | 憲法 SessionStart hook ＋ SAFETY guard PreToolUse hook（見下章）。做成 hook 不做 skill：**skill 不保證被載入，hook 保證**。 |

### 外部開源 skills（mirror 進內網 GitLab）

| plugin | 上游 | 說明 |
|---|---|---|
| `superpowers` | [obra/superpowers](https://github.com/obra/superpowers) | brainstorming、subagent 開發＋code review、系統化 debug、red/green TDD。 |
| `andrej-karpathy-skills` | [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | 降低 LLM 常見 coding 錯誤的行為準則。 |

---

# agent-rules — AI 工作紀律系統

由 Claude Fable 5 session 蒸餾，設計目標：**判斷力寫成弱模型也能機械執行的制度**
——具體判準（「diff > 3 檔 150 行就停」）、照抄模板（VERIFIED / STUCK 報告）、
封閉分流（條件→走哪），不寫抽象原則。四層：

| 層 | 內容 | 載入方式 |
|---|---|---|
| **憲法**（常駐） | [12 條硬規則](agent-rules/rules/CONSTITUTION.md)：證據先於宣稱、先重現再修、最小 diff、錯誤逐字引用、禁幻覺 API、測試唯讀、三振停手、破壞性操作需確認…＋回合終檢 6 題 | 各家 session-start hook 注入，**現讀 marketplace 檔＝永遠最新** |
| **Playbooks**（按需） | 五本固定流程：[bugfix](agent-rules-bugfix/SKILL.md)（先重現→根因→最小修→機器驗證）、[feature](agent-rules-feature/SKILL.md)（驗收清單先行）、[refactor](agent-rules-refactor/SKILL.md)（行為零改變）、[investigate](agent-rules-investigate/SKILL.md)（答案不是 diff）、[review](agent-rules-review/SKILL.md)（每個 finding 要有觸發條件） | skill 觸發詞路由，進 bundle 自動到手 |
| **情境檔**（按需讀） | [DECISIONS](agent-rules/rules/DECISIONS.md)（問 vs 做查表）、[SAFETY](agent-rules/rules/SAFETY.md)（護欄協定）、[ANTIPATTERNS](agent-rules/rules/ANTIPATTERNS.md)（15 種失敗氣味） | 憲法說何時讀；hook 一併注入**絕對路徑**，agent 要用時自己開（不常駐、不脹 context） |
| **SAFETY guard**（機械強制） | [`guard.py`](agent-rules/hooks/guard.py) 在 PreToolUse 層攔 `rm -rf`、force-push、`git reset --hard`、`DROP`、無 WHERE 的 DELETE、`sudo`… ——**模型自不自覺都過不了關**；擋下的理由文字引導 agent 走 SAFETY §1 協定（亮指令→使用者同意→使用者跑） | hook，同下表 |

### 支援矩陣（腳本自動偵測，只碰你機器上有的 agent）

| agent | skills | 憲法（常駐注入） | SAFETY guard |
|---|---|---|---|
| Claude Code | plugin bundle | plugin SessionStart hook | plugin PreToolUse → **ask**（彈確認給使用者） |
| Codex | `~/.codex/skills/`（symlink） | `~/.codex/hooks.json` SessionStart | 同檔 PreToolUse → deny＋理由 |
| Gemini | `~/.agents/skills/`（symlink） | `~/.gemini/settings.json` SessionStart | 同檔 BeforeTool → deny＋理由 |
| Cline | rules 目錄 pointer rule | `Hooks/TaskStart` script | `Hooks/PreToolUse` script → cancel |
| OpenCode | `~/.agents/skills/`（與 Gemini 共用 symlink） | `opencode.json` `instructions[]`（其 plugin API 無 session-start 注入 hook，instructions 即官方常駐機制） | 生成 guard plugin JS → throw |

- Claude Code 部分**裝了 plugin 就有**，不用旗標。
- 其他 agent 的憲法＋guard 走 **`--constitution` 旗標，opt-in、預設不做**——因為要寫你的
  個人設定檔（`~/.codex/hooks.json`、`~/.gemini/settings.json`…）。所有寫入**冪等**、
  不動你自己的任何 key；你既有的同名 Cline hook **絕不覆蓋**（印手動指引）；舊版佈局
  （AGENTS.md/GEMINI.md 嵌入 block、rules symlink）會自動清掉遷移。
- Cline hooks 限 macOS/Linux；只有 `~/.cline` 的舊佈局退回 rules symlink。
- 憲法或 guard 的 pattern 改版：**誰都不用重跑**——hook 現讀 marketplace 檔。
  唯一例外：guard pattern 清單改動要同步 `guard.py` 與生成的 OpenCode JS 兩處（維護者的事）。
- 非 Claude 工具想手動接（不跑腳本）：貼 [`CONSTITUTION.md`](agent-rules/rules/CONSTITUTION.md)
  進該工具 rules 檔即可。

---

# 更新怎麼跟

`skills-sync.sh` 做完兩件事，之後更新全自動：

- **裝 bundle plugin**（自家 skill 整包）而非逐裝。bundle 清單住在 marketplace →
  repo **新增** skill 隨 marketplace 刷新自動出現，零動作（逐裝做不到：auto-update
  只更新已裝的）。舊逐裝使用者重跑一次腳本自動遷移。
- **開 marketplace auto-update**（寫進 `~/.claude/settings.json` 的
  `extraKnownMarketplaces`；第三方 marketplace 預設關）。每次 Claude Code 啟動自動
  git-pull ＋ 更新已裝 plugins，有更新會提示 `/reload-plugins`。

**要重跑腳本的只剩三種情境**（其餘一律自動）：

1. 新機器初裝
2. 要接新的 agent（新裝了 Gemini/Codex/Cline/OpenCode）
3. marketplace 新收錄 **bundle 以外**的新 plugin（外部 mirror 或 `agent-rules` 這類
   hook plugin——新 plugin 不會自己裝；腳本讀 marketplace.json 自動補齊）

重跑方式：跟 Claude 說 `/agent-rules-setup`，或
`bash ~/.claude/plugins/marketplaces/ai-agent-skills/skills-sync.sh`（加 `--constitution`
含跨 agent 憲法/guard；`agents` 模式只碰跨 agent 不動 Claude plugins）。

### 版本策略

- 本 repo 的 plugin **不設 `version` 欄** → commit SHA 即版本 → 每個 merge 進 main
  都是新版，auto-update 直接帶到 HEAD。「人人最新」就是這樣達成的。
- 要**受控發版**：給 bundle 加 `version` 欄，merge 時手動 bump 才算新版——一個欄位切換。
- 要 **org-wide 強制**：IT 在 managed-settings.json 部署 `extraKnownMarketplaces`
  （含 `"autoUpdate": true`）＋ `enabledPlugins`，見官方「Manage plugins for your organization」。

### 跨 agent skills 同步細節

SKILL.md 是跨 agent 共用格式（Claude/Codex/Gemini/OpenCode 原生讀），腳本 **symlink
同一份來源**進各 agent 位置（Cline 例外：不讀 SKILL.md，生成 pointer rule——skill 名＋
描述＋「要用時去讀該 SKILL.md」，不內嵌全文以免脹 context）。symlink 指向 marketplace
下載目錄 → 內容跟著 auto-update 走。只同步**自家 skill**；外部 mirror 上游各自支援多
agent，不由這裡轉。

### 進階：只裝某幾個 / 離線

- 精挑單裝：`/plugin install wiki-doc-author@ai-agent-skills`。**bundle 或 granular
  擇一**——裝了 bundle 別再單裝成員 skill（會重複載入）；單裝更新照樣自動，但新 skill
  不會自己出現（bundle 特權）。
- 完全離線：把 skill 資料夾（含 `scripts/`）複製進專案 `.claude/skills/<name>/`，
  Claude Code 自動載入。

---

# 維護者

### 換掉 placeholder（上線前一次性）

`skills-sync.sh` 開頭的 `GITLAB_URL`、`marketplace.json` 裡 external 的 placeholder URL，
都換成內網 GitLab mirror 的 `.git`。離線驗證：`bash skills-sync.sh --self-test`
（plugin plan／guard／跨 agent 三套全綠才算過）。

### 加自家 skill

用 `skill-author` skill 讓 AI 照標準產出（含 marketplace 註冊、弱模型五規則、validator
gate）；或人工照 [`CONTRIBUTING.md`](CONTRIBUTING.md)。merge 進 main 後全隊自動拿到。

### 加外部 / 第三方 skill（內網 GitLab mirror）

上游 repo 拉成內網 GitLab **pull mirror**，`marketplace.json` 的 `plugins` 加一筆，
`source` 用 **`url` 形式**指 mirror 的 `.git`（**不要**用 `github`+`repo`，那只給公開 GitHub）：

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

- **沒有 `skills` 欄**：外部 plugin 的 skill 由它自己的 repo 結構提供。
- **沒設 `sha` = 跟 mirror 預設分支**；要鎖版本加 `"sha": "<commit>"`（之後不會自己往前）。
  ⚠️ 不 pin = 自動吃 mirror 同步到的任何 commit（含上游被改）。要穩定供應鏈就 pin。
- 更新鏈：上游 GitHub → GitLab mirror 排程同步 → 成員 auto-update 自動帶到（已裝的人）。
  **新收錄**的是新 plugin，請成員重跑一次腳本（自動補裝）。

### 改 agent-rules

- 憲法/情境檔/playbook：直接改 md，merge 即生效（hook 現讀檔，全隊零動作）。
- guard pattern：改 [`agent-rules/hooks/guard.py`](agent-rules/hooks/guard.py) 的
  `PATTERNS` **和** `skills-sync.sh` 生成的 OpenCode JS 清單，**兩處同步**；
  `--self-test` 有 guard 單元測試擋回歸。
- 新的弱模型失敗模式 → [ANTIPATTERNS.md](agent-rules/rules/ANTIPATTERNS.md) 加一條
  （氣味要可機械自檢，改做要可執行）。

### 開發環境（devcontainer）

本 repo 帶 `.devcontainer/`（python 3.14 ＋ lint/測試工具鏈，跟 CI 同款）。驗證指令一律
`bash skill-author/scripts/envrun.sh <指令>`——自動判定「容器內／容器在跑／自動起／
沒 devcontainer 就 host 直跑」，起不了 exit 2 印選項。

### 企業 allow-list（給 IT，選用）

managed settings 用 `strictKnownMarketplaces` 的 `hostPattern`（regex）允許內網 GitLab
host，全公司即可安裝。見官方「Manage plugins for your organization」。

---

# 設計原則

- **自包含**：每個 skill 一份 SKILL.md 讀完即可執行；工具放 `scripts/`（純 stdlib、零相依）。
- **清單即真相**：裝什麼一律以 `marketplace.json` 為準，`skills-sync.sh` 讀它，不另維護名單。
- **hook 勝過 rules**：要保證載入的用 hook（常駐注入、機械攔截），rules/skill 只放按需內容
  ——rules 是勸，hook 是擋。
- **引用勝過快照**：hook 在 session 開頭現讀 marketplace 檔，改版全隊自動跟新，零嵌入複本。
- **弱模型優先**：規則寫成判準＋模板＋封閉分流（見
  [weak-model-rules](skill-author/references/weak-model-rules.md)），最弱的模型走得完才算數。
- **別人的 dotfile 是別人的**：寫個人設定檔一律 opt-in、冪等、不碰無關內容、不覆蓋既有 hook。
