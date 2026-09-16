' Silent launcher for the Jira-assign poller scheduled task.
' Window style 0 avoids the brief PowerShell console flash that
' -WindowStyle Hidden still shows on some Windows builds.
Option Explicit
Dim sh, fso, dir, ps1, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = dir & "\Invoke-JiraAssignPoller.ps1"
If Not fso.FileExists(ps1) Then
  WScript.Quit 1
End If
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & ps1 & """"
Set sh = CreateObject("WScript.Shell")
' 0 = hidden, False = do not wait (task returns immediately; poller runs detached)
sh.Run cmd, 0, False
