# Personal Systems Development

这是一个通过真实使用逐步生长的个人系统开发项目。目标不是一次性设计完整的“个人成长系统”，而是从已经发生的痛点出发，每次交付一个可使用、可验证的最小闭环，并让使用结果决定下一轮方向。

## 当前状态

- 阶段：`v0.1` 已完成第一次端到端试用，正在根据真实反馈调整材料与反思体验。
- 已有输入：个人系统的 Motivation、已确认痛点、需求与待定架构问题。
- 当前目标：把已同步的记录整理成反思，并形成下一次行动变化。
- 当前待验证：清爽材料格式能否在后续增量整理中保持稳定，以及反思能否形成可采用的下一次行动。
- `v0.1` 已提供扫描脚本和两阶段 Prompt，完成一次材料归类与阶段性反思，但尚未通过完整用户验收，也不是发布版本。

需求事实以本地的 `docs/personal-pain-points-and-needs.md` 为准。该文档当前仍处于持续收集阶段，不应被 README、Roadmap 或观察记录重复改写成另一套需求。

## 产品目标

建立一个持续运行的反馈闭环：

```text
计划 -> 实践 -> 记录与反思 -> 沉淀经验
     -> 在下一次计划与实践中复用 -> 用新结果修正经验
```

系统是否有效，最终看它有没有改变后续判断、行动和结果，而不是累计了多少记录、文档或功能。

## 当前边界

- 从真实痛点和具体使用情境出发，不预先设计完整的大系统。
- 一轮只推进一个主要问题，交付能够进入真实使用的最小闭环。
- 区分战略规划与项目战术计划，候选想法不自动成为当前承诺。
- 区分原始记录、待验证观察和可复用经验，不把所有内容都沉淀为资产。
- 经验复用必须能够观察到行为或结果变化，不能只以“已检索”或“已注入上下文”作为成功证据。
- 当前仅服务个人本地使用；不提前建设多用户、正式部署、企业审批或复杂安全治理。

## 本地项目资料

以下内容用于本地规划和 AI 协作，不纳入远端 Git 仓库：

| 位置 | 作用 |
| --- | --- |
| `docs/personal-pain-points-and-needs.md` | 当前需求、Motivation、已确认痛点和架构待定问题的唯一汇总 |
| `docs/ROADMAP.md` | 版本顺序、每个版本的目标与覆盖需求 |
| `docs/observations/OBSERVATIONS.md` | 持续追加的真实使用观察、影响与处理状态 |
| `AGENTS.md` | AI 在本项目中的工作规则、上下文入口和验证要求 |

[CHANGELOG.md](CHANGELOG.md) 记录已接受版本之间对使用者有意义的变化，随产品代码一起纳入 Git。

## v0.1 本地试运行

前提：使用 PowerShell 7（`pwsh`），并确保同步后的随手记位于 `C:/codex working space/随手记/daily/`；也可以通过 `-DailyDir` 指定其他位置。

1. 扫描 2026-06-19 以来尚未由 v0.1 处理的内容：

   ```powershell
   pwsh -NoProfile -File scripts/scan-reflection-notes.ps1 -Mode Scan -FromDate 2026-06-19 > reflection/runtime/scan-result.json
   ```

   `Scan` 只读取原始笔记并生成 `reflection/runtime/scan-checkpoint.json`，不会推进正式状态。

2. 将扫描结果和已有项目上下文交给 [记录拆分与项目归类 Prompt](prompts/v0.1-classify-records.md)，集中确认归属不清的片段。

3. 将确认后的分类结果交给 [项目 MDAO 材料组织 Prompt](prompts/v0.1-organize-project-materials.md)，把每个项目写成 `reflection/projects/<project-id>.md`。

4. 重新读取并确认全部材料已经落盘后，提交本次扫描 checkpoint：

   ```powershell
   pwsh -NoProfile -File scripts/scan-reflection-notes.ps1 -Mode Commit
   ```

5. 用户选择一个项目后，呈现对应的项目材料文档，再按本地 `docs/reflection/project-reflection-method-v1.md` 开展反思。

扫描状态、checkpoint、分类中间结果和项目材料都位于本地 `reflection/`，不会进入 Git。

运行自动检查：

```powershell
pwsh -NoProfile -File tests/test-scan-reflection-notes.ps1
pwsh -NoProfile -File tests/test-prompt-contracts.ps1
```

## 迭代方式

1. 从需求文档和真实观察中选定一个主要问题。
2. 明确期望结果、范围、非范围和通过条件。
3. 完成最小端到端实现与必要验证。
4. 进入真实使用，并记录新的观察。
5. 接受版本后更新 Change Log；根据证据调整 Roadmap。

代码出现后，再按实际技术栈补充运行命令、`src/`、`tests/` 和必要的运行日志约定。
