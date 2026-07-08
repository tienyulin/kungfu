<p align="center">
  <img src="assets/kungfu-icon.png" width="200" alt="Kungfu">
</p>

<h1 align="center">Kungfu</h1>

<p align="center">
  <em>插上就會一身功夫 — “I know kung fu.”</em>
</p>

---

插上一根線、睜眼就會功夫。agent 裝上 Kungfu，立刻上身一整套武功——**不是它突然變聰明，
是套路、心法、戒律一次附身**。弱的模型也打得出師父的招式。

一個 marketplace，把「功夫」拆成三種可安裝的東西：

- **招式（skills）** —— 可安裝的工作流程（wiki 文件、SOP 轉 spec、API template 開發…），
  Claude Code 之外也同步給 Gemini / Codex / Cline / OpenCode。
- **心法＋戒律（agent-rules）** —— 常駐 Constitution＋固定作業 playbook＋破壞性指令機械攔截，
  讓**任何等級的模型**（含較弱的）都守同一套紀律。
- **一路過招到收招（dev-loop）** —— 丟一個需求，agent 自己繞「做→驗→修」直到全綠開 PR。

## 沒有 Kungfu ／ 有 Kungfu

你叫 haiku 修一個 bug。它改一改，回你「應該修好了」——沒跑測試。

裝了 Kungfu，Constitution Law 1 當場擋下這句：**沒有 `VERIFIED` 區塊、沒真的跑過驗證指令，
禁止說 done。** 弱模型被逼著先重現、先跑測試、貼出輸出，才准回報完成。招式擺好，破綻自然少。

本 repo 在 Claude Code 端是一個 **plugin marketplace**（其他 agent 走 skill-drop
進共用目錄，見〈跨 agent 同步〉），任何 git 主機都能託管
（GitHub、GitLab、內部 git server 皆可）。要搬進內部環境、把所有 URL 一次換成
內部 mirror，見〈維護者〉的 `localize.sh`。

---

# 快速開始（使用者，每台機器一次）

一支腳本 `skills-sync.sh` provision 你機器上**所有** agent
（Claude Code／Gemini／Codex／OpenCode／Cline）——偵測到誰、就用該 agent 的原生機制裝誰。
兩步：

**① 把 repo 拿到機器上**（二選一，不分主次）：

```bash
# A. 有 Claude Code：加 marketplace（下載整個 repo 到 ~/.claude/plugins/marketplaces/kungfu/，
#    順便開 Claude 端 auto-update；不用自己 clone）
claude plugin marketplace add https://github.com/tienyulin/kungfu.git

# B. 其他任何情況（沒有 Claude Code，或就是想自己管）：clone 一份，建議放 $HOME 底下
git clone https://github.com/tienyulin/kungfu.git ~/kungfu
```

**② 跑腳本**——它偵測你有的 agent 就裝哪些，用該 agent 的原生機制上 skills（Claude：bundle
plugin＋auto-update；Gemini／Codex：extension／plugin adapter；OpenCode／Cline：skill-drop）。
加 `--constitution` 再把 Constitution＋Guard 接進非 Claude agent 的 dotfile（opt-in、冪等，
逐 agent 細節見〈支援矩陣〉）：

```bash
bash <repo>/skills-sync.sh --constitution            # <repo> = ① 拿到的目錄
bash ~/kungfu/skills-sync.sh agents --constitution   # 沒有 Claude Code、只接其他 agent（不碰 Claude plugins）
```

**③ 確認**：Claude Code 在 session 裡 `/reload-plugins`（或重啟）＋`claude plugin list`
（應看到 bundle + agent-rules，以及外部 skill 各自的 plugin）；其他 agent 重開 session 即生效。

之後**不用再動**：Claude 走 marketplace auto-update、其他 agent 走 hook self-refresh，
每次開新 session 自動帶到最新（機制見〈更新怎麼跟〉）。

### clone 放哪、可攜性（自行 clone 的人 = 上面的 B）

- skills、Constitution hook、Guard 全部照裝，完全不用 `claude` CLI（腳本偵測不到 `claude`
  會自動跳過 plugin 段）。
- **clone 建議放在 `$HOME` 底下**（`~/kungfu` 或 marketplace 的 `~/.claude/...`）。
  只要 clone 在家目錄內，`--constitution` 生成的 hook 就用 `$HOME`／`~` **相對路徑**
  （執行時展開），不寫死絕對前綴——這讓 hook 能跨機器/容器搬（見下）。放 `$HOME` 外
  （`/opt`、submodule workspace）也能用，但那台的 hook 會是絕對路徑、不可攜。
- **更新一樣全自動**：hook 每次觸發背景 git pull 這份 clone（6 小時節流），
  跟走 marketplace 的人同一套 self-refresh 機制。
- clone **別刪**——hooks 都指向它。之後裝了 Claude Code，重跑一次腳本即補上 plugin 部分。

### 在 devcontainer 裡用 agent-rules（掛進去，不用重裝）

hook 用 `$HOME`-relative 生成後，容器只要把 host 的相同目錄**掛到容器自己的 HOME**，
host 裝一次、每個容器共用、跟電腦一致：

| 容器裡用 | devcontainer.json `mounts` | 為什麼 |
|---|---|---|
| **Claude Code** | `~/.claude` → `${containerEnv:HOME}/.claude` | plugin hook 走 `${CLAUDE_PLUGIN_ROOT}`；掛 `.claude` 就把 marketplace clone 一起帶進去。**一條搞定** |
| **Cline / Codex / Gemini** | `~/kungfu` → 容器 HOME 同名 ＋ `~/.agents` → 容器 HOME 同名 | hook 讀 clone（`~/kungfu/...`）＋ `~/.agents/...`；`$HOME` 在容器展開成容器 HOME → 對得上 |

```jsonc
// Cline/Codex/Gemini（手動 clone 在 ~/kungfu 的情況）：
"mounts": [
  "source=${localEnv:HOME}/kungfu,  target=${containerEnv:HOME}/kungfu,  type=bind,consistency=cached",
  "source=${localEnv:HOME}/.agents, target=${containerEnv:HOME}/.agents, type=bind,consistency=cached"
  // ＋ 你的 agent 設定目錄（Cline 的 Hooks 那個）掛到容器對應位置
]
```

- **前提**：clone 在 `$HOME` 底下（見上）。放 `$HOME` 外就得掛到與 hook 內完全相同的絕對路徑。
- **OpenCode 例外**：它的 `instructions[]` 路徑保持絕對（opencode.json loader 不保證展開 `~`），
  所以 OpenCode 這條不可攜——要嘛在容器內重跑 skills-sync，要嘛掛同絕對路徑。
- 想在容器內**全新裝**（不掛）也行：容器裡 `git clone … ~/kungfu && bash ~/kungfu/skills-sync.sh agents --constitution`，hook 就用容器路徑生成。

---

# 裡面有什麼

### 自家 skills（裝 bundle 全拿）

| skill | 做什麼 |
|---|---|
| [`wiki-doc-author`](skills/wiki-doc-author/SKILL.md) | 產出餵進 wiki processor 的源頭文件 —— API（README + openapi.json）、cronjob/worker/CLI、純知識，都一份 README 搞定。附純 stdlib 工具。 |
| [`sop-to-spec`](skills/sop-to-spec/SKILL.md) | 把維運 SOP（DBA runbook、infra 程序…）轉成「人能審、AI 能照著實作三層 FastAPI 服務」的 spec。 |
| [`dev-api-template`](skills/dev-api-template/SKILL.md) | 組織 API template 的**功能與架構參考**：查它有哪些內建工具、架構怎麼分層，開發時當默認藍圖（可偏離、非強制）。facts 可 rescan 改成公司內部版。 |
| [`skill-author`](skills/skill-author/SKILL.md) | 在本 repo 新增/修改一個**可安裝**的 skill —— 照標準產 SKILL.md、註冊進 marketplace。 |
| `dev-*` 六本 playbook（bugfix / feature / refactor / investigate / review / test） | 開發任務的固定作業流程，見下方〈agent-rules〉。 |
| [`dev-loop`](skills/dev-loop/SKILL.md) | **一個需求自己做到好**：loop engineering 的端到端迭代圈，見下方〈dev-loop〉。 |
| [`agent-rules-setup`](skills/agent-rules-setup/SKILL.md) | 叫 agent 代跑 skills-sync —— 找腳本、選模式、跑、轉述警告。**使用者不用知道腳本在哪。** |
| [`using-kungfu`](skills/using-kungfu/SKILL.md) | bootstrap meta-skill：動手前先挑對的 kungfu skill。Gemini/OpenCode 會在 session 開頭自動載（跟 Constitution 互補，不重述工作紀律）。 |

### 常駐 plugin（不是 skill，要單獨裝一次——`skills-sync.sh` 會自動裝）

| plugin | 做什麼 |
|---|---|
| [`agent-rules`](agent-rules/rules/CONSTITUTION.md) | Constitution SessionStart hook ＋ Guard PreToolUse hook（見下章）。做成 hook 不做 skill：**skill 不保證被載入，hook 保證**。 |

### 外部開源 skills（直接指向公開上游；要換內部 mirror 見 localize.sh）

| plugin | 上游 | 說明 |
|---|---|---|
| `superpowers` | [obra/superpowers](https://github.com/obra/superpowers) | brainstorming、subagent 開發＋code review、系統化 debug、red/green TDD。 |
| `andrej-karpathy-skills` | [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | 降低 LLM 常見 coding 錯誤的行為準則。 |

**外部 skills 進所有 agent（含 Claude Code），單一來源＝**
[`external-skills.json`](external-skills.json)（name/url/ref）。`skills-sync` 偵測到哪些 agent，
就用**那家的原生機制**裝——repo 有該家 adapter／自帶 marketplace 就照它的設計裝（session-start
bootstrap 才會正確載入；upstream 明確拒絕手動 symlink 轉發），沒有就 skill-drop：

| agent | repo 有該家 adapter／marketplace | 純 skill（無 adapter） |
|---|---|---|
| Claude Code | `claude plugin marketplace add <url>` ＋ install（repo 自帶 `.claude-plugin/marketplace.json`） | drop `skills/*/` 進 `~/.claude/skills`（Claude 原生自動探索） |
| Gemini | `gemini extensions install <url>` | 略過（Gemini 只吃 extension，純 skill 當不了） |
| OpenCode | `opencode plugin "<name>@git+<url>" --global` | drop 進 `~/.agents/skills`（OpenCode 原生讀） |
| Codex | `codex plugin marketplace add <repo>` ＋ `codex plugin add` | drop 進 `~/.agents/skills`（Codex 原生讀） |
| Cline | 無原生裝 → drop `skills/*/` 進 `~/.cline/skills` | 同左 |

每個 repo 先 clone 一份到 `~/.agents/external/<name>`（backing store＋判斷它 ship 了哪些
adapter＋給沒 adapter 的 agent 當 skill-drop 來源）。預設開；不想裝外部的加 `--no-external`。
**不再放進 Claude 的 `marketplace.json`**——Claude 也從 external-skills.json 裝。外部 skill 不走
marketplace auto-update：更新／新收錄都是**重跑一次 skills-sync**（各 agent 一起帶到，含 Claude）。

---

# agent-rules — AI 工作紀律系統

設計目標：**把判斷力寫成弱模型也能機械執行的制度**
——具體判準（「diff > 3 檔 150 行就停」）、照抄模板（VERIFIED / STUCK 報告）、
封閉分流（條件→走哪），不寫抽象原則。五層：
（這套制度的由來與時間見 [ORIGIN.md](ORIGIN.md)。）

| 層 | 內容 | 載入方式 |
|---|---|---|
| **Constitution**（常駐） | [12 條硬規則](agent-rules/rules/CONSTITUTION.md)：證據先於宣稱、先重現再修、最小 diff、錯誤逐字引用、禁幻覺 API、測試唯讀、三振停手、破壞性操作需確認…＋回合終檢 6 題 | 各家 session-start hook 注入，**現讀 marketplace 檔＝永遠最新** |
| **Judgment**（常駐入口＋按需展開） | 通用判斷制度 32 檔，vendored 於 [agent-rules/judgment/](agent-rules/judgment/README.md)：[INDEX](agent-rules/judgment/INDEX.md)＝Constitution 沒覆蓋的 7 條判斷法則（目的>字面、可逆×範圍、成本對稱、預設值+ASSUMED…）＋兩層路由表；17 個任務域檔（部署/除錯/架構/研究/摘要/事故/資安/Oracle…）＋ 11 個訊號檔（卡關/選擇/權衡/驗證/自我進化…） | INDEX 隨 Constitution**同一支 hook** 常駐注入（含各檔絕對路徑）；域檔 agent 照路由表自己開——開工時查任務型、過程中對訊號型，**任何時刻最多 2 檔**（防發散） |
| **Playbooks**（按需） | 六本固定流程：[bugfix](skills/dev-bugfix/SKILL.md)（先重現→根因→最小修→機器驗證）、[feature](skills/dev-feature/SKILL.md)（驗收清單先行）、[refactor](skills/dev-refactor/SKILL.md)（行為零改變）、[investigate](skills/dev-investigate/SKILL.md)（答案不是 diff）、[review](skills/dev-review/SKILL.md)（每個 finding 要有觸發條件）、[test](skills/dev-test/SKILL.md)（每條測試 kill-proof） | skill 觸發詞路由，進 bundle 自動到手 |
| **Situations**（按需讀） | [DECISIONS](agent-rules/rules/DECISIONS.md)（問 vs 做查表）、[SAFETY](agent-rules/rules/SAFETY.md)（護欄協定）、[ANTIPATTERNS](agent-rules/rules/ANTIPATTERNS.md)（15 種失敗氣味） | Constitution 說何時讀；hook 一併注入**絕對路徑**，agent 要用時自己開（不常駐、不脹 context） |
| **Guard**（機械強制） | [`guard.py`](agent-rules/hooks/guard.py) 在 PreToolUse 層攔 `rm -rf`、force-push、`git reset --hard`、`DROP`、無 WHERE 的 DELETE、`sudo`… ——**模型自不自覺都過不了關**；擋下的理由文字引導 agent 走 SAFETY §1 協定（亮指令→使用者同意→使用者跑） | hook，同下表 |

### 支援矩陣（腳本自動偵測，只碰你機器上有的 agent）

| agent | skills | Constitution（常駐注入） | Guard |
|---|---|---|---|
| Claude Code | plugin bundle | plugin SessionStart hook | plugin PreToolUse → **ask**（彈確認給使用者） |
| Codex | `~/.agents/skills/`（skill-drop，Codex 原生讀） | `~/.codex/hooks.json` SessionStart | 同檔 PreToolUse → deny＋理由 |
| Gemini | `~/.agents/skills/`（skill-drop，Gemini 原生讀） | `~/.gemini/settings.json` SessionStart | 同檔 BeforeTool → deny＋理由 |
| Cline | `~/.cline/skills/`（skill-drop，原生 on-demand Skills ≥3.48） | `Hooks/TaskStart` script | `Hooks/PreToolUse` script → cancel |
| OpenCode | `~/.agents/skills/`（skill-drop，OpenCode 原生讀） | `opencode.json` `instructions[]`（其 plugin API 無 session-start 注入 hook，instructions 即官方常駐機制） | 生成 guard plugin JS → throw |

- Claude Code 部分**裝了 plugin 就有**，不用旗標。
- 其他 agent 的 Constitution＋guard 走 **`--constitution` 旗標，opt-in、預設不做**——因為要寫你的
  個人設定檔（`~/.codex/hooks.json`、`~/.gemini/settings.json`…）。所有寫入**冪等**、
  不動你自己的任何 key；你既有的同名 Cline hook **絕不覆蓋**（印手動指引）；舊版佈局
  （AGENTS.md/GEMINI.md 嵌入 block、rules symlink）會自動清掉遷移。
- **黏性（sticky）**：`--constitution` 用過一次會留一個記號（`~/.agents/.constitution-on`），
  之後**每次普通 `skills-sync` 都自動帶上** constitution——重跑時不會忘。要關用
  `--no-constitution`（移除記號並停）。所以 skills-sync 的 **code 有更新時**（例如 hook
  路徑改法），只要重跑一次 `skills-sync`（不必記得加旗標）就會用新版重生 hook。
- **Cline 偵測靠安裝、不靠開過**：資料夾（`~/Documents/Cline`）要開過 Cline 才生，所以改看
  「擴充有沒有裝」（`saoudrizwan.claude-dev` 在 `~/.vscode*/extensions/`）＋ workspace 的
  `devcontainer.json`／`extensions.json` 有沒有宣告它。任一命中就一次佈好，不用跑兩次；
  都沒有就完全不碰。devcontainer 裡擴充還在裝、config 也抓不到的邊角情況 → `--cline` 強制。
- Cline hooks 限 macOS/Linux；只有 `~/.cline` CLI 佈局（無 app base）時 Constitution 退回 rules symlink。
- Constitution 或 guard 的 pattern 改版：**誰都不用重跑**——hook 現讀 marketplace 檔。
  唯一例外：guard pattern 清單改動要同步 `guard.py` 與生成的 OpenCode JS 兩處（維護者的事）。
- **自家 skill 靠上表的機制到手**：Gemini／Codex／OpenCode 都原生讀 `~/.agents/skills`，
  `skills-sync` 把 skills skill-drop 進去**一次餵三家**（不裝 Gemini extension／Codex plugin——
  那會讓同一份 skill 被載入兩次、每次啟動跳 skill conflict 警告）；Cline 進 `~/.cline/skills`。
  完整說明見下方〈跨 agent skills 同步細節〉。Constitution/guard 一律另走 hook。

### dev-loop — 把需求丟進圈裡（loop engineering）

[Loop engineering](https://kilo.ai/articles/what-is-loop-engineering)：人設計一次
迴圈（目標、驗證 gate、停止規則），agent 拿到需求就自己繞
「做 → 觀察 → 調整」直到 gate 全綠開 PR——**gate 的失敗輸出不是錯誤訊息，是下一輪
的新 context**。人不再逐步下 prompt，只把守 PR 與升級。

用法一行：`/dev-loop <需求>`。Intent 鎖定時問你一次，之後圈內不再問；
卡住走三振升級（LOOP ESCALATED）而不是無限重試；Guard 在圈內照常生效。

**`VERIFY.md` 慣例**（讓 loop 不用人教怎麼驗）：每個 repo root 放一份，
一個 gate 一節（run 指令＋pass 判準），至少一個 unit 類＋一個 smoke 類
（非測試觀察，防 overfitting to tests）。格式見
[skills/dev-loop/references/verify-format.md](skills/dev-loop/references/verify-format.md)。

---

# 更新怎麼跟

`skills-sync.sh` 幫每個偵測到的 agent 接上自我更新，之後全自動——各 agent 各自的通道：

- **Claude Code**：裝 bundle plugin（自家 skill 整包，非逐裝——bundle 清單住 marketplace，
  repo **新增** skill 隨刷新自動出現；逐裝做不到，auto-update 只更新已裝的，舊逐裝使用者
  重跑一次自動遷移）＋開 marketplace auto-update（寫進 `~/.claude/settings.json` 的
  `extraKnownMarketplaces`；第三方 marketplace 預設關）。每次啟動 git-pull＋更新已裝
  plugins，有更新提示 `/reload-plugins`。
- **Codex / Gemini / Cline**：`--constitution` 接的 hook 會自我 refresh——觸發時背景
  git pull clone（6 小時節流、不擋啟動，新內容下個 session 生效）。整週只用 Cline，
  Constitution 與 guard 也自己保持最新。
- **OpenCode**：instructions 是 host 直讀檔、沒有 exec 點，跟著同機其他 agent 的 refresh 沾光。

沒有哪個 agent 依賴「有沒有開 Claude Code」——各自通道各自更新。

**要重跑腳本的只剩三種情境**（其餘一律自動）：

1. 新機器初裝
2. 要接新的 agent（新裝了 Gemini/Codex/Cline/OpenCode）
3. 新增了外部 skill（`external-skills.json` 加一筆），或 marketplace 新收錄 bundle 以外的
   新 plugin（`agent-rules` 這類 hook plugin）——這些不會自己裝，重跑腳本自動補齊

重跑方式：跟 agent 說 `/agent-rules-setup`（它自己找腳本）；或直接跑 skills-sync——
Claude 使用者在 `~/.claude/plugins/marketplaces/kungfu/skills-sync.sh`、自行 clone 的在
`~/kungfu/skills-sync.sh`（加 `--constitution` 含跨 agent Constitution/guard；`agents` 模式只碰
跨 agent 不動 Claude plugins）。

### 版本策略

- 本 repo 的 plugin **不設 `version` 欄** → commit SHA 即版本 → 每個 merge 進 main
  都是新版；Claude 的 marketplace auto-update 與其他 agent 的 self-refresh hook 都直接
  帶到 HEAD——「人人最新」由這兩條通道共同達成。
- 要**受控發版**：給 bundle 加 `version` 欄，merge 時手動 bump 才算新版——一個欄位切換。
- 要 **org-wide 強制**：IT 在 managed-settings.json 部署 `extraKnownMarketplaces`
  （含 `"autoUpdate": true`）＋ `enabledPlugins`，見官方「Manage plugins for your organization」。

### 跨 agent skills 同步細節

自家 skill 都在 `skills/`。**Gemini／Codex／OpenCode 都原生讀 `~/.agents/skills`**，所以
`skills-sync` 把 `skills/*/` skill-drop 進去**一次餵三家**；Cline 進 `~/.cline/skills`：

| agent | 自家 skill 裝法 | bootstrap（using-kungfu）自動載入？ |
|---|---|---|
| Gemini | skill-drop `skills/*/` → `~/.agents/skills`（原生讀） | ✗（作為一般 skill 被發現，不 force-load） |
| Codex | skill-drop `skills/*/` → `~/.agents/skills`（原生讀） | ✗（靠 skill discovery） |
| OpenCode | skill-drop `skills/*/` → `~/.agents/skills`（原生讀） | ✗ 本機（`.opencode/plugins/kungfu.js` 只在 npm-published 路徑注入） |
| Cline | skill-drop `skills/*/` → `~/.cline/skills`（無原生安裝機制） | ✗ |

**為什麼不裝 Gemini extension／Codex plugin**：那些機制會把同一份 skill 再曝一次，而 Gemini／
Codex 本來就讀 `~/.agents/skills` → 同一 skill 載入兩次、每次啟動跳 skill conflict 警告。單一
來源（skill-drop）最乾淨；既有的舊 extension／plugin `skills-sync` 會自動移除遷移。

Constitution/guard 一律另走 hook（見〈支援矩陣〉），跟這層無關。**外部 skill（`external-skills.json`）**
不同：外部 repo 各自 ship adapter，所以照它的設計用原生機制裝（adapter repo 走 extension／plugin，
純 skill 才 skill-drop），見上方〈外部開源 skills〉。

### 進階：只裝某幾個 / 離線

- 精挑單裝：`/plugin install wiki-doc-author@kungfu`。**bundle 或 granular
  擇一**——裝了 bundle 別再單裝成員 skill（會重複載入）；單裝更新照樣自動，但新 skill
  不會自己出現（bundle 特權）。
- 完全離線：把 skill 資料夾（含 `scripts/`）複製進專案 `.claude/skills/<name>/`，
  Claude Code 自動載入。

---

# 維護者

### 搬進內部環境（一次性）

預設所有 URL 指向公開 GitHub，開箱即用。要換成內部 git 主機的 mirror：複製
[`localize.config.example`](localize.config.example) → `localize.config`，填入你的
內部 URL，跑 `bash localize.sh`——它一次把 `skills-sync.sh`、`marketplace.json`、
README、`agent-rules-setup` 裡的預設 URL 全部換掉。先 `bash localize.sh --dry-run`
可預覽。離線驗證：`bash skills-sync.sh --self-test`（plugin plan／guard／跨 agent／
external 四套全綠才算過）。

### 加自家 skill

用 `skill-author` skill 讓 AI 照標準產出（含 marketplace 註冊、弱模型五規則、validator
gate）；或人工照 [`CONTRIBUTING.md`](CONTRIBUTING.md)。merge 進 main 後全隊自動拿到。

### 加外部 / 第三方 skill

往 [`external-skills.json`](external-skills.json) 的 `skills` 加一筆——**單一來源**，
`skills-sync` 用它把外部 skill 裝進**所有**偵測到的 agent（含 Claude）：

```jsonc
{ "name": "<install id>", "url": "https://github.com/<owner>/<repo>.git", "ref": "main" }
```

- `ref` = branch／tag／sha。不設＝上游**預設分支**（吃該分支推來的任何 commit）；要穩定供應鏈
  就填某個 40 字元 sha 釘死。
- **不走 marketplace auto-update**：外部 skill 更新／新收錄，成員**重跑一次 `skills-sync`**
  （各 agent 一起帶到，含 Claude）。
- **不放進 `marketplace.json`**——那是 Claude 自家 bundle 的清單；外部 skill 一律只在
  external-skills.json（Claude 也從這裝，各 agent 用自己的原生機制，見〈外部開源 skills〉）。
- 搬內部：`localize.sh` 會把 external-skills.json 裡的 URL 一併換成 mirror。

### 改 agent-rules

- Constitution/Situations/playbook：直接改 md，merge 即生效（hook 現讀檔，全隊零動作）。
- guard pattern：改 [`agent-rules/hooks/guard.py`](agent-rules/hooks/guard.py) 的
  `PATTERNS` **和** `skills-sync.sh` 生成的 OpenCode JS 清單，**兩處同步**；
  `--self-test` 有 guard 單元測試擋回歸。
- 新的弱模型失敗模式 → [ANTIPATTERNS.md](agent-rules/rules/ANTIPATTERNS.md) 加一條
  （氣味要可機械自檢，改做要可執行）。

### 開發環境（devcontainer）

環境定義在 `.devcontainer/`：一個 `Dockerfile`（`python:3.14` image，**build 時就
`pip install -r requirements.txt`**，工具鏈烤進 image、隔離且可快取），devcontainer.json
用 `build.dockerfile`。VS Code「Reopen in Container」或 `devcontainer up` 即得完整環境。

驗證統一走 **pre-commit**（＝CI 的 gate，單一事實來源）：

```bash
pre-commit run --all-files     # 全部：black/flake8/mypy/pylint + pytest + validate + self-tests
pytest                         # 只跑測試（tests/，純 stdlib，任何裝了 pytest 的 python 都能跑）
```

`.pre-commit-config.yaml` 的 hooks 都是 `language: system`（用已裝的工具、不連外網），
CI 就是 `pre-commit run --all-files`。Python 測試在 [`tests/`](tests/)：每個 script 一個
`test_*.py`，正負案例並存（弄壞實作必轉紅）。**scripts 與測試邏輯本身純 stdlib**，
只有工具鏈（pytest＋linters）來自 `requirements.txt`。

不想／不能用 devcontainer：`pip install -r requirements.txt` 後照樣 `pre-commit run
--all-files`。需要在指定環境跑單一指令時用 `bash skills/skill-author/scripts/envrun.sh <指令>`
（自動判定容器內／起容器／host 直跑）。

### 組織 allow-list（給平台/IT 團隊，選用）

managed settings 用 `strictKnownMarketplaces` 的 `hostPattern`（regex）允許你的 git
host，全組織即可安裝。見官方「Manage plugins for your organization」。

---

# 設計原則

- **自包含**：每個 skill 一份 SKILL.md 讀完即可執行；工具放 `scripts/`（純 stdlib、零相依）。
- **清單即真相**：裝什麼以宣告檔為準（Claude 走 `marketplace.json`、跨 agent 走 `skills/`
  ＋ `external-skills.json`），`skills-sync.sh` 讀它們、不另維護名單。
- **hook 勝過 rules**：要保證載入的用 hook（常駐注入、機械攔截），rules/skill 只放按需內容
  ——rules 是勸，hook 是擋。
- **引用勝過快照**：hook 在 session 開頭現讀 marketplace 檔，改版全隊自動跟新，零嵌入複本。
- **弱模型優先**：規則寫成判準＋模板＋封閉分流（見
  [weak-model-rules](skills/skill-author/references/weak-model-rules.md)），最弱的模型走得完才算數。
- **別人的 dotfile 是別人的**：寫個人設定檔一律 opt-in、冪等、不碰無關內容、不覆蓋既有 hook。
