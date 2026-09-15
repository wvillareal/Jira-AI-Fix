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

# -WindowStyle Hidden keeps the periodic poller off your desktop.
$arg = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -Hidden
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Scheduled task '$TaskName' registered (every $IntervalMinutes minute(s), hidden window)."
Write-Host "Script: $script"
Write-Host "To remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
