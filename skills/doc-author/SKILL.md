---
name: doc-author
description: 幫一個 repo 寫出「人與 AI 都讀得懂」的兩份文件 —— README.md（repo 本體：AI 讀完不用重掃 repo 就能動工的系統地圖）＋ docs/usage.md（對外使用者文件，單檔自足、可上傳文件平台）。API repo 另附 openapi.json（從 code 匯出，不手抄）。新舊專案通用。Triggers - "寫 repo 文件"、"補 README"、"寫使用文件"、"寫給 AI 看的 README"、"author docs"、"fix my openapi"、"/doc-author"。
---

# doc-author

**開工前：把下面的進度清單照抄進你的回覆，每完成一步打勾再做下一步。**
遇到本 skill 與 references 都沒定義的情況：停下來問使用者，不要自行發明。

```
進度：
- [ ] Step 1 認種類（偵察 repo，判定要產哪幾份）
- [ ] Step 2 README.md 寫完（四卡點範本）＋ lint_anchors pass
- [ ] Step 3（僅 API）openapi 匯出 + completeness 乾淨
- [ ] Step 4（僅對外元件）docs/usage.md 寫完＋自足檢查
- [ ] Step 5 事實溯源自查＋回報（含待補清單）
```

**內容鐵律：文件是事實，寫錯比寫少嚴重。** 內容只能來自 repo 可觀察事實（code、設定、
註解）或使用者親口提供；查無的細節在**正文原地**寫「（待補：<要問什麼>）」佔位，
**禁止發明一個像樣的值再標待補**（發明的 env 名看起來像真的，比空缺更毒），更**禁止用
「常見做法/合理假設」補**（例：來源寫「重試 2 次」就寫 2 次，不要腦補成指數退避）。

**範圍鐵律：本 skill 只建/改文件**（README、`docs/`、`scripts/` 文件工具、pre-commit
設定）。**絕不刪除、移動或修改 repo 的程式碼與其他檔案。**

## 心智模型：兩個讀者、兩份文件

| 文件 | 讀者 | 目的 | 什麼時候要 |
|------|------|------|-----------|
| `README.md`（repo 根） | 維護者＋**AI agent** | 讀完建立心智模型直接動工，**不用重掃 repo** | 每個 repo 都要 |
| `docs/usage.md` | 對外使用者（call API / 用工具的人） | 單檔自足的「怎麼用」，可整份上傳文件平台 | 有對外介面才要（API / 對外 CLI）；純內部 library、純知識 repo 不用 |
| `openapi.json` | 使用者＋工具 | endpoint 權威細節 | 是 HTTP API 且框架能匯出才附（Step 3） |

## Step 1 — 認種類（先偵察，再決定產哪幾份）

讀 repo 找訊號：ASGI target（`app.main:app`）、`FastAPI(`、swagger 設定 → **API**；
crontab / k8s CronJob / Celery beat / CLI entrypoint → **會跑的非 API 元件**；
被 import 用的套件 → **library**；其餘散文 → **純知識**。

| 種類 | 產出 |
|------|------|
| HTTP API | README ＋ usage.md ＋ openapi.json（可匯出時） |
| cronjob / worker / CLI | README（觸發、輸入輸出、副作用寫進對應節）；CLI 有外部使用者 → 加 usage.md |
| library / 純內部 | README 就好 |
| 純知識 repo | README（架構節換成內容地圖：哪類知識放哪個檔） |

monorepo（多服務同 repo）→ 各服務目錄各自一份 README＋usage.md，root README 只做
索引（一表：服務 → 一句話 → 路徑）。

## Step 2 — README.md（repo 本體，AI-first）

**設計出發點：現代模型讀 code 快、grep 便宜。** 會逼 AI 重掃全 repo 的只有四種東西，
README 就解這四題，其他不寫（prose 敘事、目錄樹逐層註解、mermaid 都是給人的糖，
模型吃表格與字面識別字更準）：

| AI 的卡點 | README 給的解 |
|-----------|--------------|
| grep 不到的領域知識 | `## 名詞對照`：業務詞 ↔ code 識別字 |
| 不知從哪改起 | `## 常見任務`：做 X → 動哪些檔 → 抄哪個 pattern → 怎麼驗 |
| 不敢信文件（怕 stale） | 全文只用可驗證地標（真實路徑/符號/env 名，**禁行號**）＋ anchor lint 機器驗 |
| code 看不出來的 why | `## 契約與不變量`：error 形狀、排序保證、「別修的怪東西＋為什麼」 |

格式規則：一事一 bullet；可枚舉事實用表；指令一律可貼上執行並附一行「成功長怎樣」——
**寫進文件的指令你要自己跑過**，跑不了（依賴壞、缺環境）就在該指令區塊旁標
「（待補：未驗證——<原因>）」，只在回報裡講、文件裡不標＝讀者不知道；
字面識別字原樣寫（讓模型拿去 grep 跳轉）；控制在一頁上下——**但四卡點的資訊寧全勿省**，
精簡是砍修辭不是砍事實。

範本（節依序；不適用的節寫「無」或整節略去，略去要在 Step 5 回報說明）：

```markdown
# <repo 名>

<3 句：這是什麼、給誰用、目前狀態（正式營運/開發中/實驗）。>

## 名詞對照

| 領域詞 | code 裡的識別字 | 說明 |
|--------|----------------|------|
| 回收筒 | `RECYCLEBIN`（Oracle 檢視） | 被刪的表暫存處 |

## 常見任務

| 要做什麼 | 動哪些檔（順序） | 照哪個既有 pattern | 怎麼驗證 |
|----------|-----------------|-------------------|---------|
| 加一個新 endpoint | `api/routes.py` → `service/` → `models/schemas.py` | 抄 restore_table 那組 | `pytest tests/` |

## 指令

（跑起來 / 測試 / lint 各一個 bash 區塊，可直接貼上執行，每塊附註解一行「成功長怎樣」。）

## 架構

- 分層與呼叫方向：`api/`（HTTP 層）→ `service/`（業務規則）→ `repository/`（外部系統存取）
- 外部系統：<資料庫/佇列/第三方，各一句「用來做什麼、mock 在哪」>
- ls 看不出來的：<哪些目錄是產生的/棄用的/vendored；沒有就「無」>

## 契約與不變量

- 錯誤回傳形狀：<逐欄位寫死>
- <排序/相容/冪等保證，逐條>
- 別修的怪東西：<現象＋為什麼是故意的；沒有就「無」>

## 環境變數

| 名稱 | 預設 | 作用 |
|------|------|------|

---
對外使用文件：`docs/usage.md`（上傳至 <平台名>）。
<!-- 更新規則：動到目錄結構、入口、資料流、契約的 PR 必須同步改本檔；scripts/lint_anchors.py 會擋失效地標 -->
```

寫完把本 skill `scripts/lint_anchors.py` 複製到目標 repo 的 `scripts/`，跑：

```bash
python3 scripts/lint_anchors.py README.md
```

它抽出 README 裡 backtick 的路徑與 `ENV_NAME` 字面值，逐一驗證存在於 repo——
不存在＝地標失效＝文件過期，修到綠。**stale 地圖比沒地圖毒，freshness 靠機器擋不靠自律。**

**Retrofit 既有 README**：保留既有正確內容重組進範本節，不另開新檔；
與 code 對不上的內容當 stale 處理（改正或刪）。

## Step 3 —（僅 HTTP API）openapi.json

框架能離線匯出（判準與各框架指令見
[references/frameworks.md](references/frameworks.md)）→ 用本 skill
`scripts/gen_openapi.py --app <module:attr>` 產出，接著：

```bash
python3 scripts/openapi_completeness.py openapi.json --fail
```

紅的照 frameworks.md 的「缺口 → 回 code 修哪」表**回 code 補 summary/description/
錯誤碼/example 再重匯**——**絕不手改 openapi.json**。匯不出來（框架不支援、要加依賴）→
先問使用者；不匯就在 usage.md 手寫 endpoints 表（Step 4），README 契約節註明無 openapi。

選配：pre-commit 接 `gen_openapi` ＋ `lint_anchors`（openapi 跟著 code 自動更新、
地標失效擋 commit）。

## Step 4 —（僅對外元件）docs/usage.md

**單檔自足**：上傳平台後使用者只看得到這一份——禁止「見 repo 某檔」「參考 README」
式引用；需要的內容直接寫進來。用字白話、用使用者會搜尋的詞、不用內部代號。三條
容易漏的（實測 user 卡住的點）：
- **每種輸入形式都要有範例**：參數支援兩種指定方式（例：時間戳或 SCN）就給兩個
  可貼上的範例，不要只示範其中一種。
- **時間類參數寫明格式與時區**（例：ISO 8601、UTC）——user 第一個會問的就是這個。
- **專有狀態/術語首次出現用半句白話解釋**（例：「FLASHBACKED（回溯完成、唯讀待驗證）」）
  ——user 看不到 code，文件裡的每個名詞都要能在文件內自己讀懂。

範本：

```markdown
# <服務名> 使用說明

<白話 2–3 句：這能幫你做什麼、什麼情況用得到。>

## 快速開始
<最短可用路徑：base URL、一個完整可貼上執行的請求範例＋預期回應。>

## 認證
<怎麼拿到憑證、放哪個 header、沒帶會怎樣。>

## 功能一覽
| 動作 | 呼叫 | 說明 |
|------|------|------|
| 查詢回收筒 | `GET /query-recycle-bin` | 列出還救得回來的表 |

## 錯誤與重試
| 你會看到 | 意思 | 該怎麼辦 |
|----------|------|---------|

## 限制與注意
<rate limit、已知怪現象、不支援的情況；沒有就「無」。>
```

自足檢查（機器）：`grep -nE '(\.\./|見 |參考 |README|see )' docs/usage.md` ——
命中內部引用就把被引用的內容直接寫進來。

## Step 5 — 事實溯源自查＋回報

逐檔檢查：每個 env 名、數字、URL、行為描述都能指出出處（repo 檔案或使用者哪句話）；
查無的已改成「（待補：<問題>）」。**行為描述另抽 3 條**（優先抽：預設值、身分/權限、
HTTP 動詞這類容易寫反的），每條把出處程式碼**逐字引一行**貼進回報——引不出來的那條
就是你腦補的，回去修（實測最常見的錯：把 code 的 `'dev'` 寫成「空值」、把 GET 寫成 POST）。回報模板（照抄填空）：

三個機器檢查**在回報前重跑一次**，回報裡貼工具的**逐字輸出**（不是自己寫 pass——
聲稱與輸出不符＝假勾，驗收必退件）：

```
DOCS READY: <產出檔案清單>
ANCHOR LINT: <逐字貼：python3 scripts/lint_anchors.py README.md docs/usage.md 的輸出>
OPENAPI: <逐字貼 completeness 輸出末行 / 不適用＋原因>
USAGE 自足: <逐字貼 grep 指令與其輸出（無輸出寫「grep 無命中」）/ 不適用>
待補清單: <要問使用者的問題，逐條；沒有寫「無」>
略去的節: <哪些節不適用＋一句原因；沒有寫「無」>
```
