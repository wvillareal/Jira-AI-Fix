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
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
}
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    throw 'RepoRoot could not be resolved. Pass -RepoRoot explicitly.'
}

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
$failureLogs = Join-Path $autoDest 'logs\failures'
New-Item -ItemType Directory -Force -Path $failureLogs | Out-Null
$autoSrc = Join-Path $RepoRoot 'automation'
foreach ($name in @('JiraAiAutomation.ps1', 'Invoke-JiraAssignPoller.ps1', 'Install-ScheduledTask.ps1', 'config.example.json', 'README.md')) {
    $src = Join-Path $autoSrc $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -Force -LiteralPath $src -Destination (Join-Path $autoDest $name)
    }
}

$runnerSrc = Join-Path $autoSrc 'local-runner'
$runnerDest = Join-Path $autoDest 'local-runner'
if (Test-Path -LiteralPath $runnerSrc) {
    New-Item -ItemType Directory -Force -Path $runnerDest | Out-Null
    Copy-Item -Force -LiteralPath (Join-Path $runnerSrc 'package.json') -Destination $runnerDest
    Copy-Item -Force -LiteralPath (Join-Path $runnerSrc 'run-jira-ai-fix.mjs') -Destination $runnerDest
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm) {
        Push-Location $runnerDest
        try {
            Write-Host 'npm install @cursor/sdk in local-runner...'
            & npm install --omit=dev
        }
        finally { Pop-Location }
    }
    else {
        Write-Host 'WARN: npm not found; install Node.js then run npm install in local-runner.'
    }
    Write-Host "Local runner -> $runnerDest"
}

$liveConfig = Join-Path $autoDest 'config.json'
$exampleConfig = Join-Path $autoDest 'config.example.json'
if (-not (Test-Path -LiteralPath $liveConfig) -and (Test-Path -LiteralPath $exampleConfig)) {
    Copy-Item -Force -LiteralPath $exampleConfig -Destination $liveConfig
    Write-Host "Created $liveConfig from example (mode local)."
}
else {
    Write-Host "Left existing config alone: $liveConfig"
    Write-Host '  Tip: set "mode": "local" for unattended jira-ai-fix (needs CURSOR_API_KEY + Node).'
}

Write-Host "Automation scripts -> $autoDest"
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. powershell -ExecutionPolicy Bypass -File .\Setup-JiraAiFix.ps1'
Write-Host '  2. Set CURSOR_API_KEY user env; set "mode": "local" in config.json'
Write-Host '  3. Optional: Install-ScheduledTask.ps1 from the user profile copy'
Write-Host "     powershell -ExecutionPolicy Bypass -File `"$autoDest\Install-ScheduledTask.ps1`""
