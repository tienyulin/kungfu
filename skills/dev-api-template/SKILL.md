---
name: dev-api-template
description: 組織 API template 的功能與架構參考 —— 一份可查的事實：template 提供哪些內建工具、目錄怎麼分層、命名／DI／設定／auth／devcontainer／lint-CI 長什麼樣。可純查詢「template 有什麼功能、架構長怎樣」，也可在開新服務或加端點時當「默認藍圖」照著走（偏離要寫一行理由，非硬性強制）。事實層 template-facts.md 可重生：裝進組織後照 rescan.md 重掃，改寫成公司內部規範版。Triggers - "api template 有哪些功能"、"template 架構長怎樣"、"這個 template 怎麼接 DB／寄信"、"照 template 開新服務"、"在 template 型服務加端點"、"develop on the api template"、"/dev-api-template"。
---

# dev-api-template

**這是 API template 的參考手冊，不是硬性流程。** 核心是可查的事實層
[references/template-facts.md](references/template-facts.md)：template 提供哪些能力、
架構怎麼分層、各慣例的字面值。你可以只拿它回答問題，也可以拿它當開發藍圖。

## 權威與自由度（先讀）

- **template-facts.md = template 的實際樣子**，是唯一的佈局／工具權威。本檔提到的任何
  路徑／指令／命名只是示意，**與 facts 不一致一律以 facts 為準**。
- facts 是**默認藍圖**：照著走最省事、跟團隊架構一致。**要偏離**（少一層、換結構、
  不用某內建工具）→ 可以，但在回報寫**一行理由**（例：「此端點純計算，不需 repository 層」）。
- 優先序：**使用者明確指示 > template 默認（facts）> 本檔示意值**。
- 遇到 facts 與本檔都沒定義、又無法自行合理默認的情況 → **停下問使用者**，不要發明。

## 兩種用法

**用法 1 — 查詢（不寫碼）。** 使用者問「template 有哪些內建工具／架構長怎樣／
這個能力怎麼接」→ 讀 facts，用節名或 file:line 回答，**不動碼**（Constitution Law 11：
問句的交付物是帶證據的答案）。答完停下。

**用法 2 — 開發（開新服務或加端點）。** 把 facts 當默認藍圖。開工前把下面的進度清單
照抄進回覆，每完成一步打勾再做下一步：

```
進度：
- [ ] 讀完 template-facts.md；判定模式 A（開新服務）或 B（加功能）
- [ ] （A）收參數齊 → clone／生成 → 改名清單全換 → 示範端點砍掉
- [ ] （B）由內往外：models → repository（mock 先）→ service → api → tests
- [ ] 外部能力查過內建工具表（沒有 → 掃 repo → 才新增）
- [ ] 驗證迴圈全綠（pytest／lint／openapi／mock 起服務／健康端點）——
      回報時【貼每條指令的實際輸出】；沒跑的寫「未跑」，不得宣稱通過
- [ ] README（wiki-doc-author 範本 1）+ .env.example
- [ ] 若有偏離 facts 默認架構 → 回報列出偏離處＋各一行理由
```

**不動與任務無關的共用檔**（requirements、lint 設定、CI、他人的模組）；非改不可
（例：依賴裝不起來）→ 先停下問使用者，說明原因再改。

## 判斷模式

- 使用者要**開新服務** → 模式 A（起手）再接模式 B
- 已在 template 型 repo 裡（目錄樹對得上 facts）要**加功能** → 直接模式 B

## 模式 A — 新服務起手

1. 收參數（缺一不開工，不要猜）：**服務名**（kebab-case）、**對接的外部系統**、
   **端點清單或 spec**（有 sop-to-spec 的 spec 最好；沒有就要「端點 + 一句話意圖 +
   風險」清單）、port（facts 有預設；衝突才問）。
   **不可逆判準**（無 spec 時用這條分流）：操作執行後**系統無法回復原狀、且後果
   具破壞性或組織要求審批**（刪除且無法還原、動金流、關機回收…）→ 不可逆 → **停**，
   建議先跑 sop-to-spec（confirm／審批閘門不該現場發明），或使用者明示免閘。
   效果離開系統但非破壞性（寄通知信之類）→ 不算不可逆，照常開發，副作用記進 README。
2. 照 facts〈取得方式〉拿 template：clone → 照**改名清單**把服務名／port／env 前綴全換
   （facts 列了哪些檔含這些字）→ 砍掉 template 的示範端點（facts 標了哪些是示範）。
3. 進模式 B 開發。

**spec 與 facts 的分工**：佈局／工具鏈／devcontainer／命名 → facts 贏；業務行為／schema／
錯誤表／審計／測試計畫 → spec 贏（照 spec 的 domain model、錯誤模型、審計、測試計畫
各節填，節名為準）；兩邊都管到且矛盾（port、env 名）→ 問使用者。

## 模式 B — 照架構開發

**加一個功能的落點順序（由內往外，template 的默認分層）**：

```
1. models 層     # schema + 常數（confirm token、固定文案集中在 facts 指定的檔）
2. repository 層 # 外部呼叫進 repository（mock 先寫、real 介面同 mock）
3. service 層    # 業務規則、前置條件判定
4. api 層        # router 端點：schema 驗證 + 呼叫 service + 組 response
5. tests         # 每端點 happy／edge／failure；測試隔離照 facts
```

## template 的架構默認（建議沿用；要偏離就寫一行理由）

這些是 template 的設計，沿用它就跟團隊一致、也最少驚喜。不是不可違逆的鐵律——
但偏離要是**有意識的決定**並在回報說明，不是隨手漏掉：

- 依賴方向單向：api → service → repository；repository 不 import service。
- repository 不擲業務錯誤：查無回 None／空值；404／409 判定在 service。
- mock 是一等公民：`MOCK_<系統>` 開著全部測試可跑、服務可起。
- DI 走 providers（模式照 facts），router 內不自行 new client。
- 設定只進 facts 指定的設定層；程式其他地方不讀 os.environ。

**內建工具優先**：要連 DB、寄信、呼叫內部服務…先查 facts〈內建工具〉——
template 已提供的就用現成的（照其用法接 DI），不自己 new 連線／找套件重造。
表裡沒有（或整張表空／標「待 rescan」）→ **以 repo 實際為準**：先掃 repo 現有的工具
模組（照 facts 目錄樹的 repository／工具位置 grep），找到就用並回報「facts 未登錄，
建議 rescan 補表」；repo 也真的沒有，才照 repository 層規則新增並回報使用者
（可能該進 template）。facts 與 repo 實際不一致時一律 **repo 為準** + 回報。

## 驗證迴圈（開發時：紅了就修，全綠才算完）

```bash
pytest -q                                  # 測試全綠
<facts 的 lint 指令>                        # lint／type／format 照 facts
<facts 的 openapi 匯出指令>                 # 匯出 openapi.json
<facts 的 mock 一行起服務指令>              # mock 起服務
curl localhost:<port>/<健康端點>            # 起得來、打得通
```
新服務另核對 devcontainer：service 名／port／postCreate 都改成新服務的。

## README + 接 wiki

README 必附（沒 README 的 API 等於不能用）：mock 模式一行起服務、端點白話表、
2–3 個 curl 實走情境、環境變數表、怎麼跑測試。寫法照 **wiki-doc-author** skill
（範本 1 / Mode A），這個 README 就是之後餵 wiki 的源頭文件，一份兩用。

## 完成定義（用法 2 開發時）

- [ ] 目錄樹與 template-facts.md 一致，或偏離處已列出＋各一行理由
- [ ] 外部能力全走內建工具或合規新增（無自造連線／重複輪子）
- [ ] `MOCK_<系統>` 下 pytest 全綠、服務一行起得來、健康端點 200
- [ ] lint／type／format 全綠；openapi.json 匯出且 completeness 過（有 gate 時）
- [ ] （新服務）改名清單全換、示範端點已砍、devcontainer 改到位
- [ ] README 合規（wiki-doc-author 範本 1）+ .env.example 齊
- [ ] 不可逆操作（若有）照 spec 的 confirm／approval 閘門，常數集中 facts 指定的檔

## 裝進你的組織：把 facts 換成公司內部版

本檔（方法論）通用、不隨組織改；[references/template-facts.md](references/template-facts.md)
是**可重生層**，記的是「某個具體 template 長怎樣」。v1 的 facts 由一個通用 proxy 萃取，
只是示範骨架。**拿進公司後**照 [references/rescan.md](references/rescan.md) 對真正的
組織 template repo 重掃、整檔重產 facts——公司自己的目錄分層、內建工具、命名／CI 規範
就會取代 proxy 值，本檔方法論不動。
