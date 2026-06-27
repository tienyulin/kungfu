# llm-wiki-skills

LLM Wiki 平台共用的 **Claude Code skills**，獨立成 repo 讓任何專案/agent 取用。

| skill | 做什麼 |
|---|---|
| [`wiki-doc-author`](wiki-doc-author/SKILL.md) | 產出餵進 wiki processor 的源頭文件 —— API（README + openapi.json）、cronjob/worker/CLI、純知識，都一份 README 搞定。一個檔讀完就能做，附純 stdlib 工具（`scripts/`）。 |
| [`sop-to-spec`](sop-to-spec/SKILL.md) | 把維運 SOP（DBA runbook、infra 程序…）轉成「人能審、AI 能照著實作三層 FastAPI 服務」的 spec。 |

## 怎麼用

### 方式 A — git submodule（平台與各專案目前用）

把整個 repo 掛在專案的 `.claude/skills/`，Claude Code 自動載入裡面的 skill：

```bash
git submodule add https://github.com/tienyulin/llm-wiki-skills .claude/skills
git commit -m "chore: vendor llm-wiki-skills as .claude/skills submodule"
```

更新到最新：
```bash
git submodule update --remote .claude/skills && git commit -am "chore: bump skills"
```

### 方式 B — 直接複製

把需要的 skill 資料夾（含 `scripts/`）複製進專案 `.claude/skills/<name>/`。

## 設計原則

- **自包含**：每個 skill 一份 `SKILL.md` 讀完即可執行，不互相指來指去；工具放 `scripts/`（純 stdlib、無相依）。
- **通用**：不綁特定框架/語言/領域；新舊專案皆可。

> Claude Code plugin（`/plugin install`）打包待後續：plugin 需要 `skills/` 子目錄結構，與此處
> 「root = skill 資料夾、供 submodule 掛 `.claude/skills`」的 layout 不同，之後另開分支處理。
