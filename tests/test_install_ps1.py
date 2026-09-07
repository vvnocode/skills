#!/usr/bin/env python3
"""install.ps1 的离线回归测试：与 install.sh 同一套行为契约，直接继承 test_install.InstallTest 的全部用例，只替换运行方式。

需要 PATH 上有 pwsh（PowerShell 7）；没有时整类跳过。非 Windows 的 pwsh 上脚本用软链代替 junction，
断言仍按软链目标比对；junction 分支只能在 Windows 上验证。
"""
from __future__ import annotations

import shutil
import subprocess
import unittest

import test_install as bash_tests   # 以模块引用而非 from-import，避免 unittest 把 InstallTest 在本模块再收集一次

PWSH = shutil.which("pwsh")


@unittest.skipUnless(PWSH, "需要 pwsh（PowerShell 7）")
class InstallPs1Test(bash_tests.InstallTest):
    """install.ps1 行为契约：用例全部来自 InstallTest。"""

    def run_piped(self, *args: str) -> subprocess.CompletedProcess:
        """模拟 `irm … | iex` / `& ([scriptblock]::Create((irm …))) 参数`：脚本文本在会话内执行，$PSScriptRoot 为空，cwd 在仓库之外。"""
        quoted = " ".join(f"'{a}'" for a in args)
        command = f"& ([scriptblock]::Create((Get-Content -Raw -LiteralPath '{bash_tests.INSTALL_PS1}'))) {quoted}"
        proc = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-Command", command],
            cwd=self.elsewhere, env=self.env(), capture_output=True, text=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def test_local_clone_links_to_itself(self) -> None:
        """按 -File 在本仓 clone 内运行：$PSScriptRoot 指向本仓，不联网、不建托管副本。"""
        env = {**self.env(), "SKILLS_REPO_URL": "file:///nonexistent"}   # 若尝试 clone 必失败
        proc = subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-File", str(bash_tests.INSTALL_PS1)],
            cwd=bash_tests.ROOT, env=env, capture_output=True, text=True, check=False,
        )
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        names = [d.name for d in (bash_tests.ROOT / "skills").iterdir() if (d / "SKILL.md").is_file()]
        self.assertTrue(names, "本仓 skills/ 下应至少有一个 skill")
        for name in names:
            self.assert_linked(name, bash_tests.ROOT / "skills" / name)
        self.assertFalse(self.src.exists())


if __name__ == "__main__":
    unittest.main()
