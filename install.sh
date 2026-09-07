#!/usr/bin/env bash
# 把本仓 skills/<名>/ 软链到本机各 Agent 的全局 Skill 发现根。幂等、只增不减。
#
# 用法（不需要手工 clone）：
#   curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/install.sh | bash              # 全部
#   curl -fsSL https://raw.githubusercontent.com/vvnocode/skills/main/install.sh | bash -s -- 名…    # 只装指定的
#   ./install.sh [名…]                                                    # 在本仓 clone 内运行：软链指向本仓，开发用
#
# 仓库来源按运行位置自动判定：
#   仓外 / 管道运行：把仓库 clone 到 $SKILLS_REPO_DIR（缺省 ${XDG_DATA_HOME:-~/.local/share}/vvnocode-skills），
#                    已存在则 git pull；重跑同一条命令即更新，软链不用重做。SKILLS_REPO_URL 可改为 fork 地址。
#   本仓 clone 内  ：直接用所在 clone，不联网、不建托管副本。
# 已存在的普通目录或指向别处的链接只告警、不覆盖。
#
# 三处发现根缺一不可，三处覆盖本机常见 Agent：
#   ~/.agents/skills   跨工具约定俗成的 canonical 根：dsh、opencode、Cline、Dexto、Kimi、Warp、Zed 等直接读它
#   ~/.claude/skills   Claude Code 只认此处，不扫 ~/.agents/skills
#   ~/.codex/skills    Codex 只认此处，不扫 ~/.agents/skills
# opencode 同时扫 ~/.claude/skills 与 ~/.agents/skills，故不必另挂 ~/.config/opencode/skills。
set -euo pipefail

# 整个脚本体包进 main：curl | bash 时 bash 边读边执行，包成函数后必须读完整个脚本才开始执行，
# 下载中断不会执行半截脚本，读 stdin 的子进程也拿不到脚本正文。
# 注意：变量后紧跟中文标点必须写 ${VAR}。macOS 自带 bash 3.2 在 UTF-8 locale 下会把 $VAR（ 的首字节并入变量名。
main() {

    REPO_URL="${SKILLS_REPO_URL:-https://github.com/vvnocode/skills.git}"
    REPO_DIR="${SKILLS_REPO_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/vvnocode-skills}"
    ROOTS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills")
    ADDED=0; KEPT=0; WARN=0

    # ── 仓库来源 ──
    # $0 所在目录同时有 install.sh 与 skills/ 即视为本仓 clone；管道运行时 $0 是 bash（或 /dev/fd/N），落到托管副本分支。
    HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P || true)
    if [ -n "$HERE" ] && [ -f "$HERE/install.sh" ] && [ -d "$HERE/skills" ]; then
        REPO="$HERE"
        echo "· 来源：本仓 clone $REPO"
    else
        command -v git >/dev/null || { echo "✗ 需要 git"; exit 1; }
        if [ -d "$REPO_DIR/.git" ]; then
            # 已有托管副本：快进更新；拉不动（本地改动、断网）就沿用现有版本，不中断安装
            if git -C "$REPO_DIR" pull -q --ff-only; then
                echo "· 来源：托管副本 ${REPO_DIR}（已更新）"
            else
                echo "⚠ $REPO_DIR 更新失败，沿用现有版本（本地有改动或网络不通）"; WARN=$((WARN+1))
            fi
        elif [ -e "$REPO_DIR" ]; then
            echo "✗ $REPO_DIR 已存在但不是 git 仓库，请移走后重试"; exit 1
        else
            mkdir -p "$(dirname "$REPO_DIR")"
            git clone -q "$REPO_URL" "$REPO_DIR"
            echo "· 来源：已 clone $REPO_URL 到 $REPO_DIR"
        fi
        REPO=$(cd "$REPO_DIR" && pwd -P)
    fi

    # ── 要安装的 skill 列表：显式传参或 skills/ 下全部含 SKILL.md 的目录 ──
    NAMES=("$@")
    if [ ${#NAMES[@]} -eq 0 ]; then
        for d in "$REPO"/skills/*/; do
            [ -f "$d/SKILL.md" ] && NAMES+=("$(basename "$d")")
        done
    fi
    [ ${#NAMES[@]} -eq 0 ] && { echo "✗ skills/ 下没有可安装的 skill"; exit 1; }

    # ── 软链到三处发现根 ──
    for root in "${ROOTS[@]}"; do
        mkdir -p "$root"
        for name in "${NAMES[@]}"; do
            src="$REPO/skills/$name"
            [ -f "$src/SKILL.md" ] || { echo "⚠ 跳过 ${name}：skills/$name/SKILL.md 不存在"; WARN=$((WARN+1)); continue; }
            link="$root/$name"
            if [ -L "$link" ]; then
                # 已是软链：指向本仓即就位，指向别处只告警（可能是另一份 canonical，不代做切换）
                if [ "$(readlink "$link")" = "$src" ]; then KEPT=$((KEPT+1)); else echo "⚠ $link 已指向 $(readlink "$link")，未改动"; WARN=$((WARN+1)); fi
            elif [ -e "$link" ]; then
                echo "⚠ $link 是普通目录/文件，未改动（如需改为链接请先自行移走）"; WARN=$((WARN+1))
            else
                ln -s "$src" "$link"; ADDED=$((ADDED+1))
            fi
        done
    done
    echo "· 安装完成：新建 $ADDED 条，已就位 $KEPT 条，告警 $WARN 条（发现根：${ROOTS[*]}）"

    # ── 自带 setup 脚本的 skill 只提示、不代跑：setup 作用于某个具体仓库，装 skill 作用于整台机器，两者不是一回事 ──
    for name in "${NAMES[@]}"; do
        [ -f "$REPO/skills/$name/setup.sh" ] || continue
        echo "· $name 自带 setup.sh：进入目标仓库后运行 ${ROOTS[0]}/$name/setup.sh [参数]，用法见 skills/$name/README.md"
    done
}

main "$@"
