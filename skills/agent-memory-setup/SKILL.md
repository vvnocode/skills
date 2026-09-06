---
name: agent-memory-setup
description: Use when a repo is worked on by more than one coding agent (Claude Code, Codex, dsh, opencode …) and their instructions or memory sit in separate places — AGENTS.md is present but Claude ignores it, agent memory lands in the home directory, switching tools loses accumulated context, or a new machine needs the same setup reproduced in one step.
---

# 多 Agent 共用项目指令与仓内记忆

## 核心

一份指令、一份仓库内记忆，每个工具都指向它。做法是四件事：`AGENTS.md` 当正本、`CLAUDE.md` 做软链；记忆放仓内 `.memory/` 随代码提交；能改记忆目录的工具用配置指过来，不能改的把自带记忆关掉；再把记忆读写规则写进 `AGENTS.md`。**各工具强度不对等**：Claude 可以用配置硬指定记忆目录；Codex 的记忆目录写死在 `$CODEX_HOME/memories`，只能关掉再靠指令约束；dsh 与 opencode 没有自带的跨会话记忆，全靠指令。

## 机制对照

| | Claude Code | Codex | dsh | opencode |
|---|---|---|---|---|
| 读项目指令 | 只读 `CLAUDE.md`（**不读 `AGENTS.md`**） | 只读 `AGENTS.md` | `AGENTS.md`（也认 `CLAUDE.md`） | `AGENTS.md`（也认 `CLAUDE.md`） |
| 自带跨会话记忆 | 有；目录可改：`autoMemoryDirectory` | 有；目录**不可改**，固定 `$CODEX_HOME/memories` | 无 | 无 |
| 记忆读写规则来源 | 自身系统提示 + `AGENTS.md` | 仅 `AGENTS.md` | 仅 `AGENTS.md` | 仅 `AGENTS.md` |
| 项目级配置 | `.claude/settings.local.json` | `.codex/config.toml`（**需项目被信任**） | 无 | `opencode.json`（本 skill 不需要） |
| 全局 Skill 发现根 | `~/.claude/skills/` | `~/.codex/skills/` | `~/.agents/skills/` | `~/.config/opencode/skills/`、`~/.claude/skills/`、`~/.agents/skills/` |

「记忆读写规则来源」一行是关键：只有 Claude 自带「先读索引、按 frontmatter 写」的系统提示，其他三个工具只有 `AGENTS.md` 里写了才会做。步骤 4 因此不能省。

## 一键执行

```bash
./setup.sh [仓库路径] [--no-rule]
```

在目标仓库根目录运行（或传路径）。幂等，只补缺不覆盖；不能自动裁定的冲突只告警。跑完按输出做两件人工事：往 `~/.codex/config.toml` 追加信任片段（用 Codex 才需要），然后按「验证」节逐工具确认。Windows 无法运行本脚本，按下面手工步骤做，软链换 junction 或副本。

## 手工步骤（脚本做的事）

**1. 指令合一。** 保留 `AGENTS.md` 为唯一正本，补 Claude 入口：

```bash
ln -s AGENTS.md CLAUDE.md
```

相对软链可直接入库，`git worktree add` 出来的 worktree 里照样可见。也可以在 `CLAUDE.md` 里写一行 `@AGENTS.md`，二选一。

**2. Claude 记忆改到仓内。** 建 `.memory/MEMORY.md`，写 `.claude/settings.local.json`（**不要写入库的 `settings.json`**，官方文档标明该项在项目级 settings 里会因安全被忽略）：

```json
{ "autoMemoryDirectory": "<仓库绝对路径>/.memory" }
```

把 `.claude/settings.local.json` 加进 `.gitignore`。

**3. 关掉 Codex 自带记忆。** `.codex/config.toml`：

```toml
[memories]
generate_memories = false   # 本目录会话不再沉淀到仓库外
use_memories     = false    # 不再注入仓库外的旧副本
dedicated_tools  = false    # 收掉 list/read/search/add_ad_hoc_note
```

然后在 `~/.codex/config.toml` 标记信任，否则整个 `.codex/` 静默不加载：

```toml
[projects."<仓库绝对路径>"]
trust_level = "trusted"
```

**4. 在 `AGENTS.md` 写死记忆规则。** 记忆一律存 `.memory/`，随代码提交；会话开始先读 `MEMORY.md` 索引；每条记忆单独一个 `.md`，frontmatter 含 `name` / `description` / `metadata.type`（`user` | `feedback` | `project` | `reference`）；写入前先查已有条目。`setup.sh` 追加的原文见脚本第 6 步。

## worktree 里的会话

`git worktree add` 只检出入库文件。`.claude/settings.local.json` 被 gitignore，在 worktree 里不存在，Claude 的记忆目录会退回工具默认位置，仓内记忆整份不可见。处理：在 worktree 里把根工作区那份软链过来，或装一个 post-checkout 钩子自动做。

```bash
ln -s <根工作区>/.claude/settings.local.json <worktree>/.claude/settings.local.json
```

## 验证

- Claude：在仓库目录开会话，问「不用工具，复述项目指令里关于记忆写入位置的那条」；答不出就是 `CLAUDE.md` 没加载。
- Codex：`./codex-effective-config.py <仓库绝对路径>`。它走 app-server 的 `config/read` 按 cwd 解析项目层，并抓 stderr 里的未信任警告。**不要用 `codex doctor`**，它只报全局值。
- dsh / opencode：开会话问同一问题，它们读 `AGENTS.md`。
- 记忆可见性：在 `MEMORY.md` 放一条带口令的索引行，问各工具读到几条。

## 陷阱

| 陷阱 | 后果 | 应对 |
|---|---|---|
| 没有 `CLAUDE.md` | Claude 完全不读项目规则，**无任何提示** | 必须有软链或 `@AGENTS.md` |
| Codex 项目未被信任 | `.codex/` 的 config、hooks、exec policies **整体**不加载（skills 仍加载），**静默失效**，只在 app-server 的 stderr 报一行 | `~/.codex/config.toml` 加 trusted；仓库改路径要重做 |
| 拿 `codex doctor` 当证据 | 只报全局配置，得出反向结论 | 用 `codex-effective-config.py` |
| 只关 `generate_memories` | `add_ad_hoc_note` 仍往仓库外写 | 三项一起关 |
| **Codex 后台记忆管线只读全局配置** | 项目级 `generate_memories = false` **挡不住**它按会话更新时间重新提取、重建 `~/.codex/memories` | 要彻底停只能改全局，代价是所有项目一起停；否则接受仓库外持续产生副本，本项目 `use_memories = false` 读不回来即可 |
| 去清 `~/.codex/memories` | 数据流是 `memories_1.sqlite` 的 `stage1_outputs` → `raw_memories.md` → `MEMORY.md` 等五处，只删 `MEMORY.md` 无效；清了也会被重建 | 不要花时间清 |
| 在裸 worktree 里开 Claude 会话 | `settings.local.json` 缺失，记忆目录退回默认位置 | 见「worktree 里的会话」 |
| 规则只写在 Claude 那侧 | Codex / dsh / opencode 不知道 `.memory/` 存在，各写各的或不写 | 步骤 4 不能省 |

## 常见错误

- 只做了 Claude 一侧，以为「别的工具本来就读 AGENTS.md 所以没问题」：它们读到的 AGENTS.md 里根本没有记忆规则。
- 自己发明一个 `MEMORY.md` 约定但没设 `autoMemoryDirectory`：Claude 的自动记忆仍写在仓库外。
- 把 `autoMemoryDirectory` 写进入库的 `settings.json`：被忽略，且带上了本机绝对路径。
- 在未被信任的临时目录里测 Codex 项目配置，得出「项目级配置无效」的错误结论。

## 参考实现

llm-wiki 模板（个人知识工作台）的 `scripts/bootstrap.sh` 是这套做法的完整脚本化版本，另含 worktree 共享钩子与 Skill 三处全局挂载；机制说明在其 `docs/workflows/记忆与多Agent.md`。
