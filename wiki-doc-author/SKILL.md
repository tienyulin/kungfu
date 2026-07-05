---
name: wiki-doc-author
description: 產出餵進 LLM 知識 wiki（llm-wiki processor）的源頭文件 —— 不管要記錄的是 HTTP API、cronjob/worker/CLI、還是純知識，都產一份合規 README，API 再附 openapi.json。processor 只吃兩種來源：openapi.json 與 README。新舊專案通用。開發者要寫或修這些文件時用。Triggers - "author wiki docs"、"幫我寫 wiki 文件"、"產 readme 給 processor"、"fix my openapi"、"補完 openapi"、"/wiki-doc-author"。
---

# wiki-doc-author

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 認種類（決策樹分流，monorepo 先定 source_app 切法）
- [ ] Step 2 README + docs/ 寫完（散裝知識檔搬進 docs/ 後【刪原檔】），lint_frontmatter pass
- [ ] 事實溯源自查：README/docs 裡每個 env 名、數字、URL、行為描述都在 repo 或使用者輸入
      找得到出處；查無的已改寫成「待補：<問題>」並列出要問使用者的清單
- [ ] Step 3（僅 Mode A）openapi 匯出 + completeness 乾淨 + pre-commit 接好
- [ ] Step 4 CI 接好（或規劃）；本地 push/搜尋驗證（選配）
```

**內容鐵律：wiki 是事實語料，寫錯比寫少嚴重。** 文件內容只能來自 repo 可觀察事實
（code、設定、註解）或使用者親口提供；查無的細節在**正文原地**寫「（待補：<要問什麼>）」
佔位，**禁止發明一個像樣的值再標待補**（發明的 env 名看起來像真的，比空缺更毒），
更**禁止用「常見做法/合理假設」補**（例：來源寫「重試 2 次」就寫 2 次，不要腦補成
指數退避）。

**範圍鐵律：本 skill 只建/改文件**（README、`docs/*.md`、`scripts/` 文件工具、
pre-commit 設定）。**絕不刪除、移動或修改 repo 的程式碼與其他檔案** ——
「搬進 docs/ 後刪原檔」只適用散裝的 .md 知識檔，程式碼（含 cron 腳本、設定檔）
一律原地不動。

**心智模型：processor 只有兩個來源 —— `openapi.json` 與 `README`。**
每個要被記錄的元件寫一份 README；只有「是 HTTP API 且框架能匯出 OpenAPI」才額外附
`openapi.json`（endpoint 走確定性匯入，不手抄）。其餘什麼都不用。

兩條全域規則：

- **語言**：整份語料單語。README、endpoint 描述（含 code 裡 OpenAPI 的 `summary=`，匯入不翻譯）
  全用團隊的 canonical 語言 —— 不確定是哪個就**問使用者**（無法互動才 fallback 中文）。
  查詢端會把問題翻成這個語言再搜，混語言 = 搜不到。
- **檔案佈局：一個 codebase（package）= 一個 `source_app` = 一次 push。** 一次 push 的內容 =
  該服務的 `README.md`（主文件）＋ `docs/**/*.md`（其他知識文件，**檔名自由**、kebab-case，
  每檔自己的 frontmatter）—— 多份 runbook 就是 `docs/` 下多個 .md，不用改名 README。
  - **以 codebase 劃界，不以部署劃界**：同 package 的 celery worker / 內建排程即使獨立
    container 部署，也不是獨立元件、不開新 source_app。落點判準：**一兩句話講得完**
    （排程＋做什麼）→ 寫進該服務 README 的「背景工作」一節；**有完整的觸發/輸入輸出/
    失敗模式可寫** → `docs/` 一份範本 3 格式的 reference 檔（可被 type/tag 過濾檢索）。
  - `source_app` = 該 codebase 的主服務名（CI 預設 repo 名，monorepo 用 `SOURCE_APP`
    覆寫成該服務的部署名 —— 查部署設定（k8s/compose），查無就問使用者）。README 與
    `docs/` 每檔 frontmatter 的 `source_app` 都必須等於它（整包一致）。同 source_app
    重 push = 整包替換該 app 的資料。
  - **repo 本身就是該服務**（最常見）→ root README 就是主文件，照範本寫/retrofit ——
    frontmatter + 好摘要不妨礙人類讀，專案說明與 wiki 文件是同一份。
  - **monorepo**（服務在子目錄）→ 各服務目錄各自 README + docs/、各自 source_app、CI
    分開 push（CI template 要改編，見 Step 4）；此時 root README 是純專案說明、不進 wiki。

## Step 1 — 認種類（先偵察，再走對應範本）

既有專案先讀 repo 找訊號：ASGI target（`app.main:app`）、`FastAPI(`、swagger 設定 → API；
crontab / k8s CronJob / Celery beat → cronjob；其餘散文 → 知識。新專案直接判斷：

```
要記錄一個東西
   ├─ HTTP API 服務？
   │     ├─ 框架能匯出 OpenAPI（FastAPI/NestJS/Spring/DRF/Go…，見 references/frameworks.md）
   │     │                                  → Mode A：README + openapi.json
   │     └─ 不能 / 不想接                    → Mode B：README 內含手寫 Endpoints 區
   ├─ 會「跑」但沒有 HTTP endpoint？（cronjob / worker / CLI / queue consumer）
   │     └─ 範本 3：type: reference + tags 標類型。不寫 endpoint 行。
   └─ 純知識 / 說明？（runbook、概念、教學）
         └─ 範本 4：type 選 tutorial / how-to / reference / explanation
```

**只有真的是 API 才寫 `METHOD /path` 行**，否則 processor 會把 cronjob 誤抽成 API。

## Step 2 — 寫 README（選一個範本）

frontmatter 三欄：`type`（受控值只有 `api | tutorial | how-to | reference | explanation`）、
`source_app`（小寫-連字號）、選填 `tags`（小寫-連字號）。寫完跑
`python "${CLAUDE_SKILL_DIR}/scripts/lint_frontmatter.py" README.md docs/` 必須 pass
（`${CLAUDE_SKILL_DIR}` 沒展開就用 SKILL.md 所在目錄的絕對路徑）。

**第一段＝被 embed 的摘要，是整份檔最重要的一行。** 用使用者會拿去搜的字眼講「這東西在幹嘛、
何時會用到」，不要重講 H1。描述講意圖不是語法；有範例 / error / 排程細節就寫。

- 差：「這是 Payments API」「nightly job」
- 好：「對已存信用卡扣款、退款給客戶」「每晚 02:00 對到期帳單扣款並寫結果到 billing.results」
- 拿不準就照這個公式填：「對 <對象> 做 <動作>（<關鍵細節：時間/冪等/去向>）。<誰在什麼情況> 會用到。」

**範本 1 — API（Mode A，endpoint 由 openapi.json 帶，README 不寫）**
```markdown
---
type: api
source_app: payments-api
tags: [billing, payments]
---

# Payments API

對已存信用卡扣款、退款給客戶。

## 使用方式
- 設定 `PAYMENTS_API_KEY`；base URL、認證方式、常見錯誤與重試建議寫在這。
```

**範本 2 — API（Mode B，手寫 endpoint）**
```markdown
---
type: api
source_app: legacy-billing
tags: [billing]
---

# Legacy Billing API

對舊系統收款與退款。

## Endpoints
POST /charge — 對信用卡扣款收取款項
POST /refund — 退款給客戶
GET  /balance — 查目前餘額
```
每行 `METHOD /path — 意圖`；`— 意圖` 就是 description，直接影響語意搜尋。

**範本 3 — 非 API 會跑元件（cronjob / worker / CLI）**
```markdown
---
type: reference
source_app: billing-nightly
tags: [cronjob]
---

# Nightly Billing Job

每晚 02:00 UTC 對到期帳單扣款，結果寫到 billing.results。

## 觸發 / 排程
- cron `0 2 * * *`（UTC）。
## 輸入 / 輸出
- 讀 `invoices`（status=due）；寫 `billing.results`、發 `billing.charged` 事件。
## 副作用 / 失敗模式
- 對外金流不可逆；失敗重跑安全（冪等鍵 invoice_id）。
```
worker 換 `tags:[worker]`、CLI 換 `tags:[cli]`，結構同：用途/觸發/輸入輸出/副作用。

**範本 4 — 純知識（Diátaxis，依讀者意圖選 type）**
```markdown
---
type: how-to
source_app: oracle-kb
tags: [oracle, recovery]
---

# 從誤刪救回資料

當資料被誤刪，用 Oracle Flashback 在不還原備份下回溯。

## 步驟
- ...
```
tutorial（帶著做）/ how-to（解決問題）/ reference（查閱事實）/ explanation（概念）。

**Retrofit 既有 README**：保留原內容，頂部插 frontmatter、把第一段改寫成合格摘要即可，
不另開新檔（frontmatter 在 GitHub 會渲染成表格，無害）。既有的散裝知識檔（`runbooks/`
之類非 `docs/` 的 .md）→ **搬進 `docs/`**（不是複製 —— 單一事實來源；CI 只蒐集
README + `docs/`）。

## Step 3 —（僅 Mode A）匯出 OpenAPI + 保鮮

FastAPI：`python "${CLAUDE_SKILL_DIR}/scripts/gen_openapi.py" --app app.main:app` → 產
`openapi.json`（不適用會 exit 0 提示走 Mode B）。其他框架的匯出指令見
[references/frameworks.md](references/frameworks.md)。

把本 skill 目錄的 `scripts/` **四檔**複製進**該服務目錄**的 `scripts/`（三支工具 +
`frontmatter.schema.json` —— lint 執行時讀同目錄的 schema，漏了會炸）；
`.pre-commit-config.yaml` 放 **repo root**（pre-commit 只認 root；已有就 append hooks），
monorepo 時 hook 的 `entry` 與 `--app` 用該服務的相對路徑。每次 commit 自動重生 + 擋缺漏：

```yaml
repos:
  - repo: local
    hooks:
      - id: gen-openapi            # 非 FastAPI 換成 frameworks.md 對應指令
        name: regenerate openapi.json
        # PYTHONPATH=. 必要：少了它 app import 失敗，而工具「不適用就 exit 0」
        # 的優雅降級會把失敗誤裝成「走 Mode B」，hook 形同虛設
        entry: env PYTHONPATH=. python scripts/gen_openapi.py --app app.main:app
        language: system
        pass_filenames: false
        always_run: true
      - id: openapi-completeness   # 缺 description/範例/error → 擋 commit
        name: openapi completeness gate
        entry: python scripts/openapi_completeness.py --fail
        language: system
        pass_filenames: false
        always_run: true
      - id: frontmatter-lint
        name: frontmatter lint
        entry: python scripts/lint_frontmatter.py
        language: system
        files: '(^|/)(README\.md|docs/.*\.md)$'   # 只驗會被 push 的檔（README + docs/）
```
Mode B / 非 API 只留 `frontmatter-lint`。root README **不進 wiki** 的少數情況（純說明文件、
另有服務目錄）→ 把 `files` 縮成該服務的路徑（例 `^services/api/(README\.md|docs/.*\.md)$`）。repo 沒有
Python 工具鏈（純 Node/Go）就不接 pre-commit，lint 交給 CI（見 Step 4 的 CI 節，
CI 用 python image 跑，跟 repo 語言無關）。

**補完缺漏一律改 code，不改 openapi.json（重生會蓋掉）**：改哪裡見
[references/frameworks.md](references/frameworks.md) §補漏對照。改完重生、跑
`openapi_completeness.py openapi.json --fail` 到乾淨。

## Step 4 — 接 CI + 驗證

**CI（正式的 push 途徑）**：GitLab CI include 平台 repo（llm-wiki-mcp）的
`ci-templates/generate-and-push-wiki.yml` —— 它在 main 分支上 lint（frontmatter +
openapi 完整度/新鮮度）→ 蒐集 root `README.md` + `docs/**/*.md`（有 openapi.json 一併附上）
→ 打 `$WIKI_PROCESSOR_URL/process`，`status != success` 即 fail。要設的變數：
`WIKI_PROCESSOR_URL`（問團隊部署）、選填 `SOURCE_APP`（預設 repo 名）、
`PROCESSOR_API_KEY`（processor 有開 auth 時）。

Template 的蒐集範圍是為「repo = 一個服務」的佈局設計的。**monorepo → 複製 template
改編**：每個服務一組 lint + push job，蒐集路徑、lint 路徑、`scripts/` 位置、`SOURCE_APP`
全換成該服務的（yml 內就是幾行 glob 與路徑，直接改）。**非 GitLab 平台 → 照 Step 4.2 的 push body 格式自寫**
（那段 python 就是完整的 push 實作，搬進你的 CI 即可）。

**本地驗證**：

1. `lint_frontmatter.py` pass（必要）。
2. 本地 push 實測（**選配** —— 需要跑著的 processor；沒有就跳過，交給 CI）：
```bash
python - <<'PY'
import json, os, urllib.request
md = {"README.md": open("README.md", encoding="utf-8").read()}
body = {"markdowns": md, "timestamp": "t", "trigger_info": {},
        "source_app": "payments-api", "source_version": "local"}   # source_app 同 frontmatter
if os.path.exists("openapi.json"):
    body["openapi"] = json.load(open("openapi.json", encoding="utf-8"))
req = urllib.request.Request("http://localhost:8001/process",   # processor URL 依部署換
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
print(json.load(urllib.request.urlopen(req, timeout=120))["status"])
PY
```
3. 有 push 的話，用「使用者會打的句子」搜（不是標題）：
```bash
curl 'localhost:8002/search_apis?query=退款給客戶'
curl 'localhost:8002/search_knowledge?query=每晚扣款&type=reference'
```
`search_*` 推完即時可搜；`list_knowledge`/`get_knowledge` 讀的彙總視圖要等批次
`rebuild-concepts` 才更新 —— 驗證一律用 search，別拿 list/get 判斷推送失敗。

## 工具（本 skill `scripts/`，純 stdlib）

| 工具 | 用途 |
|---|---|
| `gen_openapi.py` | 從 FastAPI app 匯出 openapi.json |
| `openapi_completeness.py` | 檢查 description/範例/error 缺漏（`--fail` 擋 CI/commit） |
| `lint_frontmatter.py` | 驗 README frontmatter（type 受控值、source_app 格式） |

frontmatter 的 `type`/`tags` 會進 wiki、可用 `search_knowledge?type=…&tag=…` 過濾。
