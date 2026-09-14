#Requires -Version 5.1
<#
.SYNOPSIS
  Install JIRA-AI-Fix skill + assignment automation from this clone into the user profile.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$skillSrc = $RepoRoot
foreach ($required in @('SKILL.md', 'runbook', 'Setup-JiraAiFix.ps1')) {
    if (-not (Test-Path -LiteralPath (Join-Path $skillSrc $required))) {
        throw "Not a Jira-AI-Fix package root (missing $required): $RepoRoot"
    }
}

$claudeSkill = Join-Path $env:USERPROFILE '.claude\skills\jira-ai-fix'
$cursorSkill = Join-Path $env:USERPROFILE '.cursor\skills\jira-ai-fix'
$autoDest = Join-Path $env:USERPROFILE '.jira-ai-automation'

function Copy-SkillTree {
    param([string]$Dest)
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    foreach ($name in @('SKILL.md', 'DRAFT_MODE.md', 'Setup-JiraAiFix.ps1', 'config', 'runbook', 'standards')) {
        $src = Join-Path $skillSrc $name
        if (-not (Test-Path -LiteralPath $src)) { continue }
        $dst = Join-Path $Dest $name
        if (Test-Path -LiteralPath $dst) { Remove-Item -Recurse -Force -LiteralPath $dst }
        Copy-Item -Recurse -Force -LiteralPath $src -Destination $dst
    }
    Write-Host "Installed skill -> $Dest"
}

Copy-SkillTree -Dest $claudeSkill
Copy-SkillTree -Dest $cursorSkill

New-Item -ItemType Directory -Force -Path $autoDest | Out-Null
$autoSrc = Join-Path $RepoRoot 'automation'
foreach ($name in @('JiraAiAutomation.ps1', 'Invoke-JiraAssignPoller.ps1', 'Install-ScheduledTask.ps1', 'config.example.json', 'README.md')) {
    $src = Join-Path $autoSrc $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -Force -LiteralPath $src -Destination (Join-Path $autoDest $name)
    }
}

$liveConfig = Join-Path $autoDest 'config.json'
$exampleConfig = Join-Path $autoDest 'config.example.json'
if (-not (Test-Path -LiteralPath $liveConfig) -and (Test-Path -LiteralPath $exampleConfig)) {
    Copy-Item -Force -LiteralPath $exampleConfig -Destination $liveConfig
    Write-Host "Created $liveConfig from example (set cursorApiKey)."
}
else {
    Write-Host "Left existing config alone: $liveConfig"
}

Write-Host "Automation scripts -> $autoDest"
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. powershell -ExecutionPolicy Bypass -File .\Setup-JiraAiFix.ps1'
Write-Host '  2. Edit %USERPROFILE%\.jira-ai-automation\config.json (cursorApiKey + repos)'
Write-Host '  3. Optional: .\automation\Install-ScheduledTask.ps1  (after install, run from user profile copy)'
Write-Host "     powershell -ExecutionPolicy Bypass -File `"$autoDest\Install-ScheduledTask.ps1`""
