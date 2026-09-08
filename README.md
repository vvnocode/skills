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

脚本先把本仓 clone 到 `~/.vvnocode/skills`（`SKILLS_REPO_DIR` 改位置，`SKILLS_REPO_URL` 改为 fork；早期版本放在 `~/.local/share/vvnocode-skills`，重跑安装会自动搬过来并重指链接），再把 `skills/*` 软链到三处全局发现根，幂等、只增不减：`~/.agents/skills/`（跨工具 canonical 根，dsh、opencode、Cline、Dexto、Kimi、Warp、Zed 等直接读）、`~/.claude/skills/`（Claude Code 只认此处）、`~/.codex/skills/`（Codex 只认此处）。已存在的普通目录或指向别处的链接只告警、不覆盖。各工具的规则入口与 Skill 发现根以 [vvnocode/AGENTS.md 的支持矩阵](https://github.com/vvnocode/AGENTS.md#支持矩阵) 为唯一正本，本仓不另维护。

- 更新：重跑同一条命令，内部 `git pull`，软链不用重做。
- 卸载：删掉三处发现根下的对应软链，再删 `~/.vvnocode/skills`。
- 开发：在本仓 clone 内运行 `./install.sh [skill名…]`，软链直接指向该 clone，不联网、不建托管副本。

Windows 用同名的 `install.ps1`，系统自带的 Windows PowerShell 5.1 即可，不需要管理员权限（目录以 junction 挂载）：

```powershell
irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1 | iex
```

只装指定的：

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1))) agent-memory-setup
```

托管 clone 在 `%USERPROFILE%\.vvnocode\skills`（早期版本在 `%LOCALAPPDATA%\vvnocode-skills`，重跑安装自动迁移），环境变量 `SKILLS_REPO_DIR` / `SKILLS_REPO_URL` 同样有效；在本仓 clone 内运行 `powershell -ExecutionPolicy Bypass -File .\install.ps1`。更新与卸载同上。脚本全文 ASCII、提示为英文：Windows PowerShell 5.1 的 `irm` 不去 BOM，带 BOM 会让 `irm | iex` 把首行当命令并把注释逐行执行；不带 BOM 时按 `-File` 运行又会用本地代码页解码，936 下中文会吞掉引号和换行导致解析失败，两条路径同时成立只有纯 ASCII 一种写法（2026-09-07 在 Windows 10 加 PowerShell 5.1 实测）。

带一键脚本的 skill（如 `setup.sh` / `setup.ps1`）同样不需要 clone，用法见各自目录下的 `README.md`。这类脚本作用于某个具体仓库，与装 skill 不是一回事，`install.sh` / `install.ps1` 只在装完后列出哪些 skill 自带 setup 及其挂载路径，不会代跑。

## Skill 列表

| Skill | 用途 |
|---|---|
| [agent-memory-setup](skills/agent-memory-setup/SKILL.md) | 让 Claude Code、Codex、dsh、opencode 在同一仓库共用一份指令（`AGENTS.md`）与一份仓内记忆（`.memory/`），换工具、换机器不丢上下文。附一键 `setup.sh` / `setup.ps1` 与 Codex 有效配置探针，curl / irm 直接执行的用法见 [README](skills/agent-memory-setup/README.md)。 |

## 测试

```bash
python3 -m unittest discover -s tests -v
```

`install.ps1` 的用例需要 PATH 上有 `pwsh`，没有时自动跳过。

## 约定

- 新 skill 放 `skills/<名>/SKILL.md`，frontmatter 含 `name` 与 `description`，description 写触发场景而不是功能罗列。
- 带脚本的 skill 在 `tests/` 里放离线回归测试，在临时目录里跑真实脚本，不触碰用户主目录。
- 带一键脚本的 skill 在自己目录放 `README.md`，写 `curl … | bash` 直接执行的用法；脚本要能在管道下运行，不依赖 `$0` 指向磁盘上的文件；变量后紧跟中文标点写 `${VAR}`，macOS 自带 bash 3.2 在 UTF-8 locale 下会把 `$VAR（` 的首字节并入变量名。
- 需要 Windows 时另放同名 `.ps1`，行为与 `.sh` 一致、共用同一套测试用例，`irm … | iex` 可运行；`.ps1` 全文 ASCII、无 BOM、英文提示，原因见安装节。
- 分支：`main` 为长期分支，改动在短期分支完成后 `--no-ff` 合回。

## 三件套

本仓是 vvnocode 三件套之一。三者各管一层、互相独立、安装顺序随意，缺任何一个另外两个照常工作：

| 仓库 | 管什么 | 装到哪 | 缺了会怎样 |
|---|---|---|---|
| [AGENTS.md](https://github.com/vvnocode/AGENTS.md) | 跨工具全局规则，含「项目记忆」读写规则与 llm-wiki 路由段 | `~/.vvnocode/rules`，软链到各工具的用户级规则入口 | 记忆读写规则没人下发：接线时用 `setup.sh --with-rule` 写进仓内 `AGENTS.md`；llm-wiki 路由段手工粘贴 |
| [skills](https://github.com/vvnocode/skills)（本仓） | 可公开分发的 skill，含给任意仓库接线的 `agent-memory-setup` | `~/.vvnocode/skills`，软链到三处全局 Skill 发现根 | 仓库不接线，偏好走各工具自带记忆；llm-wiki 的 bootstrap 会自动补装本仓 |
| [llm-wiki](https://github.com/vvnocode/llm-wiki) | 个人知识工作台：跨项目的机制、决策、案例 | 目录自选，`~/.llm-wiki` 软链指过去。它是数据仓、可一机多实例，不进 `~/.vvnocode` | 规则里的「全局知识工作台」整段失效，不查不写 |

运行时只有两处条件门把三者接起来：仓内有 `.memory/` 才读写记忆，本机有 `~/.llm-wiki` 才查写 wiki。装规则仓一行命令：

```bash
curl -fsSL https://raw.githubusercontent.com/vvnocode/AGENTS.md/main/install.sh | bash
```

llm-wiki 按其 README 或 `SETUP-FOR-AI.md` 部署。
