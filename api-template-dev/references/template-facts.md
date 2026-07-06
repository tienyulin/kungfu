# Template Facts（可重生層）

> **來源**：v1 由 proxy 參考實作（llm-wiki-mcp 平台的 `flashback-api/`）萃取。
> **裝進組織後**：照 [rescan.md](rescan.md) 對真正的組織 template repo 重掃、
> **整檔重產**（保持本檔的節結構）。SKILL.md 的方法論不用動。

## Contents
- 取得方式（clone + 改名清單 + 示範端點）
- 內建工具
- 目錄樹與各層職責
- 命名慣例
- DI 模式（core/deps.py）
- 設定模式（core/config.py）
- auth 模式（api/dependencies.py）
- openapi responses（api/openapi_responses.py）
- scripts 來源
- main.py 模式
- devcontainer
- Dockerfile / docker-compose
- lint / test / CI
- 預設值

## 取得方式（clone + 改名清單 + 示範端點）

組織做法 = **clone template repo 直接開發**（架構與工具已就位）：

- clone 指令：`git clone <組織 template repo URL> <service-name>`
  （**URL 待 rescan 填**；v1 拿不到組織 template 時的 fallback：照本檔目錄樹逐檔生成）
- **改名清單**（clone 後把 template 佔位名全換成新服務名；rescan 時逐檔確認）：
  `devcontainer.json` 的 name/service、`docker-compose.yml` 的 service/container_name/port、
  `Dockerfile` 的 EXPOSE、`.env.example` 與 `core/config.py` 的 env 前綴、
  `main.py` 的 FastAPI title、`README.md` 的 frontmatter `source_app` 與 H1、
  `pyproject.toml` 內含專案名的欄位
- **示範端點**：template 內附的 example router/service/repository/tests
  （rescan 時標明哪些檔）→ 起手時砍掉，只留架構與工具

## 內建工具

template 已內建、**開發時一律用現成**的能力（SKILL.md「內建工具優先」查這張表）。

> v1 proxy 無內建工具庫 —— **本節主要由 rescan 對組織 template 登錄**。每個工具一列：

| 工具 | 位置（模組/類） | 用途 | 怎麼接（DI provider / 直接 import） | mock 方式 |
|---|---|---|---|---|
| （rescan 填：DB 連線 client） | | | | |
| （rescan 填：寄信 mailer） | | | | |
| （rescan 填：其他…） | | | | |

登錄準則：位置與接法寫**字面值**（import 路徑、provider 名）；每個工具的 mock
開關/替身怎麼給要寫，否則「mock 是一等公民」斷在這。

## 目錄樹與各層職責

```
<service-name>/
├── main.py                    # ASGI 入口：create_app() + lifespan warm-up + 統一 error handler
├── api/
│   ├── __init__.py            # api_router = APIRouter()（無 prefix，健康端點在 root）；include 各 router
│   ├── dependencies.py        # auth，行為見下方〈auth 模式〉
│   ├── openapi_responses.py   # 共用 4xx/5xx response 宣告，骨架見下方〈openapi responses〉
│   └── routers/<domain>.py    # 端點：只做 schema 驗證 + 呼叫 service + 組 response
├── services/<domain>_service.py  # 業務規則、前置條件判定、擲業務例外（自訂 Error 類）
├── repository/
│   ├── <系統>_client.py       # real 客戶端；介面 = mock；缺連線設定 boot fail-hard
│   └── mock_<系統>.py         # 記憶體 mock：初始狀態 + 每方法模擬效果，測試可直接改內部 dict
├── models/schemas.py          # 全部 pydantic models + 常數（confirm token、audit 固定文案）
├── core/
│   ├── config.py              # frozen dataclass Settings + lru_cache get_settings()
│   └── deps.py                # DI providers + reset_singletons()
├── tests/
│   ├── conftest.py            # autouse fixture 呼叫 reset_singletons()
│   └── test_api.py            # TestClient；每端點 happy/edge/failure
├── scripts/                   # 文件工具四檔，來源見下方〈scripts 來源〉
├── .devcontainer/             # devcontainer.json + docker-compose.dev.yml
├── Dockerfile / docker-compose.yml / .env.example
├── requirements.txt           # 依賴唯一出處（pyproject 只管工具設定，不管依賴）
├── pyproject.toml / pytest.ini / .flake8 / .pre-commit-config.yaml
├── .github/workflows/ci.yml   # （組織若是 GitLab，rescan 後此節換 .gitlab-ci.yml）
└── README.md / openapi.json   # wiki-doc-author 範本 1（Mode A）
```

## 命名慣例

- 服務名 kebab-case；py 檔 snake_case；router 檔 = domain 名（`flashback.py`）
- service 類 `<Domain>Service`、業務例外 `<Domain>Error`
- mock env：`MOCK_<系統大寫蛇形>`（例 `MOCK_ORACLE`）；auth env：`<SERVICE大寫蛇形>_API_KEY`
- 外部系統連線 env：`<系統>_DSN` / `<系統>_USER` / `<系統>_PASSWORD`

## DI 模式（core/deps.py，照抄結構）

```python
@lru_cache(maxsize=1)
def get_<系統>() -> <系統>Repository:
    settings = get_settings()
    if settings.mock_<系統>:
        from repository.mock_<系統> import Mock<系統>Repository  # lazy：mock 跑不裝 driver
        return Mock<系統>Repository()
    if not settings.<系統>_dsn:
        raise RuntimeError("<系統>_DSN is required when MOCK_<系統> is not enabled")
    return Real<系統>Repository(...)

@lru_cache(maxsize=1)
def get_service() -> <Domain>Service: ...

def reset_singletons() -> None:   # 測試 seam
    for fn in (get_service, get_<系統>): fn.cache_clear()
    get_settings.cache_clear()
```

## 設定模式（core/config.py）

frozen dataclass `Settings` + `@lru_cache get_settings()`；env 只在這裡讀。
例外：API key 在 `api/dependencies.py` **每 request 讀**（測試可動態開關 auth）。

## auth 模式（api/dependencies.py）

- header `X-API-Key` ↔ env `<SERVICE大寫蛇形>_API_KEY`，`secrets.compare_digest` 比對
- **env 未設 = dev 模式：放行不驗**（main.py boot 時印警告）；有設 → mutation 端點
  必驗，read 端點不驗
- 驗證失敗（缺 header 或 key 錯）→ **401**，body 走統一錯誤 envelope
  `{"detail": str, "error_code": null}`

## openapi responses（api/openapi_responses.py）

一個模組級 dict 常數，router 的 `responses=` 引用，餵 openapi 完整度 gate：

```python
ERROR_RESPONSES: dict = {
    401: {"description": "缺少或錯誤的 API key", "model": ErrorResponse},
    404: {"description": "資源不存在", "model": ErrorResponse},
    409: {"description": "前置條件不允許", "model": ErrorResponse},
    422: {"description": "輸入驗證失敗"},
}
# router: @router.post(..., responses={**ERROR_RESPONSES, 428: {...}})  # 端點加自己的
```
（`ErrorResponse` = models 層的 `{"detail", "error_code"}` schema。）

## scripts 來源

`scripts/` 四檔 = **wiki-doc-author skill** 的 `scripts/`（gen_openapi.py、
openapi_completeness.py、lint_frontmatter.py、frontmatter.schema.json）。同一個
marketplace bundle，正常都裝了 —— 從其安裝目錄複製。找不到該 skill → 跳過
openapi 匯出/完整度 gate，README 改手寫 Endpoints 區（wiki-doc-author 的 Mode B），
並告知使用者裝 bundle 後補接。

## main.py 模式

`create_app()` 工廠 + `lifespan`：boot 時呼叫一次 `get_service()`（設定錯 = 起不來，
不是第一個 request 才炸）；API key 未設印 dev-mode 警告。統一 exception handler 把
業務例外轉 `{"detail", "error_code"}`。檔尾 `if __name__ == "__main__":
uvicorn.run(...)`（Dockerfile 的 `CMD ["python", "main.py"]` 靠它）。

## devcontainer

`.devcontainer/devcontainer.json`：
```json
{
  "name": "<service-name>",
  "dockerComposeFile": ["../docker-compose.yml", "docker-compose.dev.yml"],
  "service": "<service-name>",
  "workspaceFolder": "/app",
  "mounts": ["source=${localWorkspaceFolder},target=/app,type=bind,consistency=cached"],
  "shutdownAction": "stopCompose",
  "forwardPorts": [<port>],
  "postCreateCommand": "apt-get update && apt-get install -y --no-install-recommends git && pip install -r requirements.txt && pre-commit install --hook-type pre-commit --hook-type pre-push",
  "remoteEnv": { "MOCK_<系統>": "true" },
  "customizations": { "vscode": {
    "extensions": ["ms-python.python", "ms-python.vscode-pylance"],
    "settings": { "python.defaultInterpreterPath": "/usr/local/bin/python",
                  "python.testing.pytestEnabled": true, "python.testing.pytestArgs": ["."] } } }
}
```
`docker-compose.dev.yml`：override 該 service 為 `command: sleep infinity` +
`MOCK_<系統>: ${MOCK_<系統>:-true}`（容器活著給 VS Code attach，源碼 bind mount）。

## Dockerfile / docker-compose

- Dockerfile：`python:3.14-slim` → COPY requirements → pip install（含
  `PIP_TRUSTED_HOST` 供內網）→ COPY . → `ENV PYTHONPATH=/app` → EXPOSE <port> →
  `CMD ["python", "main.py"]`
- docker-compose.yml：單 service、`MOCK_<系統>: ${MOCK_<系統>:-true}` 預設 mock、
  全部 env 走 `${VAR:-default}`。頂部註解寫三行快速啟動。

## lint / test / CI

- black line-length 100、target py314；flake8 max 100 + `extend-ignore = E203,W503`；
  mypy `ignore_missing_imports = true`（driver 無 stubs）；pylint py-version 3.14、
  optional driver 進 `ignored-modules`
- pytest.ini：`testpaths = tests`
- pre-commit（local repo hooks，工具吃本地安裝、離線可跑）：black → flake8 → mypy →
  pylint → gen-openapi（`env PYTHONPATH=. python scripts/gen_openapi.py --app main:app`）
- CI：`MOCK_<系統>=true` 下跑 black --check / flake8 / mypy /
  `pylint $(find . -name "*.py")`（**任何訊息即紅**）/ pytest。proxy 用 GitHub Actions；
  組織平台照 rescan 結果換。
- 一鍵驗證順序 = SKILL.md Step 4。

## 預設值

| 參數 | 預設 |
|---|---|
| port | 8000（proxy 用 8003；組織慣例 rescan 後定） |
| python | 3.14-slim |
| 健康端點 | `GET /health`（回 `{"status":"ok","mock":<bool>}`） |
| mock 一行起服務 | `MOCK_<系統>=true python main.py`（容器版 `docker compose up -d`） |
| requirements 基線 | `fastapi`、`uvicorn[standard]`、`pydantic` + lint/測試工具鏈，**不 pin 版本**；外部系統 driver 用官方套件（選型記進 README 環境變數表旁） |
