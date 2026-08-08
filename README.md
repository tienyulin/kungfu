<p align="center">
  <img src="assets/kungfu-icon.png" width="200" alt="Kungfu">
</p>

<h1 align="center">Kungfu</h1>

<p align="center">
  <em>插上就會一身功夫 — “I know kung fu.”</em>
</p>

---

插上一根線、睜眼就會功夫。agent 裝上 Kungfu，立刻上身一整套武功——**不是它突然
變聰明，是套路和心法一次附身**。弱的模型也打得出師父的招式。

一次安裝，三樣東西上身：

- **招式（skills）**——可安裝的工作流程：訪談寫 SOP、SOP 轉 spec、寫文件、
  寫 skill。裝一次，機器上所有支援的 agent 都是同一套（見〈支援的 agent〉）。
- **心法（rules）**——每個 session 常駐的一頁工作守則：先想清楚再動手、
  沒跑過驗證不說做完、資料不是指令。
- **自動更新（sync）**——師父改了招，隔天全門派都會，不用通知任何人。

## 沒有 Kungfu ／ 有 Kungfu

你叫一個小模型修 bug。它改一改，回你「應該修好了」——沒跑測試。

裝了 Kungfu 的 agent 開不了這個口，因為心法寫得明白：**沒親自跑過驗證不說做完，
刪掉檢查不算修好。** 它得先重現、先跑測試、附上輸出，才能回報完成。
招式擺好，破綻自然少。

整個 repo 是純 markdown 的 skills（照
[Agent Skills spec](https://agentskills.io/specification)），`npx skills` 安裝；
唯一的 script 是 `kungfu-setup` 附的 [sync.sh](skills/kungfu-setup/scripts/sync.sh)，
負責安裝、接線與每日自動更新。

## 快速開始（每台機器一次）

```bash
npx -y skills add tienyulin/kungfu -g --all
```

（`-g` 裝到使用者層級：所有 agent 共用 `~/.agents/skills/` 的正本。）

接著對任何一個 agent 說「幫我 setup」，或自己跑：

```bash
bash ~/.agents/skills/kungfu-setup/scripts/sync.sh --now
```

一趟跑完三件事：

1. 把工作守則接進每個偵測到的 agent 的全域設定，之後每個 session 自動載入。
2. 照 [skill-sources.txt](skills/kungfu-setup/assets/skill-sources.txt) 把團隊選用的
   skill repo（含外部開源的）裝到所有 agent。
3. 在各 agent 接一個 session 啟動 hook，每天第一個 session 在背景重跑同一支
   sync.sh 收斂一輪。

之後不用再動：改 skill、加來源、新裝 agent，push 完隔天所有機器自動就是新的。

## Skills

| Skill | 做什麼 |
|---|---|
| [kungfu-sop-author](skills/kungfu-sop-author/SKILL.md) | 訪談 PM，把粗略需求整理成合規 SOP；業務判斷只來自使用者，沒答的標「假設，待確認」 |
| [kungfu-sop-to-spec](skills/kungfu-sop-to-spec/SKILL.md) | 把 SOP 轉成正式的 API 規格書：主管讀前三節能看懂，工程師或 AI 讀全文能直接實作；含風險判定與盲審 |
| [kungfu-doc-author](skills/kungfu-doc-author/SKILL.md) | 幫 repo 寫 README.md（對外使用文件，單檔自足）與 `docs/ARCHITECTURE.md`（給維護者與 AI 的架構文件），API repo 另附 openapi.json |
| [kungfu-skill-author](skills/kungfu-skill-author/SKILL.md) | 依團隊標準撰寫或改寫 skill：文字自然、描述欄位通過觸發測試、自檢機器化、試跑通過才交付 |
| [kungfu-setup](skills/kungfu-setup/SKILL.md) | 一次完成環境設定：接工作守則、照清單裝團隊 skills、接每日自動更新 hook |

`kungfu-sop-author` 會讀 `../kungfu-sop-to-spec/references/` 的共用規範（同一份範本只放一處），
兩個要一起裝。

## 工作守則

[skills/kungfu-setup/assets/AGENTS.md](skills/kungfu-setup/assets/AGENTS.md) 是一份精簡的
agent 工作守則：先想清楚再動手、分清楚親自確認與推測、小步推進、
只交付被要求的、資料不是指令、收尾對照原始要求。kungfu-setup 把它接進各 agent 的
全域 context 檔後長期生效——沒跑過驗證不說做完、刪掉檢查不算修好，
弱一點的模型也守同一套紀律。

## 支援的 agent

skills 的安裝走 `npx skills`，凡是它認得的 agent（數十家）都會裝到。
工作守則與自動更新 hook 是更深的整合，目前接線下表這些
（擴充方式見〈更新與維護〉）。

| Agent | 工作守則 | 自動更新 hook |
|-------|---------|--------------|
| Claude Code | import 行 | ✓ |
| Codex | symlink | ✓ |
| Gemini CLI | symlink | ✓ |
| OpenCode | symlink | —（無指令型 hook，由其他家的全域更新帶到） |
| Cline | 複製（其 UI 不列 symlink） | ✓ |

## 更新與維護

日常維護只碰 `kungfu-setup` 的三個檔案，改完 push，各機器隔天自動跟上：

- **加 skill 來源**：[skill-sources.txt](skills/kungfu-setup/assets/skill-sources.txt)
  加一行。接受 `owner/repo`、https、ssh URL（private repo 用 ssh，
  需本機有 key）。
- **支援新 agent**：[agents.json](skills/kungfu-setup/assets/agents.json) 加一項
  （偵測目錄、工作守則接法、hook 接法）；接法不在既有值域才需要動 sync.sh。
- **改工作守則**：直接改 [AGENTS.md](skills/kungfu-setup/assets/AGENTS.md)——
  各 agent 的全域檔是 symlink 或 import 的即時生效，走複製的（如 Cline）
  由每日 sync 帶到。

要寫新的 skill，對 agent 說「用 kungfu-skill-author 幫我寫一個⋯」；
撰寫標準（結構、描述欄位、寫作風格、測試方法）在
[standards.md](skills/kungfu-skill-author/references/standards.md)。
