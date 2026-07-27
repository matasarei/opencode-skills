# Install the dev skills into OpenCode (Windows PowerShell).
#
#   .\install.ps1              install from this checkout
#   .\install.ps1 -Project     install into .\.opencode instead of the global config

param([switch]$Project)

$ErrorActionPreference = "Stop"
$src = $PSScriptRoot

if ($Project) {
    $target = Join-Path (Get-Location) ".opencode"
} elseif ($env:XDG_CONFIG_HOME) {
    $target = Join-Path $env:XDG_CONFIG_HOME "opencode"
} else {
    $target = Join-Path $HOME ".config\opencode"
}

$skills = Join-Path $target "skills"
$lib    = Join-Path $target "dev-lib"

Write-Host "Installing to $target"

New-Item -ItemType Directory -Force $skills | Out-Null
New-Item -ItemType Directory -Force $lib    | Out-Null

Copy-Item -Force (Join-Path $src "lib\*.sh") $lib

Get-ChildItem (Join-Path $src "skills") -Directory | ForEach-Object {
    $dest = Join-Path $skills $_.Name
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Recurse -Force $_.FullName $dest
    Write-Host "  $($_.Name)"
}

if (Test-Path (Join-Path $src "agents")) {
    $agents = Join-Path $target "agents"
    New-Item -ItemType Directory -Force $agents | Out-Null
    Copy-Item -Force (Join-Path $src "agents\*.md") $agents
}

Push-Location $src
try { git rev-parse --short HEAD 2>$null | Set-Content (Join-Path $lib ".version") }
catch { "unknown" | Set-Content (Join-Path $lib ".version") }
Pop-Location

Write-Host ""
Write-Host "Done. Type '/' in OpenCode to see:"
Write-Host "  /dev-init /dev-plan /dev-implement /dev-review /dev-pr-review /dev-pr-comment /dev-verify"
# The skills fall back to $HOME/.config/opencode/dev-lib, because a SKILL.md cannot
# know where it was installed. Any other target needs the override or every skill
# calls a path that is not there. Same check as install.sh.
$defaultLib = Join-Path $HOME ".config\opencode\dev-lib"
if ($lib -ne $defaultLib) {
    Write-Host ""
    Write-Host "This is not the default location, so the skills will not find the scripts"
    Write-Host "unless you set the override:"
    Write-Host ""
    Write-Host "    `$env:DEV_SKILLS_LIB = `"$lib`""
    Write-Host ""
    Write-Host "Add it to your PowerShell profile."
    if ($Project) { Write-Host "Or re-run without -Project to install globally instead." }
}

# ---------------------------------------------------------------- Git Bash ---
#
# This is the one thing that must be right on Windows, and it fails silently
# otherwise. OpenCode picks its shell from packages/core/src/shell.ts: on Windows
# the candidates are pwsh, powershell, Git Bash, cmd — in that order — and with
# $SHELL unset it takes the first. So the default is PowerShell, where the skills'
# `${DEV_SKILLS_LIB:-...}` is not syntax at all and every injected block fails.
#
# Find Git Bash the same way OpenCode does, so we agree on the answer.

function Find-GitBash {
    if ($env:OPENCODE_GIT_BASH_PATH) { return $env:OPENCODE_GIT_BASH_PATH }
    $git = (Get-Command git -ErrorAction SilentlyContinue).Source
    if ($git) {
        $candidate = Join-Path (Split-Path (Split-Path $git)) "bin\bash.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    foreach ($p in @("$env:ProgramFiles\Git\bin\bash.exe", "${env:ProgramFiles(x86)}\Git\bin\bash.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

$bash = Find-GitBash
$cfgPath = Join-Path $target "opencode.json"
$shellSet = $false
if (Test-Path $cfgPath) {
    try { $shellSet = [bool](Get-Content $cfgPath -Raw | ConvertFrom-Json).shell } catch { }
}

Write-Host ""
if (-not $bash) {
    Write-Host "WARNING: Git Bash was not found." -ForegroundColor Red
    Write-Host "These skills are bash scripts. Without it nothing here will run."
    Write-Host "Install Git for Windows (https://git-scm.com/download/win), or use WSL."
    Write-Host ""
    Write-Host "Do NOT rely on 'bash' being on your PATH: if WSL is installed, that resolves"
    Write-Host "to C:\Windows\System32\bash.exe, which runs in a different filesystem where"
    Write-Host "your repository paths do not exist."
} elseif ($shellSet) {
    Write-Host "Git Bash found, and opencode.json already sets a shell. Nothing to do."
} else {
    Write-Host "IMPORTANT: point OpenCode at Git Bash." -ForegroundColor Yellow
    Write-Host "OpenCode defaults to PowerShell on Windows, where these skills cannot run."
    Write-Host "Add this to $cfgPath :"
    Write-Host ""
    Write-Host ('    "shell": "' + $bash.Replace('\', '\\') + '"')
    Write-Host ""
    # Guarded: a piped or scripted install has no console to read from, and must
    # not hang waiting for one.
    $answer = ''
    try { $answer = Read-Host "Set it for you now? [y/N]" } catch { }
    if ($answer -match '^[Yy]') {
        if (Test-Path $cfgPath) { $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json }
        else { $cfg = [pscustomobject]@{ '$schema' = 'https://opencode.ai/config.json' } }
        $cfg | Add-Member -NotePropertyName shell -NotePropertyValue $bash -Force
        $cfg | ConvertTo-Json -Depth 20 | Set-Content $cfgPath -Encoding UTF8
        Write-Host "Set. Restart OpenCode." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Local models: set the context window to 64k or higher."
