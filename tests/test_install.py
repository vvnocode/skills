#!/usr/bin/env python3
"""install.sh 的离线回归测试：HOME 与托管仓目录都指向临时目录，远端用本地 file:// 仓库代替 GitHub，不联网、不触碰用户主目录。

覆盖：
- 管道运行（curl | bash）：脚本不在磁盘上、cwd 在仓库之外，自行 clone 到 SKILLS_REPO_DIR，再把每个 skill 软链到三处发现根
- 重跑：托管副本 git pull 拿到新 skill，已有软链原样不动
- 传 skill 名：只装指定的
- 在本仓 clone 内直接运行：不 clone、不建托管副本，软链直接指向本仓
- 发现根已有指向别处的同名链接：只告警不覆盖
- 传了不存在的 skill 名：告警跳过，其余照装
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "install.sh"
INSTALL_PS1 = ROOT / "install.ps1"
# 三处全局发现根，相对 HOME
DISCOVERY_ROOTS = (".agents/skills", ".claude/skills", ".codex/skills")
GIT_IDENTITY = ["-c", "user.name=test", "-c", "user.email=test@example.com"]


class InstallTest(unittest.TestCase):
    """install.sh 行为契约。"""

    def setUp(self) -> None:
        """临时 HOME、临时远端仓、临时托管副本目录、仓库之外的工作目录。"""
        self.temp_dir = tempfile.TemporaryDirectory()
        tmp = Path(self.temp_dir.name).resolve()
        self.home = tmp / "home"
        self.origin = tmp / "origin"
        self.src = tmp / "src"
        self.elsewhere = tmp / "elsewhere"
        self.home.mkdir()
        self.elsewhere.mkdir()

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    # ── 构造远端 ──
    def make_origin(self, *names: str) -> None:
        """建一个形如本仓的远端：install.sh + skills/<名>/SKILL.md，提交到 main。"""
        self.origin.mkdir()
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=self.origin, check=True)
        for script in (INSTALL, INSTALL_PS1):
            shutil.copy(script, self.origin / script.name)
        for name in names:
            self.write_skill(name)
        self.commit("init")

    def write_skill(self, name: str) -> None:
        skill = self.origin / "skills" / name
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text(f"---\nname: {name}\ndescription: test\n---\n")

    def commit(self, msg: str) -> None:
        subprocess.run(["git", "add", "-A"], cwd=self.origin, check=True)
        subprocess.run(["git", *GIT_IDENTITY, "commit", "-q", "-m", msg], cwd=self.origin, check=True)

    # ── 运行 ──
    def env(self) -> dict[str, str]:
        return {
            **os.environ,
            "HOME": str(self.home),
            # 显式 UTF-8：macOS 自带 bash 3.2 只在 UTF-8 locale 下走多字节解析路径，脚本里的中文提示必须在此路径下也正确
            "LC_ALL": "en_US.UTF-8",
            "SKILLS_REPO_URL": f"file://{self.origin}",
            "SKILLS_REPO_DIR": str(self.src),
        }

    def run_piped(self, *args: str) -> subprocess.CompletedProcess:
        """模拟 `curl ... | bash -s -- 参数`：脚本从 stdin 进入，$0 是 bash，cwd 在仓库之外。"""
        proc = subprocess.run(
            ["bash", "-s", "--", *args], input=INSTALL.read_text(encoding="utf-8"),
            cwd=self.elsewhere, env=self.env(), capture_output=True, text=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def link(self, root: str, name: str) -> Path:
        return self.home / root / name

    def assert_linked(self, name: str, target: Path) -> None:
        """三处发现根都有指向 target 的软链。"""
        for root in DISCOVERY_ROOTS:
            link = self.link(root, name)
            self.assertTrue(link.is_symlink(), f"{link} 应为软链")
            self.assertEqual(os.readlink(link), str(target))

    # ── 用例 ──
    def test_piped_bootstraps_clone_and_links(self) -> None:
        """管道运行：自行 clone 到 SKILLS_REPO_DIR，三处发现根各得一条软链，cwd 不留任何东西。"""
        self.make_origin("alpha", "beta")
        self.run_piped()
        self.assertTrue((self.src / ".git").is_dir(), "应在 SKILLS_REPO_DIR 建托管副本")
        for name in ("alpha", "beta"):
            self.assert_linked(name, self.src / "skills" / name)
        self.assertEqual(list(self.elsewhere.iterdir()), [])

    def test_piped_rerun_pulls_new_skill(self) -> None:
        """重跑：远端新增的 skill 被 pull 下来并挂上，旧软链不动。"""
        self.make_origin("alpha")
        self.run_piped()
        self.write_skill("gamma")
        self.commit("add gamma")
        self.run_piped()
        self.assert_linked("alpha", self.src / "skills" / "alpha")
        self.assert_linked("gamma", self.src / "skills" / "gamma")

    def test_piped_with_names_installs_only_those(self) -> None:
        """传 skill 名只装指定的。"""
        self.make_origin("alpha", "beta")
        self.run_piped("alpha")
        self.assert_linked("alpha", self.src / "skills" / "alpha")
        for root in DISCOVERY_ROOTS:
            self.assertFalse(self.link(root, "beta").exists())

    def test_local_clone_links_to_itself(self) -> None:
        """在本仓 clone 内直接运行：不联网、不建托管副本，软链指向本仓自身。"""
        env = {**self.env(), "SKILLS_REPO_URL": "file:///nonexistent"}   # 若尝试 clone 必失败
        proc = subprocess.run(
            ["bash", str(INSTALL)], cwd=ROOT, env=env, capture_output=True, text=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        names = [d.name for d in (ROOT / "skills").iterdir() if (d / "SKILL.md").is_file()]
        self.assertTrue(names, "本仓 skills/ 下应至少有一个 skill")
        for name in names:
            self.assert_linked(name, ROOT / "skills" / name)
        self.assertFalse(self.src.exists())

    def test_existing_foreign_link_is_kept(self) -> None:
        """发现根已有指向别处的同名链接：只告警，不覆盖。"""
        self.make_origin("alpha")
        other = self.home / "other"
        other.mkdir()
        (self.home / ".claude" / "skills").mkdir(parents=True)
        self.link(".claude/skills", "alpha").symlink_to(other)
        proc = self.run_piped()
        self.assertEqual(os.readlink(self.link(".claude/skills", "alpha")), str(other))
        self.assertIn("⚠", proc.stdout)
        self.assertEqual(os.readlink(self.link(".agents/skills", "alpha")), str(self.src / "skills" / "alpha"))

    def test_unknown_name_warns_and_continues(self) -> None:
        """传了不存在的 skill 名：告警跳过，其余照装，退出码为 0。"""
        self.make_origin("alpha")
        proc = self.run_piped("alpha", "nope")
        self.assertIn("⚠ 跳过 nope", proc.stdout)
        self.assert_linked("alpha", self.src / "skills" / "alpha")


if __name__ == "__main__":
    unittest.main()
