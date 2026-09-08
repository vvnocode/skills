<#
vvnocode/skills install.ps1 -- Windows counterpart of install.sh.
Links skills/<name>/ from this repo into every agent's global skill root on this machine. Idempotent, add-only.

Usage (no manual clone needed; the built-in Windows PowerShell 5.1 is enough, no admin rights required):
  irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1 | iex                              # all skills
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/vvnocode/skills/main/install.ps1))) NAME...  # only the named ones
  powershell -ExecutionPolicy Bypass -File .\install.ps1 [NAME...]     # inside a clone of this repo: link that clone (development)

Where the repo comes from is decided by where the script runs, same as install.sh:
  outside a clone / piped : clone the repo into $env:SKILLS_REPO_DIR (default %USERPROFILE%\.vvnocode\skills, the same
                            convention as the rules repo at %USERPROFILE%\.vvnocode\rules), or git pull if it already
                            exists. Re-running the same command updates it; links stay valid. $env:SKILLS_REPO_URL may
                            point at a fork. Early versions kept the managed clone at %LOCALAPPDATA%\vvnocode-skills:
                            when the new location is absent and the old one holds a clone it is moved, and links in the
                            roots that point into the old location are repointed.
  inside a clone          : use that clone directly, no network, no managed copy.

Directories are mounted as junctions on Windows (no admin rights or Developer Mode needed); agents read through them
exactly like symlinks. The three roots are the same as in install.sh:
  ~\.agents\skills   cross-tool canonical root
  ~\.claude\skills   the only root Claude Code scans
  ~\.codex\skills    the only root Codex scans
Existing plain directories and links pointing elsewhere are reported and left untouched.

Encoding: this file is intentionally pure ASCII, no BOM, English messages. Verified on Windows PowerShell 5.1 (2026-09-07):
  - with a BOM, irm keeps the BOM and "irm | iex" turns the first line into a bogus command and then executes the
    comment block line by line as commands;
  - without a BOM, "-File" decodes the file with the ANSI code page, and under code page 936 the decoder swallows the
    byte after a stray lead byte (quotes and newlines included), so any non-ASCII text breaks parsing.
Both paths hold only for pure ASCII. tests/test_install_ps1.py guards this.
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Names = @())

# The whole body lives in one script block: "irm | iex" runs inside the caller's session, so $ErrorActionPreference and
# temporaries must not leak into it. Fatal errors use throw, never exit: under iex, exit would close the user's console.
& {
    param([string[]]$Names)
    $ErrorActionPreference = 'Stop'

    $IsWin = $env:OS -eq 'Windows_NT'
    $UserHome = if ($IsWin) { $env:USERPROFILE } else { $HOME }   # agents on Windows resolve ~/.claude etc. via USERPROFILE
    $RepoUrl = if ($env:SKILLS_REPO_URL) { $env:SKILLS_REPO_URL } else { 'https://github.com/vvnocode/skills.git' }
    $DataHome = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path (Join-Path $UserHome '.local') 'share' }   # non-Windows pwsh (tests): XDG location
    $RepoDir = if ($env:SKILLS_REPO_DIR) { $env:SKILLS_REPO_DIR } else { Join-Path (Join-Path $UserHome '.vvnocode') 'skills' }
    $LegacyDir = Join-Path $DataHome 'vvnocode-skills'   # early default managed location, migrated below
    $Roots = @('.agents', '.claude', '.codex') | ForEach-Object { Join-Path (Join-Path $UserHome $_) 'skills' }
    $LinkType = if ($IsWin) { 'Junction' } else { 'SymbolicLink' }   # junctions exist only on Windows; other platforms use symlinks
    $Added = 0; $Kept = 0; $Moved = 0; $Warn = 0

    # Native commands (git) writing to stderr can be promoted to terminating errors by Windows PowerShell 5.1 under
    # 'Stop'; relax the preference for the call and judge by exit code only. git's stdout goes to the host so the
    # function's return value stays clean.
    function Invoke-Git {
        $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & git @args | Out-Host; return $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    }
    # Compare a link target with a source path: strip the \\?\ prefix (.NET 6+ reports junction targets with it),
    # normalise to a full path, drop trailing separators, ignore case on Windows.
    function Get-NormalizedPath([string]$Path) {
        if ($Path.StartsWith('\\?\')) { $Path = $Path.Substring(4) }
        $Path = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        if ($IsWin) { $Path.ToLowerInvariant() } else { $Path }
    }

    # -- Repo source: the script directory ($PSScriptRoot is empty under "irm | iex", fall back to the current directory)
    #    counts as a clone of this repo when it holds both install.ps1 and skills\ --
    $here = if ($PSScriptRoot) { $PSScriptRoot } else { $PWD.Path }
    if ((Test-Path (Join-Path $here 'install.ps1') -PathType Leaf) -and (Test-Path (Join-Path $here 'skills') -PathType Container)) {
        $Repo = $here
        Write-Host "* source: local clone $Repo"
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'x git is required' }
        # Legacy location: only when the default is in use, the new location is absent and the old one is a git repo
        if (-not $env:SKILLS_REPO_DIR -and -not (Test-Path $RepoDir) -and (Test-Path (Join-Path $LegacyDir '.git') -PathType Container)) {
            New-Item -ItemType Directory -Force (Split-Path $RepoDir -Parent) | Out-Null
            Move-Item -LiteralPath $LegacyDir -Destination $RepoDir
            Write-Host "* managed clone moved from $LegacyDir to $RepoDir; links into the old location will be repointed"
        }
        if (Test-Path (Join-Path $RepoDir '.git') -PathType Container) {
            # Managed copy exists: fast-forward it; if that fails (local edits, no network) keep what is there and go on
            if ((Invoke-Git -C $RepoDir pull -q --ff-only) -eq 0) {
                Write-Host "* source: managed clone $RepoDir (updated)"
            } else {
                Write-Host "! $RepoDir could not be updated, keeping the current version (local changes or no network)"; $Warn++
            }
        } elseif (Test-Path $RepoDir) {
            throw "x $RepoDir exists but is not a git repository; move it away and retry"
        } else {
            New-Item -ItemType Directory -Force (Split-Path $RepoDir -Parent) | Out-Null
            if ((Invoke-Git clone -q $RepoUrl $RepoDir) -ne 0) { throw "x clone failed: $RepoUrl" }
            Write-Host "* source: cloned $RepoUrl into $RepoDir"
        }
        $Repo = (Resolve-Path $RepoDir).Path
    }

    # -- Skills to install: the names given, or every directory under skills\ that has a SKILL.md --
    $SkillsDir = Join-Path $Repo 'skills'
    if ($Names.Count -eq 0) {
        $Names = @(Get-ChildItem $SkillsDir -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } | ForEach-Object { $_.Name })
    }
    if ($Names.Count -eq 0) { throw 'x nothing to install under skills/' }

    # -- Link into the three roots --
    foreach ($root in $Roots) {
        New-Item -ItemType Directory -Force $root | Out-Null
        foreach ($name in $Names) {
            $src = Join-Path $SkillsDir $name
            if (-not (Test-Path (Join-Path $src 'SKILL.md') -PathType Leaf)) { Write-Host "! skipped ${name}: skills/$name/SKILL.md not found"; $Warn++; continue }
            $link = Join-Path $root $name
            $item = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
            if ($item -and $item.LinkType) {
                # Already a link: pointing at this repo means done; pointing into the legacy managed location was made by an
                # early version of this script and is repointed; pointing elsewhere is only reported (may be another canonical copy)
                $target = [string](@($item.Target)[0])
                $legacyPrefix = (Get-NormalizedPath $LegacyDir) + [IO.Path]::DirectorySeparatorChar
                if ((Get-NormalizedPath $target) -eq (Get-NormalizedPath $src)) { $Kept++ }
                elseif ((Get-NormalizedPath $target).StartsWith($legacyPrefix)) {
                    $item.Delete()   # removes the link only, never its target
                    New-Item -ItemType $LinkType -Path $link -Value $src | Out-Null
                    $Moved++
                }
                else { Write-Host "! $link already points to ${target}, left unchanged"; $Warn++ }
            } elseif ($item) {
                Write-Host "! $link is a plain directory or file, left unchanged (move it away to replace it with a link)"; $Warn++
            } else {
                New-Item -ItemType $LinkType -Path $link -Value $src | Out-Null
                $Added++
            }
        }
    }
    Write-Host "* done: added $Added, kept $Kept, repointed $Moved, warnings $Warn (roots: $($Roots -join ' '))"

    # -- Skills that ship a setup script are only announced, never run: a setup acts on one specific repo,
    #    installing skills acts on the whole machine --
    foreach ($name in $Names) {
        if (-not (Test-Path (Join-Path (Join-Path $SkillsDir $name) 'setup.ps1') -PathType Leaf)) { continue }
        $setup = Join-Path (Join-Path $Roots[0] $name) 'setup.ps1'
        Write-Host "* $name ships setup.ps1: inside the target repo run: powershell -ExecutionPolicy Bypass -File `"$setup`" [args]; see skills/$name/README.md"
    }
} $Names
