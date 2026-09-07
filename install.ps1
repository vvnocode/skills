<#
把本仓 skills/<名>/ 挂到本机各 Agent 的全局 Skill 发现根，install.sh 的 Windows 版。幂等、只增不减。

用法（不需要手工 clone；Windows PowerShell 5.1 或 pwsh 7 均可，不需要管理员权限）：
  irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1 | iex                            # 全部
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1))) 名…   # 只装指定的
  powershell -ExecutionPolicy Bypass -File .\install.ps1 [名…]                                            # 在本仓 clone 内运行：挂本仓，开发用

仓库来源按运行位置自动判定，与 install.sh 一致：
  仓外 / 管道运行：把仓库 clone 到 $env:SKILLS_REPO_DIR（缺省 %LOCALAPPDATA%\vvnocode-skills），已存在则 git pull；
                   重跑同一条命令即更新，链接不用重做。$env:SKILLS_REPO_URL 可改为 fork 地址。
  本仓 clone 内  ：直接用所在 clone，不联网、不建托管副本。

Windows 上用 junction 挂目录：不需要管理员权限或开发者模式，工具按目录读取时与软链等价。三处发现根同 install.sh：
  ~\.agents\skills   跨工具 canonical 根
  ~\.claude\skills   Claude Code 只认此处
  ~\.codex\skills    Codex 只认此处
已存在的普通目录或指向别处的链接只告警、不覆盖。
本文件须保存为带 BOM 的 UTF-8：Windows PowerShell 5.1 按 -File 运行无 BOM 的文件时会按本地代码页读中文。
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Names = @())

# 整个脚本体放进一个脚本块：irm | iex 是在用户当前会话里执行，这样 $ErrorActionPreference 与临时变量不泄漏到用户会话。
# 致命错误用 throw 而不是 exit：iex 场景下 exit 会把用户的终端窗口一起关掉。
& {
    param([string[]]$Names)
    $ErrorActionPreference = 'Stop'

    $IsWin = $env:OS -eq 'Windows_NT'
    $RepoUrl = if ($env:SKILLS_REPO_URL) { $env:SKILLS_REPO_URL } else { 'https://github.com/vvnocode/skills.git' }
    $DataHome = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path (Join-Path $HOME '.local') 'share' }   # 非 Windows 的 pwsh（跑测试）退回 XDG 位置
    $RepoDir = if ($env:SKILLS_REPO_DIR) { $env:SKILLS_REPO_DIR } else { Join-Path $DataHome 'vvnocode-skills' }
    $Roots = @('.agents', '.claude', '.codex') | ForEach-Object { Join-Path (Join-Path $HOME $_) 'skills' }
    $LinkType = if ($IsWin) { 'Junction' } else { 'SymbolicLink' }   # junction 只有 Windows 有，其他平台的 pwsh 用软链
    $Added = 0; $Kept = 0; $Warn = 0

    # 原生命令（git）写 stderr 时，Windows PowerShell 5.1 在 Stop 偏好下可能把它当成终止错误；调用期间临时放宽，只看退出码。
    # git 的 stdout 送到宿主，不混进函数返回值。
    function Invoke-Git {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & git @args | Out-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    }
    # 链接目标与源路径比较：去掉 \\?\ 前缀（.NET 6 起 junction 目标带它）、统一为完整路径、去尾分隔符；Windows 不分大小写
    function Get-NormalizedPath([string]$Path) {
        if ($Path.StartsWith('\\?\')) { $Path = $Path.Substring(4) }
        $Path = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        if ($IsWin) { $Path.ToLowerInvariant() } else { $Path }
    }

    # ── 仓库来源：脚本所在目录（irm | iex 时 $PSScriptRoot 为空，退回当前目录）同时有 install.ps1 与 skills\ 即视为本仓 clone ──
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    if ((Test-Path (Join-Path $here 'install.ps1') -PathType Leaf) -and (Test-Path (Join-Path $here 'skills') -PathType Container)) {
        $Repo = $here
        Write-Host "· 来源：本仓 clone $Repo"
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw '✗ 需要 git' }
        if (Test-Path (Join-Path $RepoDir '.git') -PathType Container) {
            # 已有托管副本：快进更新；拉不动（本地改动、断网）就沿用现有版本，不中断安装
            if ((Invoke-Git -C $RepoDir pull -q --ff-only) -eq 0) {
                Write-Host "· 来源：托管副本 ${RepoDir}（已更新）"
            } else {
                Write-Host "⚠ $RepoDir 更新失败，沿用现有版本（本地有改动或网络不通）"; $Warn++
            }
        } elseif (Test-Path $RepoDir) {
            throw "✗ $RepoDir 已存在但不是 git 仓库，请移走后重试"
        } else {
            New-Item -ItemType Directory -Force (Split-Path $RepoDir -Parent) | Out-Null
            if ((Invoke-Git clone -q $RepoUrl $RepoDir) -ne 0) { throw "✗ clone 失败：$RepoUrl" }
            Write-Host "· 来源：已 clone $RepoUrl 到 $RepoDir"
        }
        $Repo = (Resolve-Path $RepoDir).Path
    }

    # ── 要安装的 skill 列表：显式传参或 skills\ 下全部含 SKILL.md 的目录 ──
    $SkillsDir = Join-Path $Repo 'skills'
    if ($Names.Count -eq 0) {
        $Names = @(Get-ChildItem $SkillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } | ForEach-Object { $_.Name })
    }
    if ($Names.Count -eq 0) { throw '✗ skills/ 下没有可安装的 skill' }

    # ── 挂到三处发现根 ──
    foreach ($root in $Roots) {
        New-Item -ItemType Directory -Force $root | Out-Null
        foreach ($name in $Names) {
            $src = Join-Path $SkillsDir $name
            if (-not (Test-Path (Join-Path $src 'SKILL.md') -PathType Leaf)) { Write-Host "⚠ 跳过 ${name}：skills/$name/SKILL.md 不存在"; $Warn++; continue }
            $link = Join-Path $root $name
            $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
            if ($item -and $item.LinkType) {
                # 已是链接：指向本仓即就位，指向别处只告警（可能是另一份 canonical，不代做切换）
                $target = [string](@($item.Target)[0])
                if ((Get-NormalizedPath $target) -eq (Get-NormalizedPath $src)) { $Kept++ }
                else { Write-Host "⚠ $link 已指向 ${target}，未改动"; $Warn++ }
            } elseif ($item) {
                Write-Host "⚠ $link 是普通目录/文件，未改动（如需改为链接请先自行移走）"; $Warn++
            } else {
                New-Item -ItemType $LinkType -Path $link -Value $src | Out-Null
                $Added++
            }
        }
    }
    Write-Host "· 安装完成：新建 $Added 条，已就位 $Kept 条，告警 $Warn 条（发现根：$($Roots -join ' ')）"
} $Names
