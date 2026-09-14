<#
.SYNOPSIS
  Register a Windows Scheduled Task that runs the Jira-assign poller every N minutes.
#>
[CmdletBinding()]
param(
    [int]$IntervalMinutes = 5,
    [string]$TaskName = 'JiraAiAssignPoller'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Invoke-JiraAssignPoller.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "Missing $script" }

$arg = "-NoProfile -ExecutionPolicy Bypass -File `"$script`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration ([TimeSpan]::MaxValue)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Scheduled task '$TaskName' registered (every $IntervalMinutes minute(s))."
Write-Host "Script: $script"
Write-Host "To remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
