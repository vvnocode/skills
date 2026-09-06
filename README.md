# skills

个人维护、可公开分享的 Agent Skill 集合。每个 skill 一个目录 `skills/<名>/`，以 `SKILL.md` 为入口，附带的脚本与其同目录；内容不含任何本机路径、内网地址或凭据。

## 安装

```bash
git clone https://github.com/vvnocode/skills.git
cd skills && ./install.sh          # 全部；或 ./install.sh agent-memory-setup 只装指定的
```

`install.sh` 把 `skills/*` 软链到三处全局发现根，幂等、只增不减：

| 发现根 | 谁读它 |
|---|---|
| `~/.agents/skills/` | 跨工具约定俗成的 canonical 根：dsh、opencode、Cline、Dexto、Kimi、Warp、Zed 等 |
| `~/.claude/skills/` | Claude Code（不扫 `~/.agents/skills`） |
| `~/.codex/skills/` | Codex（不扫 `~/.agents/skills`） |

opencode 同时扫 `~/.claude/skills` 与 `~/.agents/skills`，不必另挂 `~/.config/opencode/skills`。新电脑只需 clone 加一次 `./install.sh`；仓库更新后 `git pull` 即生效，软链不用重做。卸载时手工删除对应软链。

## Skill 列表

| Skill | 用途 |
|---|---|
| [agent-memory-setup](skills/agent-memory-setup/SKILL.md) | 让 Claude Code、Codex、dsh、opencode 在同一仓库共用一份指令（`AGENTS.md`）与一份仓内记忆（`.memory/`），换工具、换机器不丢上下文。附一键 `setup.sh` 与 Codex 有效配置探针。 |

## 测试

```bash
python3 -m unittest discover -s tests -v
```

## 约定

- 新 skill 放 `skills/<名>/SKILL.md`，frontmatter 含 `name` 与 `description`，description 写触发场景而不是功能罗列。
- 带脚本的 skill 在 `tests/` 里放离线回归测试，在临时目录里跑真实脚本，不触碰用户主目录。
- 分支：`main` 为长期分支，改动在短期分支完成后 `--no-ff` 合回。
