#!/usr/bin/env python3
"""agent-memory-setup/setup.sh 的离线回归测试：在临时 git 仓库里跑真实脚本，不触碰用户主目录与真实项目。

覆盖：
- 全新仓库一跑到位：CLAUDE.md -> AGENTS.md 软链、.memory/MEMORY.md、.claude/settings.local.json 指向仓内 .memory、
  .gitignore 忽略 settings.local.json、.codex/config.toml 三项记忆开关全关、AGENTS.md 含「项目记忆」节
- 重跑幂等：第二次运行后所有产物字节不变
- 只有 CLAUDE.md 的仓库：改名为 AGENTS.md 并建软链，正文不丢
- AGENTS.md 与 CLAUDE.md 都是普通文件且内容不同：不动任何一个，只告警，其余步骤照做
- --no-rule：不往 AGENTS.md 追加记忆节
"""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SETUP = ROOT / "skills" / "agent-memory-setup" / "setup.sh"


def sha(path: Path) -> str:
    """文件内容摘要，用于幂等比对；软链按其目标字符串计算。"""
    if path.is_symlink():
        return "link:" + os.readlink(path)
    return hashlib.sha256(path.read_bytes()).hexdigest()


class AgentMemorySetupTest(unittest.TestCase):
    """setup.sh 行为契约。"""

    def setUp(self) -> None:
        """空的临时 git 仓库。"""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.repo = Path(self.temp_dir.name).resolve() / "repo"
        self.repo.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.repo, check=True)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_setup(self, *args: str) -> subprocess.CompletedProcess:
        """在临时仓库里跑 setup.sh，HOME 指向临时目录以防误写用户主目录。"""
        env = {**os.environ, "HOME": self.temp_dir.name}
        proc = subprocess.run(
            ["bash", str(SETUP), *args], cwd=self.repo, capture_output=True, text=True, env=env, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def snapshot(self) -> dict[str, str]:
        """仓库内全部产物的摘要（排除 .git）。"""
        return {
            str(p.relative_to(self.repo)): sha(p)
            for p in self.repo.rglob("*")
            if ".git" not in p.parts and (p.is_file() or p.is_symlink())
        }

    def test_fresh_repo_gets_everything(self) -> None:
        """全新仓库一次跑齐五项产物。"""
        proc = self.run_setup()
        claude = self.repo / "CLAUDE.md"
        self.assertTrue(claude.is_symlink(), proc.stdout)
        self.assertEqual(os.readlink(claude), "AGENTS.md")
        self.assertTrue((self.repo / ".memory" / "MEMORY.md").is_file())

        settings = json.loads((self.repo / ".claude" / "settings.local.json").read_text())
        self.assertEqual(settings["autoMemoryDirectory"], str(self.repo / ".memory"))
        ignored = subprocess.run(
            ["git", "check-ignore", "-q", ".claude/settings.local.json"], cwd=self.repo, check=False,
        )
        self.assertEqual(ignored.returncode, 0, ".claude/settings.local.json 必须被 gitignore")

        toml = (self.repo / ".codex" / "config.toml").read_text()
        for key in ("generate_memories", "use_memories", "dedicated_tools"):
            self.assertRegex(toml, rf"{key}\s*=\s*false")

        agents = (self.repo / "AGENTS.md").read_text()
        self.assertIn(".memory/", agents)
        self.assertIn("MEMORY.md", agents)
        # 收尾必须给出 Codex 信任片段，路径是仓库绝对路径
        self.assertIn(f'[projects."{self.repo}"]', proc.stdout)

    def test_rerun_is_idempotent(self) -> None:
        """第二次运行不改动任何已就位产物。"""
        self.run_setup()
        before = self.snapshot()
        self.run_setup()
        self.assertEqual(before, self.snapshot())

    def test_only_claude_md_is_renamed(self) -> None:
        """仓库原本只有 CLAUDE.md：正文迁到 AGENTS.md，CLAUDE.md 变软链。"""
        (self.repo / "CLAUDE.md").write_text("# 原有规则\n\n口令 XYZZY\n")
        self.run_setup()
        self.assertTrue((self.repo / "CLAUDE.md").is_symlink())
        self.assertIn("XYZZY", (self.repo / "AGENTS.md").read_text())

    def test_conflicting_files_are_left_alone(self) -> None:
        """两份普通文件内容不同：不合并、不覆盖，告警后其余步骤照做。"""
        (self.repo / "AGENTS.md").write_text("# A\n")
        (self.repo / "CLAUDE.md").write_text("# C\n")
        proc = self.run_setup()
        self.assertFalse((self.repo / "CLAUDE.md").is_symlink())
        self.assertEqual((self.repo / "CLAUDE.md").read_text(), "# C\n")
        self.assertIn("⚠", proc.stdout)
        self.assertTrue((self.repo / ".memory" / "MEMORY.md").is_file())

    def test_no_rule_flag_skips_agents_section(self) -> None:
        """--no-rule 时 AGENTS.md 原样不动。"""
        (self.repo / "AGENTS.md").write_text("# 规则\n")
        self.run_setup("--no-rule")
        self.assertEqual((self.repo / "AGENTS.md").read_text(), "# 规则\n")


if __name__ == "__main__":
    unittest.main()
