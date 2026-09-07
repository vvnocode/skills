# agent-memory-setup

让 Claude Code、Codex、dsh、opencode 在同一仓库共用一份指令（`AGENTS.md`，`CLAUDE.md` 为其软链）与一份仓内记忆（`.memory/`），换工具、换机器不丢上下文。机制对照、手工步骤与陷阱见 [SKILL.md](SKILL.md)。

## 一键搭建

不需要 clone 本仓，在目标仓库目录下执行：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/skills/agent-memory-setup/setup.sh | bash
```

参数跟在 `bash -s --` 之后：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/skills/agent-memory-setup/setup.sh | bash -s -- /path/to/repo --with-rule
```

| 参数 | 含义 |
|---|---|
| `仓库路径` | 缺省为当前所在 git 仓库根 |
| `--with-rule` | 往 `AGENTS.md` 追加「项目记忆」节。装了跨工具全局规则（如 [vvnocode/claude.md](https://github.com/vvnocode/claude.md) 的「项目记忆」节）的机器不需要；只给没有全局规则的协作者用的仓库才加 |

幂等：只补缺不覆盖；不能自动裁定的冲突只告警交人工。跑完按输出做两件人工事：往 `~/.codex/config.toml` 追加信任片段（用 Codex 才需要），再逐工具验证。Windows 无法运行本脚本，按 SKILL.md 的手工步骤做。

已用根目录 `install.sh` 装好本 skill 的机器，也可直接运行本地副本：

```bash
~/.agents/skills/agent-memory-setup/setup.sh [仓库路径] [--with-rule]
```

## 验证 Codex 有效配置

`codex doctor` 只报全局配置，看不出项目级 `.codex/config.toml` 是否被采纳。探针走 app-server 的 `config/read` 按目录解析有效值，并抓「项目未被信任」的警告：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/skills/agent-memory-setup/codex-effective-config.py | python3 - /path/to/repo
```

需要本机有 `codex` 可执行文件；不在 PATH 时追加 `--codex /path/to/codex`。
