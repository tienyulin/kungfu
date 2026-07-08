---
name: skill-author
description: 在這個 kungfu repo 裡新增或修改一個 skill（跨 agent：Claude Code／Gemini／Codex／OpenCode／Cline 都吃同一份），並讓它可被安裝。照官方 Agent Skills spec + 本 repo 慣例產出合規 SKILL.md、scripts/references，並註冊進 .claude-plugin/marketplace.json。開發者想加/改 skill 時用。Triggers - "寫一個 skill"、"新增 skill"、"author a skill"、"add a skill to kungfu"、"/skill-author"。
---

# skill-author

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] 確認 cwd = repo root（.claude-plugin/marketplace.json 存在）
- [ ] Step 1 命名 + 建目錄
- [ ] Step 2 SKILL.md（frontmatter + body；弱模型五規則套過）
- [ ] Step 3 marketplace.json 兩處
- [ ] Step 4 validator 全綠（+ 乾淨環境才 install 實測）
```

在本 repo 新增一個**可安裝**的 skill。心智模型：一個 skill = 一個資料夾
（`skills/<name>/SKILL.md` ＋ 選填 `scripts/`、`references/`）放在 `skills/` 子目錄下
（superpowers-style 佈局），再在 `.claude-plugin/marketplace.json` 註冊。

**先確認位置**：所有指令都要在 kungfu repo root 下執行 —— 判別法：cwd 有
`.claude-plugin/marketplace.json`。（這個 repo 常是別的專案的 submodule，路徑通常是
`<專案>/.claude/skills/`；每條指令前 `cd` 過去或用 `cd … &&` 前綴。）

**修改既有 skill**：跳過 Step 1、3（已註冊），直接改內容 → Step 4 驗證（已裝過的機器
install 實測也跳過，見 Step 4）。用途/description 有變 → 同步改 marketplace 條目的英譯
description。改名 = 當新增走全流程 ＋ 刪舊目錄與 marketplace 舊條目。

**git 收尾不在本 skill 範圍**：照 repo 慣例 branch → PR；merge 進 main 後全隊才會自動拿到
（marketplace auto-update）。本 repo 若是別的專案的 submodule，提醒使用者該專案照慣例
bump submodule pointer，否則該 checkout 內載入的仍是舊版。

## Step 1 — 命名 + 建目錄

- `name`：kebab-case、≤64 字、須等於目錄名（其餘格式規則 validator 會擋，不用背）。
- `mkdir skills/<name>`，放 `SKILL.md`（＋需要時 `scripts/`、`references/`）。

## Step 2 — 寫 SKILL.md

frontmatter 只要兩欄：

```yaml
---
name: <name>                 # = 目錄名
description: <做什麼 + 何時用>。Triggers - "<中文觸發句>"、"<english trigger>"、"/<name>"。
---
```

**description 決定 skill 會不會被選中**，是最關鍵的一欄：
- 第三人稱、≤1024 字，講 what + when，結尾 `Triggers -` 列具體中英觸發句。
- 「稍微 pushy」= 把使用時機寫寬、觸發句寫多（模型傾向 under-trigger）。
  例：「開發者要寫或修這些文件時用」勝過「可用於文件撰寫」。

**body**（≤500 行，超過就拆進 `references/`）：
- 寫到「讀完即可執行」：步驟依執行順序排、給可照抄的範本/指令、結尾放完成定義。
  **結構照本檔與 repo 既有 skill**（開頭心智模型 → Step 1..N → 完成定義）。
- **弱模型相容（必讀）**：團隊執行模型能力參差，skill 要寫到最弱的模型也走得完 ——
  現在去讀 [references/weak-model-rules.md](references/weak-model-rules.md)，
  五條硬規則（低自由度、封閉分流、機器 gate、進度 checklist、未定義=停）逐條套用。
- 只寫模型不知道的事（專案慣例、格式、字面值）；通識解釋、行銷句、版本沿革都不放。
- prose 中文，專有名詞英文＋首次出現一句解釋。
- 引用只深一層（`references/X.md`），不要 `../`。
- `scripts/`：純 stdlib、零相依、錯誤訊息清楚；不可引用 skill 目錄外的檔
  （安裝時只複製 skill 目錄）。

## Step 3 — 註冊進 marketplace（必做，否則裝不到）

`.claude-plugin/marketplace.json`（**純 JSON，不能有註解**）要改**兩處**：

**① `plugins` 陣列加自身項目**（照既有條目的欄位風格；`category`/`keywords` 自由字串）：
```json
{
  "name": "<name>",
  "source": "./",
  "strict": false,
  "description": "<frontmatter description 的英譯（濃縮版即可）>",
  "author": { "name": "tienyulin" },
  "keywords": ["..."],
  "category": "workflow",
  "skills": ["./skills/<name>"]
}
```

**② 把 `"./skills/<name>"` 加進既有 bundle plugin（`"name": "kungfu"` 那個條目）的
`skills` 陣列**——它長這樣，只動它的 `skills`（bundle 的 description 刻意不枚舉成員
名單，不用改）：
```json
{
  "name": "kungfu",
  "source": "./",
  "description": "Bundle — installs this repo's own skills at once (…)",
  "skills": ["./skills/wiki-doc-author", "./skills/sop-to-spec", "./skills/<name>"]
}
```
成員裝的是 bundle ＋ marketplace auto-update：skill 進 bundle、merge 進 main，
全隊下次開 session 自動拿到。**不設 `version` 欄** —— 沒有它，git commit SHA 就是
版本，每個 commit 都算新版；設了反而要手動 bump，漏 bump = 收不到更新。

這步接的是 **Claude 通道**（marketplace + validator gate）。skill 是**跨 agent** 的：
只要它在 `skills/` 下，Gemini／Codex／OpenCode／Cline 各家 adapter（`gemini-extension.json`、
`.codex-plugin/`、`.opencode/`、Cline skill-drop）會自動撿到同一份，不必另外註冊。

## Step 4 — 驗證

```bash
# 1) 離線 validator（頂替需外網的官方 skills-ref；含 marketplace 註冊/bundle/version/
#    envrun 同步檢查）。經 envrun 跑 = 用本 repo 的 devcontainer（沒起且有 CLI 會自動起）
bash skills/skill-author/scripts/envrun.sh python3 skills/skill-author/scripts/validate_skill.py <name>   # 或不帶參數驗全部
```
envrun exit 2（起不了容器）時的**唯一例外**：validator 本身純 stdlib，可直接
`python3 skills/skill-author/scripts/validate_skill.py` host 直跑；black/mypy 等其他工具鏈
指令不適用此例外——照 envrun 印出的選項原樣轉述給使用者選（只轉述，不代跑）。

2) 本地安裝實測 —— **先查這台機器有沒有已註冊的同名 marketplace**：
```bash
claude plugin marketplace list | grep kungfu
```
- **已註冊**（團隊成員機器的常態）→ **跳過實測**：不要 add/remove —— remove 會把
  使用者正在用的 bundle 連 plugins 一起拔掉。validator + PR CI 已足夠。
- **未註冊**（乾淨環境）→ 實測後移除（中途失敗也要跑最後一行，別把設定殘留在 user scope）：
```bash
claude plugin marketplace add "$PWD"
claude plugin install <name>@kungfu    # <name>@<marketplace.json 頂層 name>
claude plugin list | grep -A3 <name>            # Status 行應為 enabled（不在名稱同一行）
claude plugin marketplace remove kungfu   # 會連同其 plugins 一起移除
```

## 完成定義

validator 擋的（跑 `validate_skill.py <name>` 全綠即代表）：
- [ ] 目錄名 = frontmatter `name`（kebab/長度）
- [ ] description 有 `Triggers -` 觸發句
- [ ] marketplace.json 兩處都改（自身 plugin ＋ bundle `skills`）、無 `version` 欄

自查的（validator 不驗語意）：
- [ ] description 第三人稱、what+when、觸發句中英都有
- [ ] body 讀完即可執行；≤500 行（validator 只警告，超過就拆 references/）
- [ ] 弱模型五規則過（weak-model-rules.md）：關鍵步驟有逐字可抄物或機器 gate、
      判斷點封閉分流、多步驟有進度 checklist、有「未定義=停」護欄
- [ ] scripts 純 stdlib、不引用 skill 目錄外的檔
- [ ] 乾淨環境才做的 install 實測（已註冊 marketplace 的機器跳過，見 Step 4）
