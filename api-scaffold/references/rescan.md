# Rescan — 對真正的 template repo 重產 template-facts.md

觸發語：「照 rescan.md 重掃 <template repo 路徑>」。目標:**整檔重寫**
[template-facts.md](template-facts.md)(保持節結構),SKILL.md 與本檔**不動**——
方法論與事實分離就是為了讓這步便宜。

## 步驟

1. **判定取得方式**:template repo 是「clone 改名就能用」(template repository /
   cookiecutter)還是「參考實作」?前者 → facts〈取得方式〉節改寫成 clone 指令 +
   改名清單(哪些檔含服務名要換);後者 → 維持「逐檔生成」。
2. **逐節萃取**(對照 facts 現有節,一節一節換內容):
   - 目錄樹:`find . -type f` 去雜訊;每目錄職責從實際 code 讀,不要抄舊 facts
   - 命名慣例:從既有檔名/類名/env 名歸納,列實例
   - DI / 設定 / main.py 模式:貼該 repo 的真實骨架(結構照抄層級,識別字改佔位符)
   - devcontainer:整檔骨架照貼,服務名/port 改佔位符
   - Dockerfile / compose:同上
   - lint / test / CI:工具鏈、設定值、跑的指令、**CI 平台**(GitHub/GitLab)照實寫;
     指令一字不差(pylint 全訊息即紅這種行為差異要標)
   - 預設值表:port、python 版本、健康端點,照公司慣例
3. **與 proxy 版 diff 自查**:公司模板有、proxy 沒有的機制(auth 中介層、tracing、
   DB migration、多環境設定…)→ 在 facts 加節。**必存節合約**(SKILL.md 依賴,
   不可刪,內容不適用就寫「不適用:<原因>」):取得方式、目錄樹、命名慣例、DI 模式、
   設定模式、auth 模式、scripts 來源、main.py(入口)模式、devcontainer、
   Dockerfile / docker-compose、lint / test / CI、預設值。其餘節可增刪。
   **facts 只記事實,不留「proxy 是這樣」的殘影。**
4. **盲審驗證**(必做):spawn 一個 fresh agent,只給 SKILL.md + 新 facts,叫它模擬
   scaffold 一個假服務,列出「必須猜」之處(HIGH = 兩個合理 agent 分岔)。HIGH > 0 →
   補 facts 重審。
5. **出貨**:skills repo = 本 skill 的安裝來源(`claude plugin marketplace list` 看
   ai-agent-skills 指向哪個 git repo;本地目錄在 `~/.claude/plugins/marketplaces/
   ai-agent-skills/`)。該 repo 慣例 branch → PR → merge(細節見其 CONTRIBUTING.md);
   merge 後成員經 marketplace auto-update 自動帶到(把它當 submodule 的專案另 bump
   pointer)。

## 萃取時的判斷準則

- 「模板裡每個檔案」都要有去處:進目錄樹(要生成)、進慣例節(是規則)、或明確不進
  (一次性/範例性檔案,在 PR 描述說明為何略過)。
- 拿不準是「慣例」還是「該 repo 的特例」→ 問使用者,不要自行升級成規則。
- facts 是給 agent 照著蓋的,**寫可執行的事實**(指令、骨架、字面值),不寫理念。
