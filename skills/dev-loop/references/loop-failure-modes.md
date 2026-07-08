# Loop 四大失敗模式 — 每輪自檢表

每輪迭代掃一眼。氣味要可機械自檢；中了照「處置」欄做，不要憑感覺硬繞。

| 失敗模式 | 氣味（怎麼發現自己中了） | 處置 |
|---|---|---|
| **Thrashing**（打轉不收斂） | 同一個 gate 連紅、每輪 diff 越改越小；或這輪改的跟第 1 輪某次一樣 | 三振規則提前執行：停、revert 到最後綠狀態、LOOP ESCALATED。禁止「再試一次說不定就好」 |
| **Overfitting to tests**（測試過了、需求沒達） | DONE MEANS 只剩測試項在打勾、「非測試觀察」那項一直沒驗；或你改了測試讓它過（Constitution Law 7 直接禁止） | 先跑「非測試觀察」項（實際啟動/呼叫看行為）；動過測試檔 → revert，回頭修程式碼 |
| **Context drift**（拿舊假設做新輪） | 這輪引用的錯誤訊息不是**這輪** gate 貼出來的；或引用的檔案內容是你改過之前的版本 | 重跑 gate、重讀檔案，用新輸出重寫假設（Constitution Law 4／ANTIPATTERNS #13） |
| **Unsafe autonomy**（圈裡做出危險動作） | 想跑的指令在 SAFETY §1 清單上；guard hook 回 ask/deny | 不繞過 guard、不換寫法躲 pattern。把該步驟寫進 LOOP ESCALATED 讓使用者決定 |

通則：出圈永遠合法（升級是成果），硬繞永遠不合法。
