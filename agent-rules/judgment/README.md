# judgment/ — 通用判斷力制度

> **這份是線上使用版**（vendored 進 agent-rules plugin，隨 marketplace autoUpdate 發佈）。
> 觸發方式：INDEX.md 隨 Constitution 的 SessionStart hook 自動常駐注入（含各檔絕對路徑），
> 其餘 31 檔由 agent 照 INDEX 路由表按需 Read——不用安裝、不用手動載入。
> 修訂走本 repo 的 PR＋CI；原始快照在 github.com/tienyulin/judgment。由來與時間見根目錄 ORIGIN.md。

首次整理並整併於 2026-07-05。目的：讓之後在此環境長期運作的模型
（不論等級：Sonnet / Opus / Haiku / minimax / qwen / 7B 開源），在做**任何事情**時
借用一套已固化的判斷程序。本系統不限寫程式 — 它管的是「怎麼判斷」，不是「怎麼寫 code」。

設計原則：規則以**能力下限**設計 — 每條有可觀察觸發、數字化門檻（3 次、2 倍、5 分鐘）、
可照抄模板。弱模型照字面執行就能及格；強模型把它當防呆檢查清單，成本趨近於零。

## 結構（三層＋思考框架，30 個規則檔＋本 README）

```
KERNEL.md      ← 常駐層：12 條法則 + 回合終檢 + 路由表（唯一必讀）
THINKING.md    ← 生成層：思考迴圈（怎麼想出答案）；>30 分鐘或高風險問題先讀
signals/ × 11  ← 訊號層：過程中出現特定訊號才載入
domains/ × 17  ← 任務層：按任務類型載入；每檔自包含，可單獨使用
```

KERNEL 與 THINKING 的分工：KERNEL 是**約束**（防止做錯），THINKING 是**生成**（產出答案的六步迴圈：FRAME 定框 → SPREAD 展開 → PROBE 試探 → COMMIT 收斂 → ATTACK 自攻 → DELIVER 交付，附換檔動作與心智常數）。

| 檔案 | 內容 | 載入時機 |
|---|---|---|
| **KERNEL.md** | 12 法則、終檢、路由表 | **每 session 開頭** |
| THINKING.md | 思考迴圈六步＋橫向動作＋心智常數 | 問題 >30 分鐘或高風險時 |
| signals/ASK-OR-ACT.md | 問/做/停查表、大任務偵測、預設值程序 | 猶豫要不要問時 |
| signals/STUCK.md | 迴圈訊號、三振模板、換高度清單 | 同一問題失敗 2 次時 |
| signals/CHOICES.md | 選擇程序、tie-breaker、決策記錄 | 方案間選擇時 |
| signals/TRADEOFFS.md | 深度權衡 10 步：利害表、全成本、敏感度 | 單向門/大金額/影響他人時 |
| signals/LIMITS.md | 超載訊號、降載程序、升級階梯 | 任務可能超出能力時 |
| signals/LONGRUN.md | WORKING.md 協議、漂移檢查、恢復規則 | 任務 > 30 分鐘或跨 session |
| signals/VERIFY.md | 8 種成品類型驗證配方 | 宣稱「完成」之前 |
| signals/FAILMODES.md | 10 種 LLM 故障模式：症狀→自測→解法 | 回合結束前掃一次 |
| signals/AMPLIFY.md | 5 個放大器：多發＋驗證買回能力差距 | 高風險產出時 |
| signals/RETRO.md | 失敗變規則：三行紀錄、四路分流、提案制 | 被糾正/失敗/規則沒防住時 |
| signals/EXAMPLES.md | 14 個好壞對照案例 | 不確定規則怎麼套用時 |
| domains/CODING.md | 寫程式 12 條 | 任務 = 寫/改碼 |
| domains/DEBUG.md | 除錯 11 條 | 任務 = 修東西 |
| domains/DEPLOY.md | 部署 12 條（最嚴） | 任務 = 碰 prod |
| domains/ORACLE-DBA.md | Oracle DBA 12 條（嚴度同 DEPLOY） | 任務 = 碰 Oracle DB |
| domains/ARCHITECT.md | 架構設計 12 條（數字先於設計） | 任務 = 系統設計/選型 |
| domains/DIAGRAMS.md | 技術圖 11 條（選型/拆圖/render 驗證） | 任務 = 畫圖 |
| domains/PLANNING.md | 規劃 12 條＋完成陷阱附錄 | 任務 = 先計畫 |
| domains/RESEARCH.md | 研究 12 條 | 任務 = 查資料 |
| domains/WRITING.md | 寫作 12 條＋輸出規格附錄 | 任務 = 寫東西 |
| domains/DISTILL.md | 長文提煉 11 條（結論先行、埋雷掃描） | 任務 = 摘要/重點整理 |
| domains/REVERSE-ENG.md | 逆向工程 11 條（行為優先、假設實驗迴圈） | 任務 = 搞懂無文件系統 |
| domains/CASCADE.md | 失敗連鎖 10 條（污染清點、三階推演） | 任務 = 故障影響/風險推演 |
| domains/EDGE-CASES.md | 五步方法＋五張生成器表 | 任務 = 找 edge case |
| domains/JUDGE.md | 評判 12 條（rubric 先行、拆偏誤） | 任務 = 評判任何東西 |
| domains/INCIDENT.md | 火場 8 條（止血>根因、溝通節奏） | 事故**進行中** |
| domains/DATA.md | 資料判讀 10 條（每條問「誰選的」） | 任務 = 解讀數據 |
| domains/SECURITY.md | 日常資安 8 條（接觸那一刻前置） | 碰到密鑰/PII/漏洞 |

domains/ 每檔固定格式：觸發（可觀察）→ 動作（可執行）→ 自檢（yes/no）＋每條一個
真實場景例＋回合終檢＋禁語表。**自包含** — 單獨貼進任何 agent 的 system prompt 都能用。

## 按模型強度的載入策略

規則總量越多，遵守率越低 — 所以不要一次全塞，按承載力給：

| 模型等級 | 策略 |
|---|---|
| 強（Opus 級以上） | 常駐 KERNEL 就夠。其餘檔案當需要時的參考書 |
| 中（Sonnet / Haiku 級） | 常駐 KERNEL ＋ 照路由表按需載入一至兩檔 |
| 小（7B / 專用 agent） | **不載 KERNEL**，直接把對應的一個 domains/ 檔當 system prompt 用 |

通用原則：**任何時刻 context 裡最多 KERNEL ＋ 2 檔**。要載第三檔，先卸一檔。

## 與 agent-rules 並用（INDEX.md）

環境裡已有 agent-rules Constitution 常駐時，**不要**再常駐 KERNEL（兩部 Constitution 重疊會互相稀釋）。
改用 [INDEX.md](INDEX.md)：它只含 Constitution 沒覆蓋的 7 條增量法則＋完整路由表，
由 agent-rules 的注入管線一起送進 session（`@JUDGMENT@` placeholder 由注入器換成本 repo 路徑）。
KERNEL 與全部檔案原樣保留——單獨使用、或當 train 其他 skill 的素材時，照下方安裝法。
INDEX 的路由表新增檔案時要同步更新。

## 安裝（三選一——只在「不裝 agent-rules plugin、單獨使用本制度」時需要）

（下方 `<judgment 目錄>` = 你放 judgment 的位置：kungfu 裡 vendored 的 `agent-rules/judgment/`，
或你自己 clone 的 judgment repo；填成該機器上的實際絕對路徑。）

1. **CLAUDE.md 指令**（最簡單）：加一行
   `每個 session 開始時，先讀 <judgment 目錄>/KERNEL.md 並遵守其中規則與路由表。`
2. **SessionStart hook**（最可靠）：settings.json 的 hooks 加
   ```json
   {
     "hooks": {
       "SessionStart": [
         { "hooks": [ { "type": "command",
             "command": "cat <judgment 目錄>/KERNEL.md" } ] }
       ]
     }
   }
   ```
3. **其他 agent（Codex／Gemini／OpenCode／Cline）**：各自的 session-start hook 讀 KERNEL.md
   （機制同 2，各家格式不同）；沒有 hook 機制時才手動把 KERNEL.md 或單一 domains/ 檔貼進 system prompt。

## 與 agent-rules/ 的關係

agent-rules 的 Constitution 管**寫程式的執行紀律**；本系統管**通用判斷**。兩者相容；
重疊處（三振、逐字引用、完成定義）規則一致，衝突時以使用者最新訊息為準。

## 修訂標準（給未來想改規則的 session）

新規則必須同時過 4 關，缺一不收：

1. **可觀察的觸發** — 不需要自由裁量就知道何時適用。
2. **可執行的動作** — 寫成「做 X」，不是「注意 X」。
3. **可判定的自檢** — 一個 yes/no 問題能檢查有沒有做到。
4. **一個真實失敗案例** — 沒有失敗故事的規則是想像出來的。

**刪除比新增優先**。KERNEL 永不超過 12 條；新法則要進，先淘汰一條舊的。
domains/ 每檔上限 12 條。抽象語（「保持謹慎」「合理判斷」「視情況」）出現 = 該規則不合格。
一條規則 30 天內從未被觸發 → 考慮移除或合併。
