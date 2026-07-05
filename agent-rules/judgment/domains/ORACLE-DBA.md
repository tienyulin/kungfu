# ORACLE-DBA — Oracle 資料庫管理規則系統

> 讀者：任何模型（規則以 7B 等級為下限設計——弱模型照字面執行，強模型當檢查清單）。
> 適用：Oracle 資料庫的維運、診斷、調校、備份還原、資料操作、HA 操作。
> 每條規則三段：觸發（可觀察）→ 動作（可執行）→ 自檢（yes/no）。
> 優先序：使用者最新明確訊息 > 專案 CLAUDE.md > 本檔 > 你的直覺。本檔沒寫到的情況，用 KERNEL.md。
> 規則依防災重要性排序，衝突時取編號小的。
> 本領域特殊性：**錯一條指令可能毀掉的是資料本身**——資料不像程式碼，沒有 git 可以救。寧可慢。

## R1 — 先確認你連到哪裡，再打第一條指令

- **觸發**：建立任何資料庫連線之後、執行任何指令之前。
- **動作**：1. 跑 `SELECT instance_name, host_name, version FROM v$instance;` 和 `SELECT name, database_role, open_mode FROM v$database;`，輸出逐字記下。2. 對照任務目標：這是使用者要我操作的那顆嗎？名字對不上 → 停，回報。3. `database_role` 是 PRIMARY 且名字像正式環境（prod/prd/正式命名慣例）→ 本檔所有規則升到最嚴（等同 KERNEL J3 不可逆＋影響他人格）。
- **自檢**：我有本回合的 instance 查詢輸出，且確認過它是目標庫嗎？
- **例**：tnsnames 裡 `ORCL` 指向誰沒人記得 → 錯：「應該是測試庫」直接跑 UPDATE。→ 對：查出 `host_name = prod-db01` → 停，跟使用者確認。

## R2 — 破壞性 SQL 過三道閘

- **觸發**：要執行 UPDATE、DELETE、TRUNCATE、DROP、或任何 DDL。
- **動作**：
  1. **閘一（範圍）**：先跑 `SELECT COUNT(*)` 用**一字不改的同一個 WHERE 子句**。筆數和預期對不上 → 停。UPDATE/DELETE 沒有 WHERE → 停，亮出完整語句問使用者。
  2. **閘二（退路）**：R3 的退路建好了才准執行。TRUNCATE/DROP 不進 undo——flashback query 救不回來，只有 recyclebin（DROP TABLE）或還原點救得了。
  3. **閘三（提交）**：執行後先驗證結果（抽 3 筆看內容），對了才 COMMIT。錯了 ROLLBACK。TRUNCATE/DDL 隱含 commit、無法 rollback → 執行前視同不可逆操作，先亮語句等同意。
- **自檢**：COUNT 用的 WHERE 和實際執行的 WHERE 是同一段文字嗎？COMMIT 前抽查過了嗎？
- **例**：清測試資料 → 錯：`DELETE FROM orders WHERE created < '2025-01-01'`（隱式日期轉換，NLS 設定不同刪錯範圍）。→ 對：先 `SELECT COUNT(*)` 同 WHERE、用 `TO_DATE(...,'YYYY-MM-DD')` 明確格式、確認筆數、執行、抽查、才 COMMIT。

## R3 — 改動前先有經過驗證的退路

- **觸發**：任何會改變資料或結構的操作之前。
- **動作**：1. 小範圍資料改動 → 先 `CREATE TABLE backup_<表名>_<日期> AS SELECT ...` 備份受影響列。2. 結構改動 / 大範圍改動 → 建 restore point（先查 FRA 空間夠不夠：`V$RECOVERY_FILE_DEST`；guaranteed restore point 會吃 FRA，用完要刪）。3. 依賴既有備份當退路 → 先驗證它：`RMAN VALIDATE` 或查最近一次成功還原演練的紀錄。**沒還原過的備份只是一個檔案，不是備份。**4. 寫下一行「退路 = 跑 ___」。
- **自檢**：退路那一行寫了，而且它的可用性是本回合驗證過的嗎？
- **例**：改欄位型別前 → 錯：「昨晚有 RMAN 排程，沒問題。」（排程三週前就開始失敗，沒人看）。→ 對：`LIST BACKUP SUMMARY` 確認昨晚那份存在＋`VALIDATE` 通過，才動手。

## R4 — 版本與授權先查，語法後寫

- **觸發**：要使用本回合沒驗證過的語法、view、feature、或 package。
- **動作**：1. 先查版本：`SELECT banner FROM v$version;`。2. 該 feature 查**對應版本**的官方文件確認存在（12c/19c/23ai 差異大，記憶不可信）。3. 要查 AWR、ASH、`DBA_HIST_*`、SQL Tuning Advisor → 先確認有 Diagnostics/Tuning Pack 授權（問使用者或查 `DBA_FEATURE_USAGE_STATISTICS`）；沒授權就查了 = 讓使用者違約，改用 Statspack / `V$SESSION` 即時視圖。
- **自檢**：這次用的每個 view 和語法，都確認過在**這個版本、這個授權**下合法嗎？
- **例**：錯：在 19c SE2 上直接查 `DBA_HIST_ACTIVE_SESS_HISTORY`（SE2 根本沒有 Diagnostics Pack 可買）。→ 對：改用 `V$SESSION` + Statspack。

## R5 — 診斷從 alert log 和等待事件開始，不從猜測開始

- **觸發**：收到「資料庫慢 / 掛了 / 報錯」類任務。
- **動作**：1. 先看 alert log 最後 200 行（位置：`SELECT value FROM v$diag_info WHERE name='Diag Trace';`），ORA 錯誤**逐字**記下。2. 查現在在等什麼：`SELECT event, COUNT(*) FROM v$session WHERE wait_class <> 'Idle' GROUP BY event ORDER BY 2 DESC;`。3. 拿到具體證據（錯誤碼 / top 等待事件 / 具體 SQL_ID）之後，才准形成假設。4. 「慢」要先量化：慢的是哪個操作、多久、以前多久——沒有這三個數字不准開始調校。
- **自檢**：我的假設指得出它來自哪一行 alert log 或哪個等待事件嗎？
- **例**：「資料庫好慢」→ 錯：直接調大 SGA（猜的）。→ 對：等待事件顯示 `enq: TX - row lock contention` → 是鎖不是記憶體，查 blocking session。

## R6 — 一次一參數，量測前後，範圍寫明

- **觸發**：要改任何初始化參數或做調校改動。
- **動作**：1. 記下舊值（`SELECT name, value, isdefault FROM v$parameter WHERE name='...';`）。2. 一次只改一個參數。3. 寫明範圍再執行：`ALTER SYSTEM ... SCOPE=MEMORY|SPFILE|BOTH`——SCOPE 沒想清楚的改動，重啟後行為會跟你以為的不同。4. 改動前後量同一個指標，數字進回報。5. 沒效 → 改回舊值再試下一個（KERNEL J5）。
- **自檢**：舊值記了？只改了一個？前後數字都有？
- **例**：錯：一口氣改 `sga_target`、`pga_aggregate_target`、`db_file_multiblock_read_count`，變快了但不知道是哪個（另兩個從此成為沒人敢動的迷信）。→ 對：一個一個來。

## R7 — 索引與統計資訊不是免費的

- **觸發**：想加索引、或想跑 `DBMS_STATS.GATHER_*` 來「修慢查詢」。
- **動作**：1. 加索引前：拿實際執行計畫證明它會被用（`DBMS_XPLAN.DISPLAY_CURSOR` 帶真實統計，不是 `EXPLAIN PLAN` 的猜測）；並寫一行代價聲明：這張表的每次 DML 從此多維護一個索引。2. 正式環境重收統計 = 可能翻轉**其他** SQL 的執行計畫——收之前確認有退路（`DBMS_STATS.EXPORT_*` 舊統計，或 SQL plan baseline 鎖住關鍵 SQL）。3. 只對出問題的物件收，不跑全庫。
- **自檢**：索引有執行計畫證據？收統計前舊統計可還原？
- **例**：錯：半夜全庫 gather stats，早上三支報表全變慢（計畫翻了）。→ 對：只收那張表，先 export 舊統計，翻車可以 import 回來。

## R8 — 殺 session 和重啟是最後手段，且會銷毀證據

- **觸發**：想 `ALTER SYSTEM KILL SESSION`、重啟 instance、或重啟 listener。
- **動作**：1. 先抓證據存檔：該 session 的 SQL_ID、等待事件、undo 用量（`v$transaction` 的 `used_ublk`）——重啟後 `V$` 視圖全部歸零，現場就沒了。2. 殺長交易前先算回滾代價：undo 量大 → 回滾可能比讓它跑完更久，殺了更慘。3. 重啟正式環境 instance = 不可逆＋影響他人 → 亮出理由和指令，等使用者同意。4. 重啟後必驗：instance OPEN、alert log 無新錯、應用連得上。
- **自檢**：殺/重啟之前，現場證據存了嗎？回滾代價算了嗎？
- **例**：批次卡 6 小時 → 錯：直接 kill（undo 800 萬 block，回滾滾了 14 小時）。→ 對：查 `used_ublk` 發現回滾更貴 → 回報使用者選：等它跑完 or 接受回滾時間。

## R9 — 空間問題不准用刪檔解

- **觸發**：FRA 滿、archivelog 塞爆、tablespace 滿、磁碟滿。
- **動作**：1. **禁止** OS 層 `rm` 刪 archivelog / 資料檔——RMAN 不知情，備份鏈斷裂。要刪走 RMAN：`DELETE ARCHIVELOG ALL COMPLETED BEFORE 'SYSDATE-n'`（先確認已備份：`BACKED UP 1 TIMES`）。2. **禁止**用關 archivelog mode 解空間問題——那是拿掉整個時間點還原能力，只有使用者能決定。3. tablespace 滿 → 加 datafile 前查磁碟真實剩餘空間、確認加對 tablespace。4. 治本：查空間為什麼滿（備份沒在刪過期？某表暴長？），只治標會三天後再滿一次。
- **自檢**：我的解法動到的每個檔案，RMAN 都知情嗎？根因查了嗎？
- **例**：ORA-00257 archiver stuck → 錯：`rm /arch/*.arc`（下次還原直接失敗）。→ 對：RMAN 確認已備份 → RMAN DELETE → 查出根因是備份 job 兩週前壞了。

## R10 — 大量資料操作要分批，並算 undo 帳

- **觸發**：預估影響超過 10 萬列的 UPDATE / DELETE / INSERT，或要在上班時間跑。
- **動作**：1. 分批執行（每批 1 萬～10 萬列，批間 COMMIT），禁止單一交易吃完全表——undo 爆掉（ORA-01555 / ORA-30036）會連累別人。2. 先估 undo 與 temp 用量，對照現有容量。3. 大量 DELETE 後空間不會自己回來，要跟使用者確認是否需要 shrink / move。4. 上班時間跑會鎖表、搶 IO → 先問使用者要不要排離峰。5. 寫可重跑（re-runnable）的批次：中斷後能從斷點續跑，不是從頭來。
- **自檢**：分批了？undo 估了？中斷可續跑？
- **例**：刪 5000 萬列歷史資料 → 錯：一條 DELETE，跑 3 小時後 undo 爆，回滾又 3 小時，白天 IO 被吃光。→ 對：離峰、每批 5 萬列、記錄進度表、可續跑。

## R11 — 權限給最小的那一個，不給 DBA

- **觸發**：遇到 ORA-01031（insufficient privileges）或任何權限報錯，或被要求開權限。
- **動作**：1. 查出**缺的那一個**具體權限（看報錯的操作對照文件，或查 `DBA_SYS_PRIVS`/`DBA_TAB_PRIVS` 現況）。2. 只授那一個：`GRANT SELECT ON schema.table TO user;`。3. 「GRANT DBA 最快」= 禁手——那是把整顆庫的鑰匙給出去解一個檔案櫃的鎖。4. 任何 GRANT 記錄進回報（給了誰、什麼、為什麼）。
- **自檢**：授出去的權限是「缺的那一個」還是「一定夠大的那一包」？
- **例**：AP 帳號報 ORA-01031 → 錯：`GRANT DBA TO app_user`。→ 對：查出只缺 `CREATE SEQUENCE`，授這一個。

## R12 — Switchover 不是 Failover；HA 指令先確認腳站在哪

- **觸發**：要操作 Data Guard、RAC、或任何切換 / 容錯移轉。
- **動作**：1. 先跑 R1 確認目前連的是哪個節點、哪個角色（primary / standby）。2. 分清楚：**switchover** = 計畫性、無資料遺失、可切回；**failover** = 災難用、可能掉資料、舊 primary 通常要重建。使用者說「切換」→ 先確認他要哪一種，附一句差異說明。3. Failover 或任何「可能掉資料」的 HA 操作 → 亮出指令＋預估資料遺失窗口，等明確同意。4. 切換前檢查同步狀態：`SELECT * FROM v$archive_dest_status;` / lag 多少，逐字記下。
- **自檢**：我確認過自己在哪個節點、什麼角色、使用者要的是哪一種切換嗎？
- **例**：「切到備庫」→ 錯：直接 failover（其實只是要做主機維護，結果舊主庫要重建，掉了 40 秒交易）。→ 對：確認是計畫性維護 → switchover，先檢查 lag = 0。

---

## 回合終檢（結束前逐題答，任一 no → 先修再結束）

1. 每條指令執行前都知道自己連在哪一顆庫、什麼角色？
2. 破壞性 SQL 都過了三道閘（同 WHERE 的 COUNT／退路／抽查後才 COMMIT）？
3. 退路寫了，且可用性本回合驗證過？
4. ORA 錯誤都逐字引用，沒有憑記憶改寫？
5. 每個改動都記了舊值＋前後量測？
6. 沒有用 rm 刪過任何資料庫管的檔案、沒有授出超過需要的權限？

## 禁語表

| 禁語 | 替代寫法 |
|---|---|
| 「應該是連到測試環境」 | 跑 `v$instance`/`v$database`，貼輸出 |
| 「先重啟看看」 | 先抓證據（等待事件、alert log），重啟是最後手段且需同意 |
| 「加個索引就會快」 | 拿 `DBMS_XPLAN.DISPLAY_CURSOR` 的真實計畫證明，附 DML 維護代價 |
| 「archivelog 刪掉就有空間了」 | RMAN 確認已備份後走 RMAN DELETE，並查根因 |
| 「直接給 DBA 權限最快」 | 查出缺的那一個權限，只授它 |
| 「有備份排程，沒問題」 | `LIST BACKUP SUMMARY` + VALIDATE，沒還原過的備份不是備份 |
| 「這語法我記得是這樣」 | 查 `v$version` 對應版本的文件，貼出處 |
