#!/usr/bin/env bash
# 把本仓 skills/<名>/ 软链到本机各 Agent 的全局 Skill 发现根。幂等、只增不减。
#
# 用法：./install.sh [skill名...]      缺省安装全部；已存在的普通目录或指向别处的链接只告警、不覆盖。
#
# 三处发现根缺一不可，三处覆盖本机常见 Agent：
#   ~/.agents/skills   跨工具约定俗成的 canonical 根：dsh、opencode、Cline、Dexto、Kimi、Warp、Zed 等直接读它
#   ~/.claude/skills   Claude Code 只认此处，不扫 ~/.agents/skills
#   ~/.codex/skills    Codex 只认此处，不扫 ~/.agents/skills
# opencode 同时扫 ~/.claude/skills 与 ~/.agents/skills，故不必另挂 ~/.config/opencode/skills。
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd -P)
ROOTS=("$HOME/.agents/skills" "$HOME/.claude/skills" "$HOME/.codex/skills")

# 要安装的 skill 列表：显式传参或 skills/ 下全部含 SKILL.md 的目录
NAMES=("$@")
if [ ${#NAMES[@]} -eq 0 ]; then
    for d in "$REPO"/skills/*/; do
        [ -f "$d/SKILL.md" ] && NAMES+=("$(basename "$d")")
    done
fi
[ ${#NAMES[@]} -eq 0 ] && { echo "✗ skills/ 下没有可安装的 skill"; exit 1; }

ADDED=0; KEPT=0; WARN=0
for root in "${ROOTS[@]}"; do
    mkdir -p "$root"
    for name in "${NAMES[@]}"; do
        src="$REPO/skills/$name"
        [ -f "$src/SKILL.md" ] || { echo "⚠ 跳过 $name：skills/$name/SKILL.md 不存在"; WARN=$((WARN+1)); continue; }
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
