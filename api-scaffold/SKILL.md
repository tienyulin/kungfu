---
name: api-scaffold
description: 照公司 API template 開一個新的三層式 FastAPI 服務（api / service / repository + mock、devcontainer、lint/CI、測試）。從零 scaffold 到「mock 模式一行起服務、測試全綠」為止。開發者要開新服務/新 API 專案時用。Triggers - "開一個新的 API 服務"、"照模板開專案"、"scaffold a new api"、"new service from template"、"/api-scaffold <service-name>"。
---

# api-scaffold

照公司 API template 從零蓋一個三層式 FastAPI 服務。**兩層知識分離**：

- 本檔 = 方法論（怎麼 scaffold、三層鐵律、驗證迴圈）—— 穩定，不隨模板改。
- [references/template-facts.md](references/template-facts.md) = 模板的**具體事實**
  （目錄樹、devcontainer、lint/CI、命名慣例）—— **可重生層**。模板 repo 演進時照
  [references/rescan.md](references/rescan.md) 重掃重產 facts，本檔不用動。

先讀完 template-facts.md 再開工 —— 它是唯一的佈局權威。**本檔提到的任何路徑/指令/
命名若與 facts 不一致，一律以 facts 為準**（本檔的字面值只是示意）。

## Step 1 — 收參數

問使用者（缺一不開工，不要猜）：
1. **服務名**（kebab-case，例 `order-sync-api`）
2. **對接的外部系統**（Oracle/Redis/內部 API…）→ 決定 repository 介面與 mock env 名
   `MOCK_<系統大寫蛇形>`
3. **端點清單或 spec**：有 sop-to-spec 產的 spec 最好；沒有就要使用者給「端點 +
   一句話意圖 + 風險（查詢/可逆/不可逆）」清單。**無 spec 而清單含不可逆操作 → 停**：
   建議先跑 sop-to-spec（不可逆的 confirm/審批閘門不該由 scaffold 現場發明），或
   使用者明示免閘再繼續
4. port（facts 有預設值；衝突才問）

**spec 與 facts 的分工**：佈局/工具鏈/devcontainer/命名 → facts 贏；業務行為/schema/
錯誤表/審計/測試計畫 → spec 贏（照 spec 的 domain model、錯誤模型、審計、測試計畫
各節填，節名為準）；兩邊都管到且矛盾（port、env 名）→ 問使用者。

## Step 2 — Scaffold（依序生成，順序即依賴方向）

照 template-facts.md 的目錄樹逐檔生成（檔案路徑/骨架一律以 facts 為準），
**由內往外**的層次順序：

```
1. models 層     # schema + 常數（confirm token、固定文案集中在 facts 指定的檔）
2. 設定層        # env 讀取（含 mock 開關）
3. mock repository   # 先寫 mock：完整可測的記憶體實作
4. real repository   # 介面同 mock；缺連線設定 boot fail-hard
5. DI providers      # 照 facts 的 DI 模式 + 測試 seam
6. service 層        # 業務規則、前置條件判定
7. api 層 + 入口     # routers、auth dependency、app 工廠 + lifespan warm-up
8. tests             # 測試隔離照 facts；每端點 happy/edge/failure
9. 容器 + CI         # devcontainer / Dockerfile / compose / lint 設定（照 facts 骨架抄改）
10. .env.example + README（見 Step 5）
```

## Step 3 — 三層鐵律（生成時逐條遵守）

- **依賴方向單向**：api → service → repository。repository 不 import service，
  service 不 import api。models/core 誰都能 import。
- **repository 永不擲業務錯誤**：查無回 None/空值；404/409 判定在 service。
- **mock 是一等公民**：`MOCK_<系統>=true` 下全部測試可跑、服務可起，不需要任何外部系統。
  mock 初始狀態要足以跑完全部測試。
- **DI 一律走 providers**（模式照 facts），router 內不得自行 new client；
  測試用 facts 提供的測試 seam 隔離。
- **設定只進 core/config.py**：程式其他地方不讀 os.environ。

## Step 4 — 驗證迴圈（紅了就修，全綠才算完）

```bash
pytest -q                                  # 測試全綠
<facts 的 lint 指令>                        # lint/type/format 照 facts
<facts 的 openapi 匯出指令>                 # 匯出 openapi.json
<facts 的 mock 一行起服務指令>              # mock 起服務
curl localhost:<port>/<健康端點>            # 起得來、打得通
```
devcontainer 驗證：`devcontainer.json` 指的 compose service 名 = 新服務名、
postCreateCommand 裝得起來（至少人工核對一遍路徑與名稱都改到）。

## Step 5 — README + 接 wiki

README 必附（沒 README 的 API 等於不能用）：mock 模式一行起服務、端點白話表、
2–3 個 curl 實走情境、環境變數表、怎麼跑測試。寫法照 **wiki-doc-author** skill
（範本 1 / Mode A：frontmatter + 第一段摘要 + committed openapi.json），這個 README
就是之後餵 wiki 的源頭文件，一份兩用。

## 完成定義

- [ ] 目錄樹與 template-facts.md 一致；三層鐵律逐條符合
- [ ] `MOCK_<系統>=true` 下 pytest 全綠、服務一行起得來、健康端點 200
- [ ] lint/type/format 全綠（facts 的指令）
- [ ] openapi.json 已匯出且 completeness 過（有 gate 工具時）
- [ ] devcontainer 的 service 名/port/postCreate 都改成新服務的
- [ ] README 合規（wiki-doc-author 範本 1）+ .env.example 齊
- [ ] 不可逆操作（若有）照 spec 的 confirm/approval 閘門，常數集中 models/schemas.py
