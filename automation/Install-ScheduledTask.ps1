<#
.SYNOPSIS
  Register a Windows Scheduled Task that runs the Jira-assign poller every N minutes.
#>
[CmdletBinding()]
param(
    [int]$IntervalMinutes = 60,
    [string]$TaskName = 'JiraAiAssignPoller'
)

$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Invoke-JiraAssignPoller.ps1'
$vbs = Join-Path $PSScriptRoot 'Invoke-JiraAssignPoller-Silent.vbs'
if (-not (Test-Path -LiteralPath $script)) { throw "Missing $script" }
if (-not (Test-Path -LiteralPath $vbs)) { throw "Missing $vbs" }

# Launch via wscript + VBS (window style 0) so the periodic poller does not flash a console.
# Direct powershell.exe -WindowStyle Hidden still briefly shows a window on many hosts.
$arg = "//B //Nologo `"$vbs`""
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument $arg
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -Hidden
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal -Force | Out-Null

Write-Host "Scheduled task '$TaskName' registered (every $IntervalMinutes minute(s), silent via wscript)."
Write-Host "Launcher: $vbs"
Write-Host "Script: $script"
Write-Host "To remove: Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"
