---
name: wiki-doc-author
description: 產出餵進 LLM 知識 wiki（llm-wiki processor）的源頭文件 —— 不管要記錄的是 HTTP API、cronjob/worker/CLI、還是純知識，都產一份合規 README，API 再附 openapi.json。processor 只吃兩種來源：openapi.json 與 README。新舊專案通用。開發者要寫或修這些文件時用。觸發詞 - "author wiki docs"、"幫我寫 wiki 文件"、"產 readme 給 processor"、"fix my openapi"、"補完 openapi"、"/wiki-doc-author"。
---

# wiki-doc-author

一份讀完就能做的 skill：教 AI agent 產出**餵進 LLM 知識 wiki 的源頭文件**。自包含 —— 規範、各框架
做法、範本、工具全在這一個檔（＋同目錄 `scripts/` 可執行工具）。丟進任何 repo 都能用，新舊專案皆可。

> **唯一心智模型 —— processor 只有兩個來源：`openapi.json` 與 `README`。**
> 每個要被記錄的東西**一律寫一份 README**（通用源頭）；只有「是 HTTP API 且框架能產 OpenAPI」時，
> 才**額外附一份 `openapi.json`**（endpoint 精準、不手抄）。其餘什麼都不用。

文件是給**語意搜尋（semantic search，向量比對語意）和 AI agent** 看的，不只給人。所以「過關」不是
「把範本填滿」，而是讓對面那個 agent 查得到、看得懂。

> **語言：全部用專案的 canonical 語言寫（預設中文）。** wiki 是**單語語料** —— README 摘要、endpoint
> 描述（含 OpenAPI 的 `summary=`，寫在 code 裡）、知識文件，都用同一種語言。原因：跨語言檢索（短文本）
> 弱，查詢端 agent 查詢前會把問題翻成這個語言，所以語料混語言會對不上。確定性 OpenAPI 匯入不經 LLM、
> 不會幫你翻譯，所以 `summary=` 一定要在 code 就寫成 canonical 語言。團隊用哪個語言由部署的
> `WIKI_QUERY_LANG` 決定。

## 決策樹：要記錄什麼？（先判斷，再走對應 Step 2 範本）

```
要記錄一個東西
   │
   ├─ 是 HTTP API 服務？
   │     ├─ 框架能產 OpenAPI（FastAPI / NestJS / Spring / DRF / Go …）→ Mode A：README + openapi.json
   │     └─ 不能 / 不想接                                              → Mode B：README 內含手寫 Endpoints 區
   │
   ├─ 是會「跑」但沒有 HTTP endpoint 的元件？（cronjob / worker / CLI / queue consumer …）
   │     └─ 元件 README：當 reference 知識文件，type: reference、tags 標類型（cronjob / worker / cli）
   │
   └─ 是純知識 / 說明？（runbook、概念、教學）
         └─ 知識 README：Diátaxis 分類 tutorial / how-to / reference / explanation
```

**關鍵規則：只有真的是 API 才寫 `METHOD /path` 行**（Mode B）。cronjob / worker 等**不要寫 endpoint
行**，否則 processor 會把它誤抽成 API。非 API 的會跑元件 = 知識文件 + tags，不需要也不可以有 endpoint。

## 什麼叫好（判斷，不是填空）

- **第一段＝被 embed 的摘要，是整份檔最重要的一行。** 用使用者會拿去搜的字眼，一兩句講清楚
  *這東西在幹嘛、何時會用到*。不要把 H1 重講一遍。
  - 差：「這是 Payments API」「nightly job」。
  - 好：「對已存信用卡扣款、退款給客戶」「每晚 02:00 對到期帳單扣款並寫結果到 billing.results」。
- **描述講意圖，不是語法。** `POST /payments/refund — 退款給客戶` 勝過 `— 退款端點`；
  cronjob 寫「做什麼、何時觸發、影響什麼」勝過「一支排程」。
- **有範例 / error / 排程細節就寫**，這對 AI 讀者價值最高（學到形狀，不只名字）。
- 只把範本弄到 linter 過、卻沒做到上面，就是沒做到真正的事。

## Step 1 — 認種類 + （API）選模式

API 才需要判模式：這個 app 的框架能不能**離線/build 時匯出 OpenAPI 成檔**？能 → Mode A，不能 → Mode B。

| 框架 | 匯出 openapi 成檔（離線/build） | 模式 |
|---|---|---|
| **FastAPI / Starlette**（有 `.openapi()`） | `python scripts/gen_openapi.py --app <module>:<attr>`（例 `app.main:app`） | A |
| **NestJS**（TS） | bootstrap 用 `SwaggerModule.createDocument()` → `fs.writeFileSync('openapi.json', …)`，包成 `npm run gen:openapi` | A |
| **Spring Boot**（springdoc） | `springdoc-openapi-maven-plugin`（build 期匯出，不必起服務） | A |
| **Django + DRF**（drf-spectacular） | `python manage.py spectacular --file openapi.yaml`（純離線） | A |
| **Go**（swaggo/swag） | `swag init`（從註解產 `docs/swagger.json`） | A |
| **其他能產 OpenAPI 的** | 跑該框架的匯出器產出 spec 檔 | A |
| **不是 HTTP API / 不能產 / 不想接** | —— | B |

`scripts/gen_openapi.py` 對 `.openapi()` 那種：import app → 寫 `openapi.json`；**不適用就優雅 exit 0
不擋**（提示走 Mode B）。其他框架把 Step 3 hook 的 `entry` 換成上表對應指令即可。

## Step 2 — 寫 README（依種類選一個範本）

frontmatter 三欄：`type`（受控）、`source_app`（小寫-連字號，穩定識別）、選填 `tags`（小寫-連字號）。
`type` 受控值只有：`api | tutorial | how-to | reference | explanation`（其餘 linter 擋）。
body：H1；**第一段＝摘要**；其餘依範本。寫完跑 `python scripts/lint_frontmatter.py <file>` 必須 pass。

**範本 1 — API（Mode A，有 openapi.json）**
```markdown
---
type: api
source_app: payments-api
tags: [billing, payments]
---

# Payments API

對已存信用卡扣款、退款給客戶。   ← 第一段＝摘要（被 embed）

## 使用方式
- 設定 `PAYMENTS_API_KEY`；base URL `…`。
（endpoint 不用寫 —— 由 committed openapi.json 帶，processor 走確定性轉換）
```

**範本 2 — API（Mode B，沒有 openapi.json，手寫 endpoint）**
```markdown
---
type: api
source_app: legacy-billing
tags: [billing]
---

# Legacy Billing API

對舊系統收款與退款。   ← 摘要

## Endpoints
POST /charge — 對信用卡扣款收取款項
POST /refund — 退款給客戶
GET  /balance — 查目前餘額
```
每行 `METHOD /path — 意圖`；`— 意圖` 會被當 description（影響語意搜尋），寫清楚做什麼。

**範本 3 — 非 API 會跑元件（cronjob / worker / CLI）**
```markdown
---
type: reference
source_app: billing-nightly
tags: [cronjob]
---

# Nightly Billing Job

每晚 02:00 UTC 對到期帳單扣款，結果寫到 billing.results。   ← 摘要（沒有 endpoint）

## 觸發 / 排程
- cron `0 2 * * *`（UTC）。
## 輸入 / 輸出
- 讀 `invoices`（status=due）；寫 `billing.results`、發 `billing.charged` 事件。
## 副作用 / 失敗模式
- 對外金流不可逆；失敗重跑安全（冪等鍵 invoice_id）。
```
（worker 換 `tags:[worker]`、CLI 換 `tags:[cli]`，結構相同：用途/觸發/輸入輸出/副作用。**不寫 endpoint 行**。）

**範本 4 — 純知識 / 說明（Diátaxis）**
```markdown
---
type: how-to
source_app: oracle-kb
tags: [oracle, recovery]
---

# 從誤刪救回資料

當資料被誤刪，用 Oracle Flashback 在不還原備份下回溯。   ← 摘要

## 步驟
- ...
```
`type` 依**讀者意圖**選：tutorial（帶著做）/ how-to（解決問題）/ reference（查閱事實）/ explanation（概念）。

## Step 3 — （僅 API Mode A）接 OpenAPI freshness + 完整度

讓 committed 的 `openapi.json` 每次 push 都最新。把同目錄 `scripts/` 的工具複製進 app 的 `scripts/`，
加 `.pre-commit-config.yaml`：
```yaml
repos:
  - repo: local
    hooks:
      - id: gen-openapi            # 重生 openapi.json 並納入這次 commit（非 FastAPI 換成上表指令）
        name: regenerate openapi.json
        entry: python scripts/gen_openapi.py --app app.main:app
        language: system
        pass_filenames: false
        always_run: true
      - id: openapi-completeness   # 缺 description/範例/error → 擋下 commit
        name: openapi completeness gate
        entry: python scripts/openapi_completeness.py --fail
        language: system
        pass_filenames: false
        always_run: true
      - id: frontmatter-lint
        name: frontmatter lint
        entry: python scripts/lint_frontmatter.py
        language: system
        files: '\.md$'
```
`pre-commit install` 後，commit 時自動重生 + 把缺漏擋在當下。Mode B / 非 API 只留 `frontmatter-lint` 一個 hook。

**補完缺漏 = 改程式碼，不是改 openapi.json（它由 code 生會被蓋）：**

| 缺漏 | FastAPI | 通則 |
|---|---|---|
| endpoint 沒描述 | route `summary=`/`description=` 或 docstring | 該 operation 的標註 |
| 參數沒描述 | `Query(..., description=…)` / `Path(...)` | 該參數的標註 |
| 缺範例 | `responses={200:{"content":{...:{"example":…}}}}` 或 Pydantic `json_schema_extra` | schema 的 `example` |
| 缺 error | `responses` 補 4xx/5xx + schema | 宣告 error 狀態碼 + schema |

改完重生（`gen_openapi.py`），再 `openapi_completeness.py openapi.json --fail` 到乾淨。

## Step 4 — 推送 + 驗證查得到

本地測試 push（README ＋可選 openapi）：
```bash
python - <<'PY'
import json, os, urllib.request
md = {"README.md": open("README.md", encoding="utf-8").read()}
body = {"markdowns": md, "timestamp": "t", "trigger_info": {},
        "source_app": "payments-api", "source_version": "local"}
if os.path.exists("openapi.json"):
    body["openapi"] = json.load(open("openapi.json", encoding="utf-8"))   # 有就附 → 確定性匯入
req = urllib.request.Request("http://localhost:8001/process",
    data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
print(json.load(urllib.request.urlopen(req, timeout=120))["status"])
PY
```
正式環境由 CI 自動做（push 時附 committed openapi.json）。**用「使用者會打的句子」搜確認**（不是用標題）：
```bash
curl 'localhost:8002/search_apis?query=退款給客戶'
curl 'localhost:8002/search_knowledge?query=每晚扣款&type=reference'
```

## 既有專案 retrofit

先讀 repo 認種類/框架，再回填：
- API？找 uvicorn/ASGI target（`app.main:app`）、`FastAPI(`、`@app.get`、或 swagger 設定 → Step 1 表選模式。
- cronjob/worker？找 crontab / k8s CronJob / Celery beat / scheduler 設定 → 範本 3。
- 其餘散文 → 範本 4。
新專案則一開始就照範本寫。

## 附錄 — §Ingestion（processor 怎麼吃；綁 llm-wiki 後端）

- push 目標：`POST <processor>/process`，body `{"markdowns": {"README.md": ...}, "source_app", "source_version",
  "openapi": <spec dict 選填>, "timestamp", "trigger_info"}`。
- **兩來源**：有 `openapi` → endpoint 從 spec **確定性**匯入（不走 LLM、不撞限流、不幻覺）；
  沒有 → README 的 `METHOD /path — 意圖` 行由 LLM 抽取。README 第一段兩種都會被 embed。
- frontmatter `type`/`tags` 會存、可查（`search_apis`、`search_knowledge?type=…`）。

工具（同目錄）：`scripts/gen_openapi.py`、`scripts/openapi_completeness.py`、`scripts/lint_frontmatter.py`、
`scripts/frontmatter.schema.json`（純 stdlib，無相依）。
