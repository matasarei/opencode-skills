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

Write-Host ""
Write-Host "The scripts are bash. On Windows they need Git Bash, which ships with Git for"
Write-Host "Windows. Set OpenCode's shell to Git Bash if tool calls fail with 'bash: not found'."
Write-Host ""
Write-Host "Local models: set the context window to 64k or higher."
