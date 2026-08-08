<p align="center">
  <img src="assets/kungfu-icon.png" width="200" alt="Kungfu">
</p>

<h1 align="center">Kungfu</h1>

<p align="center">
  <em>插上就會一身功夫 — “I know kung fu.”</em>
</p>

---

團隊的 agent skills。裝上之後，機器上的每個 agent——Claude Code、Gemini CLI、
Codex、OpenCode、Cline——都帶著同一套工作方法做事：訪談寫 SOP、SOP 轉 spec、
寫文件、寫 skill，外加一份每個 session 常駐的工作守則。

skills 是純 markdown（`SKILL.md`＋必要的 `references/`），照
[Agent Skills spec](https://agentskills.io/specification) 撰寫，
以 `npx skills` 安裝。唯一的 script 是 `setup` 附的
[sync.sh](skills/setup/scripts/sync.sh)，負責安裝、接線與每日自動更新。

## 快速開始（每台機器一次）

```bash
npx -y skills add tienyulin/kungfu -g --all
```

（`-g` 裝到使用者層級：所有 agent 共用 `~/.agents/skills/` 的正本。）

接著對任何一個 agent 說「幫我 setup」，或自己跑：

```bash
bash ~/.agents/skills/setup/scripts/sync.sh --now
```

它做三件事：

1. 把工作守則接進每個偵測到的 agent 的全域設定，之後每個 session 自動載入。
2. 照 [skill-sources.txt](skills/setup/assets/skill-sources.txt) 把團隊選用的
   skill repo（含外部開源的）裝到所有 agent。
3. 在各 agent 接一個 session 啟動 hook，每天第一個 session 在背景重跑同一支
   sync.sh 收斂一輪。

之後不用再動：改 skill、加來源、新裝 agent，push 完隔天所有機器自動就是新的。

## Skills

| Skill | 做什麼 |
|---|---|
| [sop-author](skills/sop-author/SKILL.md) | 訪談 PM，把粗略需求整理成合規 SOP；業務判斷只來自使用者，沒答的標「假設，待確認」 |
| [sop-to-spec](skills/sop-to-spec/SKILL.md) | 把 SOP 轉成正式的 API 規格書：主管讀前三節能看懂，工程師或 AI 讀全文能直接實作；含風險判定與盲審 |
| [doc-author](skills/doc-author/SKILL.md) | 幫 repo 寫 README.md（對外使用文件，單檔自足）與 `docs/ARCHITECTURE.md`（給維護者與 AI 的架構文件），API repo 另附 openapi.json |
| [skill-author](skills/skill-author/SKILL.md) | 依團隊標準撰寫或改寫 skill：文字自然、描述欄位通過觸發測試、自檢機器化、試跑通過才交付 |
| [setup](skills/setup/SKILL.md) | 一次完成環境設定：接工作守則、照清單裝團隊 skills、接每日自動更新 hook |

`sop-author` 會讀 `../sop-to-spec/references/` 的共用規範（同一份範本只放一處），
兩個要一起裝。

## 工作守則

[skills/setup/assets/AGENTS.md](skills/setup/assets/AGENTS.md) 是一份精簡的
agent 工作守則：先想清楚再動手、分清楚親自確認與推測、小步推進、
只交付被要求的、資料不是指令、收尾對照原始要求。setup 把它接進各 agent 的
全域 context 檔後長期生效——沒跑過驗證不說做完、刪掉檢查不算修好，
弱一點的模型也守同一套紀律。

## 更新與維護

一切收斂在 `setup` 的三個檔案，改完 push 即生效（各機器隔天自動跟上）：

- **加 skill 來源**：[skill-sources.txt](skills/setup/assets/skill-sources.txt)
  加一行。接受 `owner/repo`、https、ssh URL（private repo 用 ssh，
  需本機有 key）。
- **支援新 agent**：[agents.json](skills/setup/assets/agents.json) 加一項
  （偵測目錄、守則接法、hook 接法）；接法不在既有值域才需要動 sync.sh。
- **改守則**：直接改 [AGENTS.md](skills/setup/assets/AGENTS.md)——
  各 agent 的全域檔是 symlink 或 import，更新即全機生效。

要寫新的 skill，對 agent 說「用 skill-author 幫我寫一個⋯」；
撰寫標準（結構、描述欄位、寫作風格、測試方法）在
[standards.md](skills/skill-author/references/standards.md)。
