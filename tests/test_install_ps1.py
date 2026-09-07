#!/usr/bin/env python3
"""install.ps1 的离线回归测试：与 install.sh 同一套行为契约，直接继承 test_install.InstallTest 的全部用例，只替换运行方式。

另有源文件守卫（任何平台都跑）：全 ASCII、无 BOM。带 BOM 时 5.1 的 irm 不去 BOM，irm | iex 把首行当命令、注释逐行当命令执行；
无 BOM 时 5.1 按 -File 用本地代码页解码，936 下 .NET 会把孤立首字节后的那个字节（含引号、换行）一起吞掉，任何非 ASCII 都会破坏解析。
Windows 上再按 936 / 1252 代码页解码源文件做解析与执行用例，对应 5.1 按 -File 运行的真实路径。

运行器取 PATH 上的 pwsh（PowerShell 7），没有则取 powershell（Windows PowerShell 5.1）；两者都没有时整类跳过。
Windows 上脚本建 junction，其他平台的 pwsh 建软链，断言按链接目标比对。控制台输出强制 UTF-8，避免 5.1 按代码页输出中文。

Windows 上只跑本文件：python -m unittest discover -s tests -p test_install_ps1.py -v（其余用例依赖 bash）。
"""
from __future__ import annotations

import os
import shutil
import subprocess
import unittest

import test_install as bash_tests   # 以模块引用而非 from-import，避免 unittest 把 InstallTest 在本模块再收集一次

PWSH = shutil.which("pwsh") or shutil.which("powershell")
PREAMBLE = "[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false; "   # 无 BOM 的 UTF-8：5.1 用带 BOM 的会在重定向输出开头多写 BOM
# 与 5.1 的 irm 行为一致：按 UTF-8 解码但**保留** BOM（Get-Content / ReadAllText 会去掉 BOM，模拟不忠实）
READ_LIKE_IRM = "[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes('{path}'))"


class InstallPs1SourceTest(unittest.TestCase):
    """install.ps1 源文件守卫，不需要 PowerShell。"""

    def test_pure_ascii_no_bom(self) -> None:
        """全 ASCII 且无 BOM：带 BOM 会毁掉 irm | iex，非 ASCII 会毁掉 5.1 在 936 代码页下的 -File 解析，两条路径同时成立只有纯 ASCII。"""
        raw = bash_tests.INSTALL_PS1.read_bytes()
        self.assertNotEqual(raw[:3], b"\xef\xbb\xbf")
        self.assertEqual([hex(b) for b in raw if b > 0x7F][:5], [])


@unittest.skipUnless(PWSH, "需要 pwsh 或 powershell")
class InstallPs1Test(bash_tests.InstallTest):
    """install.ps1 行为契约：用例全部来自 InstallTest。"""

    WARN_MARK = "!"
    SKIP_TEXT = "! skipped nope"

    def run_ps(self, command: str, cwd, env) -> subprocess.CompletedProcess:
        """跑一段 PowerShell 命令，stdout 按 UTF-8 解码。"""
        return subprocess.run(
            [PWSH, "-NoProfile", "-NonInteractive", "-Command", PREAMBLE + command],
            cwd=cwd, env=env, capture_output=True, encoding="utf-8", errors="replace", check=False,
        )

    def run_piped(self, *args: str) -> subprocess.CompletedProcess:
        """模拟 `irm … | iex` / `& ([scriptblock]::Create((irm …))) 参数`：脚本文本在会话内执行，$PSScriptRoot 为空，cwd 在仓库之外。"""
        quoted = " ".join(f"'{a}'" for a in args)
        text = READ_LIKE_IRM.format(path=bash_tests.INSTALL_PS1)
        command = f"& ([scriptblock]::Create(({text}))) {quoted}"
        proc = self.run_ps(command, self.elsewhere, self.env())
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        return proc

    def test_local_clone_links_to_itself(self) -> None:
        """按文件路径在本仓 clone 内运行：$PSScriptRoot 指向本仓，不联网、不建托管副本。"""
        env = {**self.env(), "SKILLS_REPO_URL": "file:///nonexistent"}   # 若尝试 clone 必失败
        proc = self.run_ps(f"& '{bash_tests.INSTALL_PS1}'", bash_tests.ROOT, env)
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        names = [d.name for d in (bash_tests.ROOT / "skills").iterdir() if (d / "SKILL.md").is_file()]
        self.assertTrue(names, "本仓 skills/ 下应至少有一个 skill")
        for name in names:
            self.assert_linked(name, bash_tests.ROOT / "skills" / name)
        self.assertFalse(self.src.exists())

    @unittest.skipUnless(os.name == "nt", "代码页 936 / 1252 只有 Windows PowerShell 自带")
    def test_parses_and_runs_under_ansi_code_pages(self) -> None:
        """5.1 按 -File 读无 BOM 文件时用本地代码页：按 936（简中）与 1252（西欧）解码都必须能解析；936 解码后在本仓模式实际执行一遍。"""
        for cp in (936, 1252):
            command = (f"$t = [IO.File]::ReadAllText('{bash_tests.INSTALL_PS1}', [Text.Encoding]::GetEncoding({cp})); "
                       "$null = [scriptblock]::Create($t); 'parsed'")
            proc = self.run_ps(command, self.elsewhere, self.env())
            self.assertEqual(proc.returncode, 0, f"cp{cp}: " + proc.stdout + proc.stderr)
            self.assertIn("parsed", proc.stdout, f"cp{cp}")
        env = {**self.env(), "SKILLS_REPO_URL": "file:///nonexistent"}
        command = (f"$t = [IO.File]::ReadAllText('{bash_tests.INSTALL_PS1}', [Text.Encoding]::GetEncoding(936)); "
                   "& ([scriptblock]::Create($t))")
        proc = self.run_ps(command, bash_tests.ROOT, env)   # cwd 在本仓：走本仓模式，不联网
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        for d in (bash_tests.ROOT / "skills").iterdir():
            if (d / "SKILL.md").is_file():
                self.assert_linked(d.name, d)


if __name__ == "__main__":
    unittest.main()
