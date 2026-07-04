---
name: api-template-dev
description: 照公司定義好的 API template 開發三層式 FastAPI 服務 —— 新服務從 clone template 起手（架構、devcontainer、lint/CI、內建工具都已就位），開發中照三層架構加端點、用 template 內建工具（DB 連線、寄信等）而不是重造。開發者要開新服務或在 template 型服務上加功能時用。Triggers - "照 template 開新服務"、"用 api template 開發"、"加一個端點"、"develop on the api template"、"new service from template"、"/api-template-dev"。
---

# api-template-dev

照公司 API template 開發。**兩層知識分離**：

- 本檔 = 方法論（起手流程、三層鐵律、內建工具優先、驗證迴圈）—— 穩定，不隨模板改。
- [references/template-facts.md](references/template-facts.md) = 模板的**具體事實**
  （怎麼 clone、目錄樹、內建工具清單、devcontainer、lint/CI、命名）—— **可重生層**。
  模板演進時照 [references/rescan.md](references/rescan.md) 重掃重產 facts，本檔不動。

先讀完 template-facts.md 再開工 —— 它是唯一的佈局與工具權威。**本檔提到的任何路徑/
指令/命名若與 facts 不一致，一律以 facts 為準**（本檔的字面值只是示意）。

## 判斷模式

- 使用者要**開新服務** → 模式 A（起手）再接模式 B
- 已在 template 型 repo 裡（目錄樹對得上 facts）要**加功能** → 直接模式 B

## 模式 A — 新服務起手

1. 收參數（缺一不開工，不要猜）：**服務名**（kebab-case）、**對接的外部系統**、
   **端點清單或 spec**（有 sop-to-spec 的 spec 最好；沒有就要「端點 + 一句話意圖 +
   風險」清單）、port（facts 有預設；衝突才問）。
   **不可逆判準**（無 spec 時用這條分流）：操作執行後**系統無法回復原狀、且後果
   具破壞性或組織要求審批**（刪除且無法還原、動金流、關機回收…）→ 不可逆 → **停**，
   建議先跑 sop-to-spec（confirm/審批閘門不該現場發明），或使用者明示免閘。
   效果離開系統但非破壞性（寄通知信之類）→ 不算不可逆，照常開發，副作用記進 README。
2. 照 facts〈取得方式〉拿 template：clone → 照**改名清單**把服務名/port/env 前綴全換
   （facts 列了哪些檔含這些字）→ 砍掉 template 的示範端點（facts 標了哪些是示範）。
3. 進模式 B 開發。

**spec 與 facts 的分工**：佈局/工具鏈/devcontainer/命名 → facts 贏；業務行為/schema/
錯誤表/審計/測試計畫 → spec 贏（照 spec 的 domain model、錯誤模型、審計、測試計畫
各節填，節名為準）；兩邊都管到且矛盾（port、env 名）→ 問使用者。

## 模式 B — 照架構開發

**加一個功能的落點順序（由內往外）**：

```
1. models 層     # schema + 常數（confirm token、固定文案集中在 facts 指定的檔）
2. repository 層 # 外部呼叫進 repository（mock 先寫、real 介面同 mock）
3. service 層    # 業務規則、前置條件判定
4. api 層        # router 端點：schema 驗證 + 呼叫 service + 組 response
5. tests         # 每端點 happy/edge/failure；測試隔離照 facts
```

**三層鐵律**：
- 依賴方向單向：api → service → repository；repository 不 import service。
- repository 永不擲業務錯誤：查無回 None/空值；404/409 判定在 service。
- mock 是一等公民：`MOCK_<系統>` 開著全部測試可跑、服務可起。
- DI 一律走 providers（模式照 facts），router 內不得自行 new client。
- 設定只進 facts 指定的設定層；程式其他地方不讀 os.environ。

**內建工具優先**：要連 DB、寄信、呼叫內部服務…先查 facts〈內建工具〉——
template 已提供的一律用現成的（照其用法接 DI），**不得自己 new 連線/自己找套件重造**。
表裡沒有（或整張表空/標「待 rescan」）→ **以 repo 實際為準**：先掃 repo 現有的工具
模組（照 facts 目錄樹的 repository/工具位置 grep），找到就用並回報「facts 未登錄，
建議 rescan 補表」；repo 也真的沒有，才照 repository 層規則新增並回報使用者
（可能該進 template）。facts 與 repo 實際不一致時一律 **repo 為準** + 回報。

## 驗證迴圈（紅了就修，全綠才算完）

```bash
pytest -q                                  # 測試全綠
<facts 的 lint 指令>                        # lint/type/format 照 facts
<facts 的 openapi 匯出指令>                 # 匯出 openapi.json
<facts 的 mock 一行起服務指令>              # mock 起服務
curl localhost:<port>/<健康端點>            # 起得來、打得通
```
新服務另核對 devcontainer：service 名/port/postCreate 都改成新服務的。

## README + 接 wiki

README 必附（沒 README 的 API 等於不能用）：mock 模式一行起服務、端點白話表、
2–3 個 curl 實走情境、環境變數表、怎麼跑測試。寫法照 **wiki-doc-author** skill
（範本 1 / Mode A），這個 README 就是之後餵 wiki 的源頭文件，一份兩用。

## 完成定義

- [ ] 目錄樹與 template-facts.md 一致；三層鐵律逐條符合
- [ ] 外部能力全走內建工具或合規新增（無自造連線/重複輪子）
- [ ] `MOCK_<系統>` 下 pytest 全綠、服務一行起得來、健康端點 200
- [ ] lint/type/format 全綠；openapi.json 匯出且 completeness 過（有 gate 時）
- [ ] （新服務）改名清單全換、示範端點已砍、devcontainer 改到位
- [ ] README 合規（wiki-doc-author 範本 1）+ .env.example 齊
- [ ] 不可逆操作（若有）照 spec 的 confirm/approval 閘門，常數集中 facts 指定的檔
