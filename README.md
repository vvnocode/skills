# skills

个人维护、可公开分享的 Agent Skill 集合。每个 skill 一个目录 `skills/<名>/`，以 `SKILL.md` 为入口，附带的脚本与其同目录；内容不含任何本机路径、内网地址或凭据。

## 安装

不需要 clone，一条命令装全部 skill：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/install.sh | bash
```

只装指定的，skill 名跟在 `bash -s --` 之后：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/install.sh | bash -s -- agent-memory-setup
```

脚本先把本仓 clone 到 `~/.local/share/vvnocode-skills`（设了 `XDG_DATA_HOME` 则在其下；`SKILLS_REPO_DIR` 改位置，`SKILLS_REPO_URL` 改为 fork），再把 `skills/*` 软链到三处全局发现根，幂等、只增不减：`~/.agents/skills/`（跨工具 canonical 根，dsh、opencode、Cline、Dexto、Kimi、Warp、Zed 等直接读）、`~/.claude/skills/`（Claude Code 只认此处）、`~/.codex/skills/`（Codex 只认此处）。已存在的普通目录或指向别处的链接只告警、不覆盖。各工具的规则入口与 Skill 发现根以 [vvnocode/claude.md 的支持矩阵](https://github.com/vvnocode/claude.md#支持矩阵) 为唯一正本，本仓不另维护。

- 更新：重跑同一条命令，内部 `git pull`，软链不用重做。
- 卸载：删掉三处发现根下的对应软链，再删 `~/.local/share/vvnocode-skills`。
- 开发：在本仓 clone 内运行 `./install.sh [skill名…]`，软链直接指向该 clone，不联网、不建托管副本。

Windows 用同名的 `install.ps1`，Windows PowerShell 5.1 与 pwsh 7 均可，不需要管理员权限（目录以 junction 挂载）：

```powershell
irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1 | iex
```

只装指定的：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1))) agent-memory-setup
```

托管 clone 在 `%LOCALAPPDATA%\vvnocode-skills`，环境变量 `SKILLS_REPO_DIR` / `SKILLS_REPO_URL` 同样有效；在本仓 clone 内运行 `powershell -ExecutionPolicy Bypass -File .\install.ps1`。更新与卸载同上。

带一键脚本的 skill（如 `setup.sh`）同样不需要 clone，用法见各自目录下的 `README.md`；`setup.sh` 目前只有 bash 版，Windows 按其 SKILL.md 的手工步骤执行。

## Skill 列表

| Skill | 用途 |
|---|---|
| [agent-memory-setup](skills/agent-memory-setup/SKILL.md) | 让 Claude Code、Codex、dsh、opencode 在同一仓库共用一份指令（`AGENTS.md`）与一份仓内记忆（`.memory/`），换工具、换机器不丢上下文。附一键 `setup.sh` 与 Codex 有效配置探针，curl 直接执行的用法见 [README](skills/agent-memory-setup/README.md)。 |

## 测试

```bash
python3 -m unittest discover -s tests -v
```

`install.ps1` 的用例需要 PATH 上有 `pwsh`，没有时自动跳过。

## 约定

- 新 skill 放 `skills/<名>/SKILL.md`，frontmatter 含 `name` 与 `description`，description 写触发场景而不是功能罗列。
- 带脚本的 skill 在 `tests/` 里放离线回归测试，在临时目录里跑真实脚本，不触碰用户主目录。
- 带一键脚本的 skill 在自己目录放 `README.md`，写 `curl … | bash` 直接执行的用法；脚本要能在管道下运行，不依赖 `$0` 指向磁盘上的文件；变量后紧跟中文标点写 `${VAR}`，macOS 自带 bash 3.2 在 UTF-8 locale 下会把 `$VAR（` 的首字节并入变量名。
- 需要 Windows 时另放同名 `.ps1`，行为与 `.sh` 一致、共用同一套测试用例，`irm … | iex` 可运行；文件存为带 BOM 的 UTF-8。
- 分支：`main` 为长期分支，改动在短期分支完成后 `--no-ff` 合回。
