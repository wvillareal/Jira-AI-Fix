#Requires -Version 5.1
<#
.SYNOPSIS
  Helpers for Jira-assign automation (Desktop notify / future local agent).
#>

function Get-JiraAiAutomationRoot {
    Join-Path $env:USERPROFILE '.jira-ai-automation'
}

function Get-JiraAiDraftsRoot {
    Join-Path $env:USERPROFILE '.jira-ai-drafts'
}

function Get-JiraAiLogsRoot {
    $dir = Join-Path (Get-JiraAiAutomationRoot) 'logs'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $dir
}

# When set, Write-JiraAiLog / Get-JiraAiProcessLogPath target MMddyyyy_<KEY>.txt
$script:JiraAiActiveLogKey = $null

function Get-JiraAiProcessLogPath {
    param(
        [string]$JiraKey = $null
    )
    $key = $null
    if (-not [string]::IsNullOrWhiteSpace($JiraKey)) {
        $key = $JiraKey.Trim().ToUpperInvariant()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($script:JiraAiActiveLogKey)) {
        $key = $script:JiraAiActiveLogKey.Trim().ToUpperInvariant()
    }

    $stamp = '{0:MMddyyyy}' -f (Get-Date)
    if ($key) {
        # Sanitize for Windows filenames (keys are normally PROJECT-1234).
        $safe = ($key -replace '[^\w\-]', '_')
        return (Join-Path (Get-JiraAiLogsRoot) ('{0}_{1}.txt' -f $stamp, $safe))
    }
    # Poller housekeeping (busy skip, no candidates, etc.) stays on the dated file.
    Join-Path (Get-JiraAiLogsRoot) ('{0}.txt' -f $stamp)
}

function Set-JiraAiProcessLogContext {
    <#
      Start writing process logs to MMddyyyy_<JIRA_KEY>.txt for this investigation.
    #>
    param(
        [Parameter(Mandatory)][string]$JiraKey
    )
    $key = $JiraKey.Trim().ToUpperInvariant()
    $path = Get-JiraAiProcessLogPath -JiraKey $key

    # One pointer line on the daily log so operators can find the per-Jira file.
    $script:JiraAiActiveLogKey = $null
    try {
        $line = '{0:yyyy-MM-dd HH:mm:ss} [INFO] Investigation log for {1}: {2}' -f (Get-Date), $key, $path
        Add-Content -LiteralPath (Get-JiraAiProcessLogPath) -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
        Write-Host $line
    }
    catch { }
    $script:JiraAiActiveLogKey = $key
    $path
}

function Clear-JiraAiProcessLogContext {
    $script:JiraAiActiveLogKey = $null
}

function Get-JiraAiRunLockPath {
    Join-Path (Get-JiraAiAutomationRoot) 'run.lock'
}

function Get-JiraAiCurrentAgentPath {
    Join-Path (Get-JiraAiAutomationRoot) 'current-agent.json'
}

function Get-JiraAiLockStaleMinutes {
    param($AutomationConfig)
    $minutes = 45
    if ($AutomationConfig -and $null -ne $AutomationConfig.lockStaleMinutes) {
        try {
            $parsed = [int]$AutomationConfig.lockStaleMinutes
            if ($parsed -gt 0) { $minutes = $parsed }
        }
        catch { }
    }
    $minutes
}

function Get-JiraAiAutomationMode {
    param($AutomationConfig)
    $mode = 'notify'
    if ($AutomationConfig.mode) { $mode = ([string]$AutomationConfig.mode).Trim().ToLowerInvariant() }
    # cloud is retired - Desktop/local skill path only.
    if ($mode -eq 'cloud') { return 'notify' }
    if ($mode -ne 'notify' -and $mode -ne 'local') { $mode = 'notify' }
    $mode
}

function Write-JiraAiLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $logDir = Get-JiraAiLogsRoot
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    $logFile = Get-JiraAiProcessLogPath
    try {
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    }
    catch { }
    Write-Host $line
}

function Test-JiraAiAutomationBusy {
    <#
      Returns whether automation is currently processing a Jira investigation.
      Used to skip the scheduled 5-minute assigned-Jira poll while busy.
    #>
    $result = [pscustomobject]@{
        IsBusy    = $false
        Reason    = ''
        Pid       = $null
        JiraKey   = $null
        StartedAt = $null
    }

    $lockPath = Get-JiraAiRunLockPath
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $ownerPid = 0
            if ($existing.pid) { $ownerPid = [int]$existing.pid }
            if ($existing.startedAt) { $result.StartedAt = [string]$existing.startedAt }
            if ($ownerPid -gt 0 -and $ownerPid -ne $PID) {
                $alive = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
                if ($alive) {
                    $result.IsBusy = $true
                    $result.Pid = $ownerPid
                    $result.JiraKey = [string]$existing.jiraKey
                    $result.Reason = ('run.lock held by pid={0} key={1}' -f $ownerPid, $existing.jiraKey)
                    return $result
                }
            }
        }
        catch { }
    }

    $busyProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -and
            ($_.CommandLine -match 'Invoke-JiraAssignPoller\.ps1' -or $_.CommandLine -match 'run-jira-ai-fix\.mjs')
        })
    if ($busyProcs.Count -gt 0) {
        $result.IsBusy = $true
        $result.Pid = [int]$busyProcs[0].ProcessId
        $result.Reason = ('live automation process pid={0}' -f $busyProcs[0].ProcessId)
        if ($busyProcs[0].CommandLine -match '(?i)(?:--jira|-IssueKey)\s+([A-Z][A-Z0-9]+-\d+)') {
            $result.JiraKey = $Matches[1].ToUpperInvariant()
        }
        return $result
    }

    try {
        $store = Get-ProcessedStore
        foreach ($key in @($store.Items.Keys)) {
            $item = $store.Items[$key]
            if (-not $item) { continue }
            if ([string]$item.lifecycle -ne 'in-progress') { continue }
            $ownerPid = 0
            if ($item.ownerPid) { $ownerPid = [int]$item.ownerPid }
            if ($ownerPid -gt 0 -and $ownerPid -ne $PID) {
                $alive = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
                if ($alive) {
                    $result.IsBusy = $true
                    $result.Pid = $ownerPid
                    $result.JiraKey = $key
                    $result.Reason = ('in-progress investigation {0} ownerPid={1}' -f $key, $ownerPid)
                    if ($item.startedAt) { $result.StartedAt = [string]$item.startedAt }
                    return $result
                }
            }
        }
    }
    catch { }

    return $result
}

function Test-JiraAiLockStale {
    <#
      True only when the lock is safe to reclaim without -Force:
      - owner PID is dead / missing, or
      - no live owner PID and lock/activity age exceeds lockStaleMinutes.

      A live owner PID is NEVER stale for auto-reclaim, even if current-agent.json
      stopped updating. Clearing the lock under a live process causes dual
      runners and ECONNRESET (seen on ST-13275). Use -Force to preempt a live run.
    #>
    param(
        $BusyInfo,
        [int]$StaleMinutes = 45
    )

    if (-not $BusyInfo -or -not $BusyInfo.IsBusy) { return $false }

    $ownerPid = 0
    if ($BusyInfo.Pid) { $ownerPid = [int]$BusyInfo.Pid }
    if ($ownerPid -gt 0) {
        $alive = Get-Process -Id $ownerPid -ErrorAction SilentlyContinue
        if ($alive) {
            # Live process owns the investigation — do not steal the lock.
            $cutoff = (Get-Date).AddMinutes(-1 * [Math]::Max(1, $StaleMinutes))
            $activityPath = Get-JiraAiCurrentAgentPath
            if (Test-Path -LiteralPath $activityPath) {
                try {
                    $activity = Get-Content -LiteralPath $activityPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($activity.updatedAt) {
                        $stamp = [datetime]::Parse([string]$activity.updatedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
                        if ($stamp -lt $cutoff) {
                            Write-JiraAiLog (
                                'Heartbeat stale for live pid={0} key={1} (updatedAt={2}); leaving lock (use -Force to preempt).' -f `
                                    $ownerPid, $BusyInfo.JiraKey, $activity.updatedAt
                            ) 'WARN'
                        }
                    }
                }
                catch { }
            }
            return $false
        }
        # Owner PID recorded but process is gone — orphaned lock.
        return $true
    }

    $cutoff = (Get-Date).AddMinutes(-1 * [Math]::Max(1, $StaleMinutes))
    $activityPath = Get-JiraAiCurrentAgentPath
    if (Test-Path -LiteralPath $activityPath) {
        try {
            $activity = Get-Content -LiteralPath $activityPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $stamp = $null
            if ($activity.updatedAt) {
                $stamp = [datetime]::Parse([string]$activity.updatedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            }
            if ($stamp -and $stamp -lt $cutoff) { return $true }
            if ($stamp -and $stamp -ge $cutoff) { return $false }
        }
        catch { }
    }

    if ($BusyInfo.StartedAt) {
        try {
            $started = [datetime]::Parse([string]$BusyInfo.StartedAt, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
            if ($started -lt $cutoff) { return $true }
            return $false
        }
        catch { }
    }

    # Busy with neither live PID nor parseable start — reclaim orphan.
    return $true
}

function Clear-JiraAiRunLockArtifacts {
    param([string]$Reason = '')
    $lockPath = Get-JiraAiRunLockPath
    $activityPath = Get-JiraAiCurrentAgentPath
    if (Test-Path -LiteralPath $lockPath) {
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $activityPath) {
        Remove-Item -LiteralPath $activityPath -Force -ErrorAction SilentlyContinue
    }
    if ($Reason) {
        Write-JiraAiLog ('Cleared run lock artifacts: {0}' -f $Reason) 'WARN'
    }
}

function Stop-JiraAiAutomationOwner {
    <#
      Best-effort stop of a busy poller/node tree so -Force can take the lock.
    #>
    param(
        [Parameter(Mandatory)][int]$OwnerPid,
        [string]$JiraKey = ''
    )

    if ($OwnerPid -le 0 -or $OwnerPid -eq $PID) { return }

    Write-JiraAiLog ('Force-stopping automation owner pid={0} key={1}' -f $OwnerPid, $JiraKey) 'WARN'

    $nodeProcs = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match 'run-jira-ai-fix\.mjs' -and
            (
                ($JiraKey -and $_.CommandLine -match [regex]::Escape($JiraKey)) -or
                (-not $JiraKey) -or
                ($_.ParentProcessId -eq $OwnerPid)
            )
        })
    foreach ($node in $nodeProcs) {
        try {
            Stop-Process -Id ([int]$node.ProcessId) -Force -ErrorAction SilentlyContinue
            Write-JiraAiLog ('Stopped node runner pid={0}' -f $node.ProcessId) 'WARN'
        }
        catch { }
    }

    try {
        Stop-Process -Id $OwnerPid -Force -ErrorAction SilentlyContinue
    }
    catch { }

    Start-Sleep -Seconds 2
}

function Enter-JiraAiRunLock {
    <#
      Ensures only one automation poller/investigation runs at a time.
      Returns $true when this process owns the lock.
      -Force (manual): stop a live owner and take the lock.
      Auto-reclaim only when the owner PID is dead / lock is orphaned.
      Never clear a lock under a live PID (use -Force instead).
    #>
    param(
        [switch]$Force,
        [int]$StaleMinutes = 45
    )

    $busy = Test-JiraAiAutomationBusy
    if ($busy.IsBusy) {
        $stale = Test-JiraAiLockStale -BusyInfo $busy -StaleMinutes $StaleMinutes
        if ($stale) {
            Write-JiraAiLog (
                'Reclaiming orphaned/dead-owner run lock ({0}; staleMinutes={1}).' -f $busy.Reason, $StaleMinutes
            ) 'WARN'
            Clear-JiraAiRunLockArtifacts -Reason $busy.Reason
        }
        elseif ($Force) {
            if ($busy.Pid) {
                Stop-JiraAiAutomationOwner -OwnerPid ([int]$busy.Pid) -JiraKey ([string]$busy.JiraKey)
            }
            Clear-JiraAiRunLockArtifacts -Reason ('forced preempt: {0}' -f $busy.Reason)
        }
        else {
            Write-JiraAiLog ('Another automation process is already running ({0}). Skipping this pass (one Jira at a time).' -f $busy.Reason)
            return $false
        }

        # Re-check after reclaim/force in case something else grabbed it.
        $busyAgain = Test-JiraAiAutomationBusy
        if ($busyAgain.IsBusy -and -not (Test-JiraAiLockStale -BusyInfo $busyAgain -StaleMinutes $StaleMinutes)) {
            if (-not $Force) {
                Write-JiraAiLog ('Lock still held after reclaim attempt ({0}). Skipping.' -f $busyAgain.Reason) 'WARN'
                return $false
            }
            if ($busyAgain.Pid) {
                Stop-JiraAiAutomationOwner -OwnerPid ([int]$busyAgain.Pid) -JiraKey ([string]$busyAgain.JiraKey)
            }
            Clear-JiraAiRunLockArtifacts -Reason ('forced preempt retry: {0}' -f $busyAgain.Reason)
        }
        elseif ($busyAgain.IsBusy) {
            Clear-JiraAiRunLockArtifacts -Reason $busyAgain.Reason
        }
    }

    $lockPath = Get-JiraAiRunLockPath
    $obj = [ordered]@{
        pid       = $PID
        startedAt = (Get-Date).ToString('o')
        jiraKey   = $null
    }
    ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $lockPath -Encoding UTF8
    Write-JiraAiLog ('Acquired run lock (pid={0}). Process log: {1}' -f $PID, (Get-JiraAiProcessLogPath))
    $true
}

function Update-JiraAiRunLock {
    param([string]$JiraKey)
    $lockPath = Get-JiraAiRunLockPath
    $startedAt = (Get-Date).ToString('o')
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing.startedAt) { $startedAt = [string]$existing.startedAt }
        }
        catch { }
    }
    $obj = [ordered]@{
        pid       = $PID
        startedAt = $startedAt
        jiraKey   = $JiraKey
    }
    ($obj | ConvertTo-Json -Compress) | Set-Content -LiteralPath $lockPath -Encoding UTF8
}

function Exit-JiraAiRunLock {
    $lockPath = Get-JiraAiRunLockPath
    if (-not (Test-Path -LiteralPath $lockPath)) { return }
    try {
        $existing = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($existing.pid -and [int]$existing.pid -ne $PID) { return }
    }
    catch { }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    Clear-JiraAiProcessLogContext
    Write-JiraAiLog ('Released run lock (pid={0}).' -f $PID)
}

function Get-JiraAiAutomationConfig {
    $path = Join-Path (Get-JiraAiAutomationRoot) 'config.json'
    $example = Join-Path (Get-JiraAiAutomationRoot) 'config.example.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if (Test-Path -LiteralPath $example) {
            Copy-Item -LiteralPath $example -Destination $path
            Write-JiraAiLog 'Created config.json from example. Edit mode/notify settings; Jira creds stay in .jira-ai-config.json.' 'WARN'
        }
        else {
            throw "Missing automation config: $path"
        }
    }
    Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-JiraAiUserConfig {
    $candidates = @(
        (Join-Path $env:USERPROFILE '.jira-ai-config.json'),
        (Join-Path $env:USERPROFILE '.jira-ai-fix-config.json')
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) {
            return [pscustomobject]@{
                Path = $p
                Cfg  = (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json)
            }
        }
    }
    throw 'Missing %USERPROFILE%\.jira-ai-config.json (atlassian credentials).'
}

function Get-AtlassianAuth {
    param($UserCfg)
    $a = $UserCfg.atlassian
    if (-not $a) { throw 'atlassian section missing from jira-ai-config.json' }

    $email = [string]$a.email
    $token = [string]$a.apiToken
    if (-not $token -and $a.tokenFile) {
        $tf = [string]$a.tokenFile
        if (Test-Path -LiteralPath $tf) { $token = (Get-Content -LiteralPath $tf -Raw).Trim() }
    }
    if (-not $email) { $email = [Environment]::GetEnvironmentVariable('ATLASSIAN_EMAIL') }
    if (-not $token) { $token = [Environment]::GetEnvironmentVariable('ATLASSIAN_API_TOKEN') }
    if (-not $email -or -not $token) { throw 'Atlassian email/apiToken missing.' }

    $site = [string]$a.siteUrl
    if (-not $site) { $site = 'https://irely.atlassian.net' }
    $site = $site.TrimEnd('/')

    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(('{0}:{1}' -f $email, $token)))
    [pscustomobject]@{
        SiteUrl = $site
        Headers = @{
            Authorization  = "Basic $b64"
            Accept         = 'application/json'
            'Content-Type' = 'application/json'
        }
    }
}

function Get-ProcessedStore {
    $path = Join-Path (Get-JiraAiAutomationRoot) 'processed.json'
    $map = @{}
    if (Test-Path -LiteralPath $path) {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $bag = $raw
        if ($raw.PSObject.Properties.Name -contains 'items') { $bag = $raw.items }
        foreach ($p in $bag.PSObject.Properties) {
            $map[$p.Name] = $p.Value
        }
    }
    [pscustomobject]@{ Path = $path; Items = $map }
}

function Save-ProcessedStore {
    param($Store)
    $items = [ordered]@{}
    foreach ($k in @($Store.Items.Keys | Sort-Object)) {
        $items[$k] = $Store.Items[$k]
    }
    $obj = [ordered]@{
        updatedAt = (Get-Date).ToString('o')
        items     = $items
    }
    ($obj | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $Store.Path -Encoding UTF8
}

function Find-NewlyAssignedJiras {
    param(
        $Auth,
        $AutomationConfig,
        [int]$LookbackMinutes = 15
    )

    $types = @($AutomationConfig.issueTypes)
    if ($types.Count -eq 0) {
        $types = @('Bug', 'Bug-QC', 'Bug-UAP', 'Bug-Ongoing UAP', 'Technical Debt', 'Performance', 'Data Fix')
    }
    $statuses = @($AutomationConfig.statuses)
    if ($statuses.Count -eq 0) { $statuses = @('Open', 'Reopened') }

    $typeList = ($types | ForEach-Object { '"{0}"' -f $_ }) -join ', '
    $statusList = ($statuses | ForEach-Object { '"{0}"' -f $_ }) -join ', '

    # Atlassian removed POST /rest/api/3/search (HTTP 410 / CHANGE-2046).
    # Use the enhanced search endpoint: POST /rest/api/3/search/jql
    $uri = '{0}/rest/api/3/search/jql' -f $Auth.SiteUrl
    $fields = @('summary', 'status', 'issuetype', 'assignee', 'updated', 'project')

    $invokeSearch = {
        param([string]$Jql)
        $bodyObj = @{ jql = $Jql; maxResults = 50; fields = $fields }
        Invoke-JsonRestMethod -Method Post -Uri $uri -Headers $Auth.Headers -BodyObject $bodyObj
    }

    # Single-quoted so PowerShell does not treat currentUser() as a subexpression.
    $jqlPrimary = 'assignee = currentUser() AND status in (' + $statusList + ') AND issuetype in (' + $typeList + ') AND assignee changed AFTER -' + $LookbackMinutes + 'm'
    try {
        $resp = & $invokeSearch $jqlPrimary
    }
    catch {
        Write-JiraAiLog ('JQL assignee-changed failed ({0}); falling back to updated lookback.' -f $_.Exception.Message) 'WARN'
        $jqlFallback = 'assignee = currentUser() AND status in (' + $statusList + ') AND issuetype in (' + $typeList + ') AND updated >= -' + $LookbackMinutes + 'm'
        try {
            $resp = & $invokeSearch $jqlFallback
        }
        catch {
            Write-JiraAiLog ('JQL updated-lookback also failed ({0}).' -f $_.Exception.Message) 'ERROR'
            throw
        }
    }

    $out = @()
    foreach ($issue in @($resp.issues)) {
        $out += [pscustomobject]@{
            Key     = [string]$issue.key
            Summary = [string]$issue.fields.summary
            Status  = [string]$issue.fields.status.name
            Type    = [string]$issue.fields.issuetype.name
            Project = [string]$issue.fields.project.key
            Updated = [string]$issue.fields.updated
        }
    }
    $out
}

function Resolve-RepoForIssue {
    param($Issue, $AutomationConfig)
    $proj = [string]$Issue.Project
    if ($AutomationConfig.repoByProject -and
        ($AutomationConfig.repoByProject.PSObject.Properties.Name -contains $proj)) {
        return $AutomationConfig.repoByProject.$proj
    }
    return $AutomationConfig.defaultRepo
}

function ConvertTo-PlainTextFromHtml {
    param([string]$Html)
    if ([string]::IsNullOrWhiteSpace($Html)) { return '' }
    $t = $Html
    $t = [regex]::Replace($t, '(?i)<br\s*/?>', "`n")
    $t = [regex]::Replace($t, '(?i)</p\s*>', "`n`n")
    $t = [regex]::Replace($t, '(?i)</li\s*>', "`n")
    $t = [regex]::Replace($t, '(?i)<li[^>]*>', '- ')
    $t = [regex]::Replace($t, '(?i)<[^>]+>', '')
    $t = [System.Net.WebUtility]::HtmlDecode($t)
    $t = [regex]::Replace($t, "[ \t]+\r?\n", "`n")
    $t = [regex]::Replace($t, "(\r?\n){3,}", "`n`n")
    $t.Trim()
}

function Get-JiraIssueBundle {
    param(
        [Parameter(Mandatory)]$Auth,
        [Parameter(Mandatory)][string]$JiraKey
    )
    $key = $JiraKey.ToUpperInvariant()
    $fields = @(
        'summary', 'description', 'status', 'issuetype', 'priority', 'assignee', 'reporter',
        'comment', 'attachment', 'created', 'updated', 'labels', 'components',
        'fixVersions', 'environment', 'customfield_10037', 'customfield_10038', 'customfield_10039'
    ) -join ','
    $uri = '{0}/rest/api/3/issue/{1}?fields={2}&expand=renderedFields' -f $Auth.SiteUrl, $key, $fields
    $issue = Invoke-RestMethod -Method Get -Uri $uri -Headers $Auth.Headers -TimeoutSec 60

    $descHtml = ''
    if ($issue.renderedFields -and $issue.renderedFields.description) {
        $descHtml = [string]$issue.renderedFields.description
    }
    $description = ConvertTo-PlainTextFromHtml -Html $descHtml
    if (-not $description -and $issue.fields.description) {
        $description = ($issue.fields.description | ConvertTo-Json -Depth 20 -Compress)
    }

    $comments = @()
    foreach ($c in @($issue.fields.comment.comments)) {
        $bodyText = ''
        if ($c.body) {
            $bodyText = ($c.body | ConvertTo-Json -Depth 20 -Compress)
        }
        $comments += [pscustomobject]@{
            Author  = if ($c.author) { [string]$c.author.displayName } else { '' }
            Created = [string]$c.created
            Body    = $bodyText
        }
    }

    $attachments = @()
    foreach ($a in @($issue.fields.attachment)) {
        $attachments += [pscustomobject]@{
            Filename = [string]$a.filename
            MimeType = [string]$a.mimeType
            Size     = [string]$a.size
            Content  = [string]$a.content
        }
    }

    $fixVersions = @()
    foreach ($fv in @($issue.fields.fixVersions)) {
        if ($fv.name) { $fixVersions += [string]$fv.name }
    }

    $reportedBuild = ''
    if ($null -ne $issue.fields.customfield_10037) {
        $reportedBuild = [string]$issue.fields.customfield_10037
    }
    $fixedInBuild = ''
    if ($null -ne $issue.fields.customfield_10039) {
        $fixedInBuild = [string]$issue.fields.customfield_10039
    }
    $customer = ''
    if ($null -ne $issue.fields.customfield_10038) {
        if ($issue.fields.customfield_10038.value) {
            $customer = [string]$issue.fields.customfield_10038.value
        }
        else {
            $customer = [string]$issue.fields.customfield_10038
        }
    }
    $environment = ''
    if ($null -ne $issue.fields.environment) {
        if ($issue.fields.environment -is [string]) {
            $environment = [string]$issue.fields.environment
        }
        else {
            $environment = ConvertTo-PlainTextFromHtml -Html ([string]($issue.renderedFields.environment))
            if (-not $environment) {
                $environment = ($issue.fields.environment | ConvertTo-Json -Depth 8 -Compress)
            }
        }
    }

    [pscustomobject]@{
        Key           = [string]$issue.key
        Summary       = [string]$issue.fields.summary
        Status        = [string]$issue.fields.status.name
        Type          = [string]$issue.fields.issuetype.name
        Priority      = if ($issue.fields.priority) { [string]$issue.fields.priority.name } else { '' }
        Assignee      = if ($issue.fields.assignee) { [string]$issue.fields.assignee.displayName } else { '' }
        Reporter      = if ($issue.fields.reporter) { [string]$issue.fields.reporter.displayName } else { '' }
        BrowseUrl     = '{0}/browse/{1}' -f $Auth.SiteUrl, $issue.key
        Description   = $description
        Comments      = $comments
        Attachments   = $attachments
        Created       = [string]$issue.fields.created
        Updated       = [string]$issue.fields.updated
        FixVersions   = $fixVersions
        ReportedBuild = $reportedBuild
        FixedInBuild  = $fixedInBuild
        Customer      = $customer
        Environment   = $environment
    }
}

function New-DesktopAnalyzePrompt {
    param([Parameter(Mandatory)][string]$JiraKey)
    @(
        "jira-ai-fix $JiraKey"
        ''
        'Mode: DRAFT_JIRA_COMMENT'
        ''
        'Jira comment voice (every comment / draft): short, direct, and professional.'
        '- Keep the required section 6 block register; compress prose inside each block.'
        '- Short sentences and tight bullets. No filler, hedging, or narration.'
        '- No casual tone, no emoji, no marketing language.'
    ) -join [Environment]::NewLine
}

function Resolve-JiraAiLocalCwd {
    param($AutomationConfig)
    if ($AutomationConfig -and $AutomationConfig.localCwd) {
        $c = [string]$AutomationConfig.localCwd
        if ($c -and (Test-Path -LiteralPath $c)) { return (Resolve-Path -LiteralPath $c).Path }
    }
    try {
        $user = Get-JiraAiUserConfig
        if ($user.Cfg.i21 -and $user.Cfg.i21.repoRoot) {
            $r = [string]$user.Cfg.i21.repoRoot
            if (Test-Path -LiteralPath $r) { return (Resolve-Path -LiteralPath $r).Path }
        }
    }
    catch { }
    if (Test-Path -LiteralPath 'C:\i21Source') { return 'C:\i21Source' }
    $null
}

function Resolve-JiraAiLocalRunnerDir {
    param($AutomationConfig)
    $candidates = @()
    if ($AutomationConfig -and $AutomationConfig.localRunnerDir) {
        $candidates += [string]$AutomationConfig.localRunnerDir
    }
    $candidates += @(
        (Join-Path (Get-JiraAiAutomationRoot) 'local-runner'),
        (Join-Path $PSScriptRoot 'local-runner')
    )
    foreach ($c in $candidates) {
        if (-not $c) { continue }
        $script = Join-Path $c 'run-jira-ai-fix.mjs'
        if (Test-Path -LiteralPath $script) { return (Resolve-Path -LiteralPath $c).Path }
    }
    $null
}

function Start-JiraAiLocalAgent {
    <#
      Launches the Node local runner (Cursor SDK) for jira-ai-fix on this machine.
      Returns a result object with Ok, DraftPath, Status, RawOutput.
    #>
    param(
        [Parameter(Mandatory)][string]$JiraKey,
        $AutomationConfig,
        [switch]$DryRun
    )

    $prompt = New-DesktopAnalyzePrompt -JiraKey $JiraKey
    if ($DryRun) {
        Write-JiraAiLog ('Dry-run local agent skipped for {0}' -f $JiraKey)
        return [pscustomobject]@{
            Ok         = $true
            DryRun     = $true
            Prompt     = $prompt
            DraftPath  = $null
            Status     = 'dry-run'
            ExitCode   = 0
            RawOutput  = ''
        }
    }

    $runnerDir = Resolve-JiraAiLocalRunnerDir -AutomationConfig $AutomationConfig
    if (-not $runnerDir) {
        throw 'local-runner not found. Run Install-ToUserProfile.ps1 (copies automation/local-runner).'
    }
    $script = Join-Path $runnerDir 'run-jira-ai-fix.mjs'
    $cwd = Resolve-JiraAiLocalCwd -AutomationConfig $AutomationConfig
    if (-not $cwd) {
        throw 'localCwd / i21.repoRoot missing. Set localCwd in automation config or i21.repoRoot in .jira-ai-config.json.'
    }

    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) { throw 'Node.js is required for local mode (node not on PATH).' }

    $investigateModel = 'grok-4.5'
    if ($AutomationConfig -and $AutomationConfig.investigateModel) {
        $investigateModel = [string]$AutomationConfig.investigateModel
    }
    elseif ($AutomationConfig -and $AutomationConfig.localModel) {
        # Backward compatible: localModel maps to the investigate phase.
        $investigateModel = [string]$AutomationConfig.localModel
    }

    $wrapUpModel = 'auto'
    if ($AutomationConfig -and $AutomationConfig.wrapUpModel) {
        $wrapUpModel = [string]$AutomationConfig.wrapUpModel
    }

    $sdkNodeModules = Join-Path $runnerDir 'node_modules\@cursor\sdk'
    if (-not (Test-Path -LiteralPath $sdkNodeModules)) {
        Write-JiraAiLog 'Installing @cursor/sdk in local-runner...'
        $npm = Get-Command npm -ErrorAction SilentlyContinue
        if (-not $npm) { throw 'npm not found; cannot install @cursor/sdk.' }
        Push-Location $runnerDir
        try {
            & npm install --omit=dev 2>&1 | Out-Null
        }
        finally { Pop-Location }
    }

    # Ensure this investigation has its own log file (even if caller forgot to set context).
    if ([string]::IsNullOrWhiteSpace($script:JiraAiActiveLogKey) -or
        $script:JiraAiActiveLogKey.Trim().ToUpperInvariant() -ne $JiraKey.Trim().ToUpperInvariant()) {
        [void](Set-JiraAiProcessLogContext -JiraKey $JiraKey)
    }

    $processLogPath = Get-JiraAiProcessLogPath -JiraKey $JiraKey
    Write-JiraAiLog ('Starting local jira-ai-fix for {0} (cwd={1}, investigate={2}, wrap-up={3})' -f $JiraKey, $cwd, $investigateModel, $wrapUpModel)
    Write-JiraAiLog ('Realtime process log: {0}' -f $processLogPath)

    $argList = @(
        ('"{0}"' -f $script),
        '--jira', $JiraKey,
        '--cwd', ('"{0}"' -f $cwd),
        '--investigate-model', $investigateModel,
        '--wrap-up-model', $wrapUpModel
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $node.Source
    $psi.Arguments = ($argList -join ' ')
    $psi.WorkingDirectory = $runnerDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $apiKey = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'Process')
    if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'User') }
    if (-not $apiKey) { $apiKey = [Environment]::GetEnvironmentVariable('CURSOR_API_KEY', 'Machine') }
    if ($AutomationConfig -and $AutomationConfig.cursorApiKey) {
        $cfgKey = [string]$AutomationConfig.cursorApiKey
        if ($cfgKey -and -not $apiKey) { $apiKey = $cfgKey.Trim() }
    }
    if ($apiKey) {
        $psi.EnvironmentVariables['CURSOR_API_KEY'] = $apiKey
    }
    $psi.EnvironmentVariables['JIRA_AI_PROCESS_LOG'] = $processLogPath

    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true
    $outData = [pscustomobject]@{ Builder = $stdoutBuilder; LogPath = $processLogPath; Prefix = '[runner]' }
    $errData = [pscustomobject]@{ Builder = $stderrBuilder; LogPath = $processLogPath; Prefix = '[runner:err]' }
    $streamAction = {
        if ([string]::IsNullOrEmpty($EventArgs.Data)) { return }
        try {
            [void]$Event.MessageData.Builder.AppendLine($EventArgs.Data)
            $raw = [string]$EventArgs.Data
            # Runner already writes activity lines into the process log — don't duplicate.
            if ($raw -match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \[INFO\]') { return }
            if ($raw -match '\[local-runner\]') { return }
            # Drop Cursor SDK internal noise (cache rebuild, rules load, parser warnings).
            if ($raw -match '(?i)computeGlobalCache|MaxListenersExceededWarning|setMaxListeners|tree-sitter|shell-parser|CursorPluginsAgentSkillsService|AgentSkillsCursorRulesService|LocalCursorRulesService|trace-warnings') { return }
            # Keep JSON in the stdout builder for the poller parser, but do not dump raw
            # outcome JSON into the process log (runner writes human-readable lines instead).
            if ($raw.TrimStart().StartsWith('{')) { return }
            # Keep only useful high-level process / outcome lines from stdout/stderr.
            if ($raw -notmatch '(?i)^process:|FAILURE|^\[[A-Z][A-Z0-9]+-\d+\]') { return }
            $line = '{0:yyyy-MM-dd HH:mm:ss} [INFO] {1} {2}' -f (Get-Date), $Event.MessageData.Prefix, $raw
            Add-Content -LiteralPath $Event.MessageData.LogPath -Value $line -Encoding UTF8
        }
        catch { }
    }

    $outSub = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $streamAction -MessageData $outData
    $errSub = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $streamAction -MessageData $errData
    $successSeenAt = $null
    $postSuccessGraceSec = 45
    try {
        [void]$proc.Start()
        $proc.BeginOutputReadLine()
        $proc.BeginErrorReadLine()
        while (-not $proc.HasExited) {
            Start-Sleep -Milliseconds 250
            # Cursor SDK sometimes keeps node alive after the runner already printed success.
            if (-not $successSeenAt) {
                $soFar = $stdoutBuilder.ToString()
                if ($soFar -match '"ok"\s*:\s*true') {
                    $successSeenAt = Get-Date
                    Write-JiraAiLog ('Local runner finished {0} successfully; allowing {1}s for clean exit...' -f $JiraKey, $postSuccessGraceSec)
                }
            }
            elseif (((Get-Date) - $successSeenAt).TotalSeconds -ge $postSuccessGraceSec) {
                Write-JiraAiLog 'Local runner hung after success; terminating node so email/lock can complete.' 'WARN'
                try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
                break
            }
        }
        Start-Sleep -Milliseconds 500
    }
    finally {
        Unregister-Event -SourceIdentifier $outSub.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $errSub.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $outSub.Id -Force -ErrorAction SilentlyContinue
        Remove-Job -Id $errSub.Id -Force -ErrorAction SilentlyContinue
    }

    $code = $proc.ExitCode
    $stdout = $stdoutBuilder.ToString()
    $stderr = $stderrBuilder.ToString()

    $summary = $null
    foreach ($line in ($stdout -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith('{') -and $t.EndsWith('}')) {
            try { $summary = $t | ConvertFrom-Json; break } catch { }
        }
    }

    $draftPath = $null
    if ($summary -and $summary.draftPath) { $draftPath = [string]$summary.draftPath }
    elseif (Test-Path -LiteralPath (Join-Path (Get-JiraAiDraftsRoot) ('{0}-rca.md' -f $JiraKey))) {
        $draftPath = Join-Path (Get-JiraAiDraftsRoot) ('{0}-rca.md' -f $JiraKey)
    }

    # Prefer runner summary over raw exit code — forced kill after hang is -1 on Windows.
    $summaryOk = $false
    if ($summary) {
        if ($summary.PSObject.Properties.Name -contains 'ok' -and [bool]$summary.ok) {
            $summaryOk = $true
        }
        elseif ([string]$summary.status -eq 'finished' -and $draftPath -and (Test-Path -LiteralPath $draftPath)) {
            $summaryOk = $true
        }
    }
    $ok = ($code -eq 0) -or $summaryOk
    if ($summaryOk -and $code -ne 0) {
        Write-JiraAiLog ('Treating local run as OK despite exit={0} (runner reported success / draft present).' -f $code) 'WARN'
    }

    [pscustomobject]@{
        Ok           = $ok
        DryRun       = $false
        Prompt       = $prompt
        DraftPath    = $draftPath
        FailurePath  = (Get-JiraAiProcessLogPath)
        FailurePhase = if ($summary -and $summary.phase) { [string]$summary.phase } else { $null }
        FailureWhy   = if ($summary -and $summary.why) { [string]$summary.why } else { $null }
        RootCause    = if ($summary -and $summary.rootCause) { [string]$summary.rootCause } else { $null }
        Status       = if ($summary) { [string]$summary.status } else { "exit=$code" }
        ExitCode     = $code
        RunId        = if ($summary) { [string]$summary.runId } else { $null }
        RawOutput    = $stdout
        StdErr       = $stderr
        Cwd          = $cwd
    }
}

function Save-JiraAssignNotify {
    param(
        [Parameter(Mandatory)][string]$JiraKey,
        [string]$Summary,
        [string]$BrowseUrl,
        [Parameter(Mandatory)][string]$PromptText,
        $Repo,
        [switch]$DryRun
    )
    $dir = Get-JiraAiDraftsRoot
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $mdPath = Join-Path $dir ('{0}-notify.md' -f $JiraKey)
    $metaPath = Join-Path $dir ('{0}-meta.json' -f $JiraKey)

    $lines = @(
        "# Jira assign notify - $JiraKey"
        ''
        ('**Summary:** {0}' -f $Summary)
        ('**Browse:** {0}' -f $BrowseUrl)
        ''
        '## Paste this in Cursor Desktop (loads real jira-ai-fix skill)'
        ''
        '```'
        $PromptText
        '```'
    )
    if ($Repo -and $Repo.url) {
        $lines += @(
            ''
            '## Suggested repo / branch'
            ''
            ('- URL: `{0}`' -f [string]$Repo.url)
            ('- startingRef: `{0}`' -f [string]$Repo.startingRef)
        )
    }
    if ($DryRun) {
        $lines += @('', '_Dry-run: notify only._')
    }

    $body = $lines -join [Environment]::NewLine
    Set-Content -LiteralPath $mdPath -Value $body -Encoding UTF8

    $meta = [ordered]@{
        jiraKey     = $JiraKey
        mode        = 'notify'
        dryRun      = [bool]$DryRun
        summary     = $Summary
        browseUrl   = $BrowseUrl
        prompt      = $PromptText
        finishedAt  = (Get-Date).ToString('o')
        repoUrl     = if ($Repo) { [string]$Repo.url } else { $null }
        startingRef = if ($Repo) { [string]$Repo.startingRef } else { $null }
    }
    ($meta | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $metaPath -Encoding UTF8

    [pscustomobject]@{
        MarkdownPath = $mdPath
        MetaPath     = $metaPath
    }
}

function Set-JiraAiClipboard {
    param([Parameter(Mandatory)][string]$Text)
    try {
        Set-Clipboard -Value $Text -ErrorAction Stop
        Write-JiraAiLog 'Prompt copied to clipboard.'
    }
    catch {
        Write-JiraAiLog ('Clipboard skipped: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Get-HttpErrorBody {
    param($ErrorRecord)
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        return [string]$ErrorRecord.ErrorDetails.Message
    }
    try {
        $resp = $ErrorRecord.Exception.Response
        if (-not $resp) { return $null }
        $stream = $resp.GetResponseStream()
        if (-not $stream) { return $null }
        $reader = New-Object System.IO.StreamReader($stream)
        return $reader.ReadToEnd()
    }
    catch { return $null }
}

function Invoke-JsonRestMethod {
    <#
      PowerShell 5.1 Invoke-RestMethod encodes a [string] -Body using the system
      ANSI code page, which corrupts UTF-8 JSON (em dashes, etc.) and makes
      Avoids PowerShell 5.1 ANSI corruption of UTF-8 JSON bodies.
      Always send UTF-8 bytes.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)]$Headers,
        $BodyObject,
        [string]$JsonBody
    )
    $bodyBytes = $null
    if ($PSBoundParameters.ContainsKey('JsonBody') -and $null -ne $JsonBody) {
        $bodyBytes = [Text.Encoding]::UTF8.GetBytes([string]$JsonBody)
    }
    elseif ($PSBoundParameters.ContainsKey('BodyObject')) {
        $json = $BodyObject | ConvertTo-Json -Depth 20 -Compress
        $bodyBytes = [Text.Encoding]::UTF8.GetBytes($json)
    }

    if ($null -eq $bodyBytes) {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 60
    }
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -Body $bodyBytes -ContentType 'application/json; charset=utf-8' -TimeoutSec 60
}

function Extract-JiraRcaDraft {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $m = [regex]::Match($Text, '(?s)```jira-rca-draft\s*\r?\n(.*?)\r?\n```')
    if ($m.Success) { return $m.Groups[1].Value.TrimEnd() }
    $null
}

function Save-JiraRcaDraft {
    param(
        [Parameter(Mandatory)][string]$JiraKey,
        [Parameter(Mandatory)][string]$Body,
        $Meta
    )
    $dir = Get-JiraAiDraftsRoot
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $mdPath = Join-Path $dir ('{0}-rca.md' -f $JiraKey)
    $metaPath = Join-Path $dir ('{0}-meta.json' -f $JiraKey)
    Set-Content -LiteralPath $mdPath -Value $Body -Encoding UTF8
    if ($null -eq $Meta) { $Meta = [ordered]@{ jiraKey = $JiraKey } }
    ($Meta | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $metaPath -Encoding UTF8
    [pscustomobject]@{
        MarkdownPath = $mdPath
        MetaPath     = $metaPath
    }
}

function Remove-JiraAiRcaDraft {
    <#
      Deletes local RCA artifacts for a Jira key so a failed/incomplete run
      cannot be mistaken for a completed investigation.
      Keeps failure diagnostics under logs\failures.
    #>
    param(
        [Parameter(Mandatory)][string]$JiraKey
    )

    $key = $JiraKey.ToUpperInvariant()
    $dir = Get-JiraAiDraftsRoot
    $removed = New-Object System.Collections.Generic.List[string]
    foreach ($name in @(
            ('{0}-rca.md' -f $key),
            ('{0}-meta.json' -f $key),
            ('{0}-notify.md' -f $key)
        )) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            $removed.Add($path) | Out-Null
        }
    }

    if ($removed.Count -gt 0) {
        Write-JiraAiLog ('Removed RCA draft artifacts for {0}: {1}' -f $key, ($removed -join ', '))
    }
    else {
        Write-JiraAiLog ('No RCA draft artifacts to remove for {0}.' -f $key)
    }

    [pscustomobject]@{
        JiraKey      = $key
        RemovedPaths = @($removed)
    }
}

function Write-JiraAiFailureReport {
    <#
      Logs failure details into the dated realtime process log and annotates/creates
      the RCA draft so the poller will not keep reinvestigating forever.
    #>
    param(
        [Parameter(Mandatory)][string]$JiraKey,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Why,
        [Parameter(Mandatory)][string]$RootCause,
        [string]$ProcessName = 'automation poller / local jira-ai-fix',
        [string]$Details = '',
        [object]$ExitCode = $null,
        [string]$Status = '',
        [string]$Cwd = '',
        [string]$RunId = ''
    )

    $key = $JiraKey.ToUpperInvariant()
    $processLog = Get-JiraAiProcessLogPath
    Write-JiraAiLog ('FAILURE jira={0} process={1}' -f $key, $ProcessName) 'ERROR'
    Write-JiraAiLog ('FAILURE failed-part={0}' -f $Phase) 'ERROR'
    Write-JiraAiLog ('FAILURE why={0}' -f $Why) 'ERROR'
    Write-JiraAiLog ('FAILURE root-cause={0}' -f $RootCause) 'ERROR'
    Write-JiraAiLog ('FAILURE status={0} exit={1} cwd={2} runId={3}' -f $Status, $ExitCode, $Cwd, $RunId) 'ERROR'
    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        foreach ($detailLine in ($Details -split "`r?`n")) {
            if ($detailLine) { Write-JiraAiLog ('FAILURE detail: {0}' -f $detailLine) 'ERROR' }
        }
    }

    Save-JiraAiFailureNoteInDraft `
        -JiraKey $key `
        -Phase $Phase `
        -Why $Why `
        -RootCause $RootCause `
        -FailureLogPath $processLog `
        -ProcessName $ProcessName `
        -ExitCode $ExitCode `
        -Status $Status | Out-Null

    return $processLog
}

function Save-JiraAiFailureNoteInDraft {
    <#
      Keeps any existing RCA draft and appends (or creates) a failure note so
      draft-based skip prevents endless retries after a failed investigation.
    #>
    param(
        [Parameter(Mandatory)][string]$JiraKey,
        [Parameter(Mandatory)][string]$Phase,
        [Parameter(Mandatory)][string]$Why,
        [Parameter(Mandatory)][string]$RootCause,
        [string]$FailureLogPath = '',
        [string]$ProcessName = '',
        [object]$ExitCode = $null,
        [string]$Status = ''
    )

    $key = $JiraKey.ToUpperInvariant()
    $drafts = Get-JiraAiDraftsRoot
    if (-not (Test-Path -LiteralPath $drafts)) {
        New-Item -ItemType Directory -Force -Path $drafts | Out-Null
    }
    $mdPath = Join-Path $drafts ('{0}-rca.md' -f $key)
    $metaPath = Join-Path $drafts ('{0}-meta.json' -f $key)
    $stamp = (Get-Date).ToString('o')
    if ([string]::IsNullOrWhiteSpace($FailureLogPath)) {
        $FailureLogPath = Get-JiraAiProcessLogPath
    }

    $note = @(
        ''
        '---'
        ''
        '## Automation failure'
        ''
        ('- Time: {0}' -f $stamp)
        ('- Process: {0}' -f $ProcessName)
        ('- Failed part: {0}' -f $Phase)
        ('- Why it failed: {0}' -f $Why)
        ('- Root cause: {0}' -f $RootCause)
        ('- Status: {0}' -f $Status)
        ('- Exit code: {0}' -f $ExitCode)
        ('- Process log: {0}' -f $FailureLogPath)
        ''
        'Automation will not reinvestigate this Jira while this RCA draft exists.'
        'Delete this draft only when a fresh investigation is intentional.'
        ''
    ) -join [Environment]::NewLine

    if (Test-Path -LiteralPath $mdPath) {
        $existing = Get-Content -LiteralPath $mdPath -Raw -Encoding UTF8
        if ($existing -notmatch '(?m)^## Automation failure\s*$') {
            Set-Content -LiteralPath $mdPath -Value ($existing.TrimEnd() + [Environment]::NewLine + $note) -Encoding UTF8
        }
        else {
            $updated = [regex]::Replace(
                $existing,
                '(?ms)^---\s*^## Automation failure.*',
                $note.TrimStart()
            )
            Set-Content -LiteralPath $mdPath -Value $updated.TrimEnd() -Encoding UTF8
        }
        Write-JiraAiLog ('Appended failure note to existing RCA draft: {0}' -f $mdPath)
    }
    else {
        $body = @(
            ('# Investigation incomplete: {0}' -f $key)
            ''
            'No completed RCA was produced. The automation failure details are below.'
            $note
        ) -join [Environment]::NewLine
        Set-Content -LiteralPath $mdPath -Value $body -Encoding UTF8
        Write-JiraAiLog ('Created failure RCA draft marker: {0}' -f $mdPath)
    }

    $meta = [ordered]@{
        jiraKey           = $key
        mode              = 'local'
        investigation     = 'failed'
        finishedAt        = $stamp
        failurePhase      = $Phase
        failureWhy        = $Why
        failureRootCause  = $RootCause
        processLogPath    = $FailureLogPath
        jiraCommentPosted = $false
    }
    ($meta | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $metaPath -Encoding UTF8
    return $mdPath
}

function Show-JiraAiToast {
    param(
        [string]$Title = 'Jira AI automation',
        [string]$Message
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Information
        $notify.Visible = $true
        $notify.BalloonTipTitle = $Title
        $notify.BalloonTipText = $Message
        $notify.ShowBalloonTip(10000)
        Start-Sleep -Seconds 1
        $notify.Dispose()
    }
    catch {
        Write-JiraAiLog ('Toast skipped: {0}' -f $_.Exception.Message) 'WARN'
    }
}

function Get-JiraAiEmailRecipient {
    param($AutomationConfig)
    if ($AutomationConfig -and $AutomationConfig.emailTo) {
        $to = [string]$AutomationConfig.emailTo
        if (-not [string]::IsNullOrWhiteSpace($to)) { return $to.Trim() }
    }
    try {
        $userBundle = Get-JiraAiUserConfig
        if ($userBundle.Cfg.atlassian -and $userBundle.Cfg.atlassian.email) {
            return [string]$userBundle.Cfg.atlassian.email
        }
    }
    catch { }
    $envEmail = [Environment]::GetEnvironmentVariable('ATLASSIAN_EMAIL')
    if ($envEmail) { return $envEmail }
    $null
}

function Get-JiraAiDraftInventory {
    param(
        [string[]]$FeaturedKeys = @(),
        [string[]]$ExcludeKeyRegexes = @('(?i)^ST-SMOKE', '(?i)^ST-99999$')
    )

    $dir = Get-JiraAiDraftsRoot
    if (-not (Test-Path -LiteralPath $dir)) { return @() }

    $featuredSet = @{}
    foreach ($k in @($FeaturedKeys)) {
        if ($k) { $featuredSet[$k.ToUpperInvariant()] = $true }
    }

    $items = @()
    foreach ($md in @(Get-ChildItem -LiteralPath $dir -Filter '*-rca.md' -File -ErrorAction SilentlyContinue)) {
        $key = $md.BaseName -replace '-rca$', ''
        $skip = $false
        foreach ($rx in @($ExcludeKeyRegexes)) {
            if ($rx -and $key -match $rx) { $skip = $true; break }
        }
        if ($skip) { continue }

        $body = Get-Content -LiteralPath $md.FullName -Raw -Encoding UTF8
        $meta = $null
        $metaPath = Join-Path $dir ('{0}-meta.json' -f $key)
        if (Test-Path -LiteralPath $metaPath) {
            try { $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }

        $summary = ''
        if ($meta -and $meta.summary) { $summary = [string]$meta.summary }
        $agentUrl = ''
        if ($meta -and $meta.agentUrl) { $agentUrl = [string]$meta.agentUrl }
        $isPlaceholder = ($body -match '(?i)DRY-RUN placeholder|waiting for completion|did not wait for completion')

        $items += [pscustomobject]@{
            Key           = $key
            Summary       = $summary
            Body          = $body
            Path          = $md.FullName
            AgentUrl      = $agentUrl
            FinishedAt    = if ($meta -and $meta.finishedAt) { [string]$meta.finishedAt } else { $md.LastWriteTime.ToString('o') }
            Featured      = [bool]$featuredSet[$key.ToUpperInvariant()]
            IsPlaceholder = [bool]$isPlaceholder
            LastWriteTime = $md.LastWriteTime
        }
    }

    $items | Sort-Object @{ Expression = 'Featured'; Descending = $true }, @{ Expression = 'LastWriteTime'; Descending = $true }
}

function Remove-JiraAiOutboxEmlIfSent {
    param(
        [string]$EmlPath,
        [string]$Delivery
    )
    if ($Delivery -ne 'send') { return }
    if ([string]::IsNullOrWhiteSpace($EmlPath)) { return }
    if (-not (Test-Path -LiteralPath $EmlPath)) { return }
    try {
        Remove-Item -LiteralPath $EmlPath -Force
        Write-JiraAiLog ('Deleted outbox .eml after successful send: {0}' -f $EmlPath)
    }
    catch {
        Write-JiraAiLog ('Could not delete outbox .eml {0}: {1}' -f $EmlPath, $_.Exception.Message) 'WARN'
    }
}

function ConvertTo-JiraAiHtmlEncoded {
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    [System.Net.WebUtility]::HtmlEncode($Text) -replace "`r`n", '<br/>' -replace "`n", '<br/>' -replace '`', '&#96;'
}

function Send-JiraAiLifecycleEmail {
    <#
      Sends one status email for a local investigation lifecycle event.
      Phase is started, resumed, or failed. Completed runs continue through
      Send-JiraAiDraftsEmail so the completed message includes the RCA body.

      For failed emails, pass FailedPart / Why / RootCause so the message
      clearly names which process step failed and why.
    #>
    param(
        $AutomationConfig,
        [Parameter(Mandatory)][string]$JiraKey,
        [Parameter(Mandatory)][ValidateSet('started', 'resumed', 'failed')][string]$Phase,
        [string]$Summary,
        [string]$JiraStatus,
        [string]$BrowseUrl,
        [string]$Details,
        [string]$FailedPart,
        [string]$Why,
        [string]$RootCause
    )

    if (-not $AutomationConfig -or $AutomationConfig.notifyEmail -eq $false) {
        Write-JiraAiLog ('Lifecycle email skipped for {0}: notifyEmail disabled.' -f $JiraKey)
        return $null
    }

    foreach ($rx in @($AutomationConfig.emailExcludeKeyRegexes)) {
        if ($rx -and $JiraKey -match $rx) {
            Write-JiraAiLog ('Lifecycle email skipped for excluded key {0}.' -f $JiraKey)
            return $null
        }
    }

    $to = Get-JiraAiEmailRecipient -AutomationConfig $AutomationConfig
    if (-not $to) {
        Write-JiraAiLog ('Lifecycle email skipped for {0}: no recipient configured.' -f $JiraKey) 'WARN'
        return $null
    }

    $failedPartLabel = $null
    if ($Phase -eq 'failed') {
        $rawPart = if ($FailedPart) { $FailedPart.Trim() } else { '' }
        $failedPartLabel = switch -Regex ($rawPart) {
            '(?i)preflight-auth|auth-missing|api.?key' { 'Preflight — API key / auth' }
            '(?i)preflight-cwd|cwd-missing|repo.?root' { 'Preflight — repo path / cwd' }
            '(?i)local-agent-startup|agent-startup|startup|network.?request' { 'Local agent startup' }
            '(?i)local-agent-execution|local-agent-execution|execution' { 'Local agent investigation' }
            '(?i)checking.?jira|^jira$' { 'Checking Jira ticket' }
            '(?i)hdtn|helpdesk' { 'Checking HDTN ticket' }
            '(?i)attachment' { 'Checking attachments' }
            '(?i)coding|implement|fix' { 'Coding / implementing fix' }
            '(?i)draft|rca' { 'Creating draft comment' }
            '(?i)email|outlook' { 'Sending email' }
            '(?i)poller-exception|poller' { 'Automation poller' }
            default {
                if ($rawPart) { $rawPart } else { 'Unknown process step' }
            }
        }
    }

    $phaseLabel = switch ($Phase) {
        'started' { 'Investigation started' }
        'resumed' { 'Investigation resumed' }
        'failed'  {
            if ($failedPartLabel) { 'Investigation failed — {0}' -f $failedPartLabel }
            else { 'Investigation failed' }
        }
    }
    $statusLabel = if ([string]::IsNullOrWhiteSpace($JiraStatus)) { 'Unknown' } else { $JiraStatus.Trim() }
    $subject = if ($Phase -eq 'failed') {
        if ($failedPartLabel) {
            '[{0}] Failed at {1}' -f $JiraKey, $failedPartLabel
        } else {
            '[{0}] Investigation failed' -f $JiraKey
        }
    } else {
        '[{0}] {1} - {2}' -f $JiraKey, $phaseLabel, $statusLabel
    }

    $safeKey = ConvertTo-JiraAiHtmlEncoded $JiraKey
    $safeSummary = ConvertTo-JiraAiHtmlEncoded $Summary
    $safeStatus = ConvertTo-JiraAiHtmlEncoded $statusLabel
    $safeDetails = ConvertTo-JiraAiHtmlEncoded $Details
    $safeUrl = ConvertTo-JiraAiHtmlEncoded $BrowseUrl
    $safeFailedPart = ConvertTo-JiraAiHtmlEncoded $failedPartLabel
    $safeWhy = ConvertTo-JiraAiHtmlEncoded $Why
    $safeRoot = ConvertTo-JiraAiHtmlEncoded $RootCause
    $actionText = switch ($Phase) {
        'started' { 'The Jira assignment was detected and the local Cursor investigation is now running.' }
        'resumed' { 'An interrupted local investigation was detected and has been restarted.' }
        'failed'  { 'The local Cursor investigation stopped before producing a completed draft.' }
    }

    $htmlParts = New-Object System.Collections.Generic.List[string]
    $htmlParts.Add('<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#222">') | Out-Null
    $htmlParts.Add(('<h2 style="margin-bottom:4px">{0}: {1}</h2>' -f $safeKey, (ConvertTo-JiraAiHtmlEncoded $phaseLabel))) | Out-Null
    if ($safeSummary) { $htmlParts.Add(('<p style="margin-top:0;color:#555">{0}</p>' -f $safeSummary)) | Out-Null }
    $htmlParts.Add(('<p><b>Jira status:</b> {0}<br/><b>Automation status:</b> {1}<br/><b>Time:</b> {2}</p>' -f
            $safeStatus,
            (ConvertTo-JiraAiHtmlEncoded $phaseLabel),
            (ConvertTo-JiraAiHtmlEncoded $((Get-Date).ToString('o'))))) | Out-Null
    $htmlParts.Add(('<p>{0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $actionText))) | Out-Null

    if ($Phase -eq 'failed') {
        $htmlParts.Add('<div style="background:#fff5f5;border:1px solid #f1c0c0;padding:12px;border-radius:4px;margin:12px 0">') | Out-Null
        $htmlParts.Add('<h3 style="margin:0 0 8px 0;color:#a11">Failure details</h3>') | Out-Null
        if ($safeFailedPart) {
            $htmlParts.Add(('<p style="margin:4px 0"><b>Failed process step:</b> {0}</p>' -f $safeFailedPart)) | Out-Null
        }
        if ($safeWhy) {
            $htmlParts.Add(('<p style="margin:4px 0"><b>Why it failed:</b> {0}</p>' -f $safeWhy)) | Out-Null
        }
        if ($safeRoot) {
            $htmlParts.Add(('<p style="margin:4px 0"><b>Root cause:</b> {0}</p>' -f $safeRoot)) | Out-Null
        }
        if (-not $safeFailedPart -and -not $safeWhy -and -not $safeRoot -and $safeDetails) {
            $htmlParts.Add('<p style="margin:4px 0"><b>Details:</b></p>') | Out-Null
        }
        $htmlParts.Add('</div>') | Out-Null
    }

    if ($safeDetails) {
        $htmlParts.Add(('<pre style="white-space:pre-wrap;background:#f7f7f7;border:1px solid #ddd;padding:12px;border-radius:4px">{0}</pre>' -f $safeDetails)) | Out-Null
    }
    if ($safeUrl) { $htmlParts.Add(('<p><a href="{0}">Open {1} in Jira</a></p>' -f $safeUrl, $safeKey)) | Out-Null }
    $htmlParts.Add('</body></html>') | Out-Null
    $html = $htmlParts -join [Environment]::NewLine

    $outbox = Join-Path (Get-JiraAiDraftsRoot) 'outbox'
    if (-not (Test-Path -LiteralPath $outbox)) {
        New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $emlPath = Join-Path $outbox ('{0}-{1}-{2}.eml' -f $stamp, $JiraKey, $Phase)
    $eml = @(
        ('To: {0}' -f $to)
        ('Subject: {0}' -f $subject)
        'X-Unsent: 1'
        'MIME-Version: 1.0'
        'Content-Type: text/html; charset=utf-8'
        'Content-Transfer-Encoding: 8bit'
        ''
        $html
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($emlPath, $eml, [System.Text.UTF8Encoding]::new($false))

    Write-JiraAiLog ('process: sending email ({0}) for {1}' -f $Phase, $JiraKey)

    $delivery = 'send'
    if ($AutomationConfig.emailDelivery) {
        $delivery = ([string]$AutomationConfig.emailDelivery).Trim().ToLowerInvariant()
    }
    if ($delivery -notin @('send', 'draft', 'display', 'eml')) { $delivery = 'send' }

    $sentOrSaved = 'eml'
    $openEml = ($delivery -in @('eml', 'display')) -or ($AutomationConfig.emailOpenClient -eq $true)
    if ($delivery -in @('send', 'draft')) {
        $job = Start-Job -ScriptBlock {
            param($To, $Subject, $HtmlBody, $Mode)
            $outlook = New-Object -ComObject Outlook.Application
            $mail = $outlook.CreateItem(0)
            $mail.To = $To
            $mail.Subject = $Subject
            $mail.BodyFormat = 2
            $mail.HTMLBody = $HtmlBody
            if ($Mode -eq 'draft') {
                $mail.Save()
                'draft'
            }
            else {
                $mail.Send()
                'send'
            }
        } -ArgumentList $to, $subject, $html, $delivery

        $completed = Wait-Job -Job $job -Timeout 20
        if ($completed -and $job.State -eq 'Completed') {
            $sentOrSaved = [string](Receive-Job -Job $job)
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        else {
            Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-JiraAiLog ('Lifecycle email Outlook delivery failed for {0}; leaving .eml in outbox.' -f $JiraKey) 'WARN'
            $sentOrSaved = 'eml-fallback'
            $openEml = $true
        }
    }

    if ($openEml -and (Test-Path -LiteralPath $emlPath)) {
        try { Start-Process -FilePath $emlPath | Out-Null }
        catch { Write-JiraAiLog ('Could not open lifecycle .eml: {0}' -f $_.Exception.Message) 'WARN' }
    }

    Remove-JiraAiOutboxEmlIfSent -EmlPath $emlPath -Delivery $sentOrSaved

    if ($sentOrSaved -eq 'send') {
        Write-JiraAiLog ('process: Done sending email ({0}) for {1}' -f $Phase, $JiraKey)
    }
    elseif ($sentOrSaved -eq 'draft') {
        Write-JiraAiLog ('process: Done creating email draft ({0}) for {1}' -f $Phase, $JiraKey)
    }
    else {
        Write-JiraAiLog ('process: Failed sending email ({0}) for {1} — left .eml in outbox' -f $Phase, $JiraKey) 'WARN'
    }

    Write-JiraAiLog ('Lifecycle email {0} for {1}: {2} ({3}).' -f $sentOrSaved, $JiraKey, $Phase, $(if ($sentOrSaved -eq 'send') { 'eml deleted' } else { $emlPath }))
    [pscustomobject]@{
        To       = $to
        Subject  = $subject
        Delivery = $sentOrSaved
        EmlPath  = if ($sentOrSaved -eq 'send') { $null } else { $emlPath }
        Phase    = $Phase
    }
}

function Send-JiraAiDraftsEmail {
    <#
      Emails the RCA draft for the Jira(s) that just finished investigation.
      Only FeaturedKeys are included (not prior drafts), and the RCA body is
      formatted for easy copy/paste into Jira.
    #>
    param(
        $AutomationConfig,
        [string[]]$FeaturedKeys = @(),
        [switch]$Force
    )

    if (-not $Force) {
        if (-not $AutomationConfig -or $AutomationConfig.notifyEmail -eq $false) {
            Write-JiraAiLog 'Draft email skipped (notifyEmail false/absent).'
            return $null
        }
    }

    $to = Get-JiraAiEmailRecipient -AutomationConfig $AutomationConfig
    if (-not $to) {
        Write-JiraAiLog 'Draft email skipped: no emailTo / Atlassian email configured.' 'WARN'
        return $null
    }

    $featuredKeys = @($FeaturedKeys | Where-Object { $_ } | ForEach-Object { $_.ToString().Trim().ToUpperInvariant() } | Select-Object -Unique)
    if ($featuredKeys.Count -eq 0) {
        Write-JiraAiLog 'Draft email skipped: no featured (just-finished) Jira key provided.' 'WARN'
        return $null
    }

    $exclude = @('(?i)^ST-SMOKE', '(?i)^ST-99999$')
    if ($AutomationConfig -and $AutomationConfig.emailExcludeKeyRegexes) {
        $exclude = @($AutomationConfig.emailExcludeKeyRegexes)
    }

    $allDrafts = @(Get-JiraAiDraftInventory -FeaturedKeys $featuredKeys -ExcludeKeyRegexes $exclude)
    # Completion email: only the Jira(s) that just finished — never prior drafts.
    $drafts = @($allDrafts | Where-Object { $_.Featured -and -not $_.IsPlaceholder })
    if ($drafts.Count -eq 0) {
        Write-JiraAiLog ('Draft email skipped: no completed RCA draft for featured key(s) {0}.' -f ($featuredKeys -join ', ')) 'WARN'
        return $null
    }

    $featuredLabel = ($drafts | ForEach-Object { $_.Key }) -join ', '
    $subject = if ($drafts.Count -eq 1) {
        '[{0}] RCA draft ready — copy/paste into Jira' -f $drafts[0].Key
    } else {
        'Jira AI RCA drafts ready ({0}) — copy/paste into Jira' -f $featuredLabel
    }

    $sections = New-Object System.Collections.Generic.List[string]
    $sections.Add('<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#222">') | Out-Null
    $sections.Add('<p><b>Investigation complete.</b> Copy the RCA below and paste it into the Jira comment.</p>') | Out-Null
    $sections.Add('<p style="color:#666;font-size:12px">Local draft only — not posted to Jira automatically.</p>') | Out-Null

    foreach ($d in $drafts) {
        $pasteBody = [string]$d.Body
        # Strip automation failure markers so paste content stays RCA-only.
        $pasteBody = [regex]::Replace(
            $pasteBody,
            '(?ms)\r?\n---\r?\n\r?\n## Automation failure\r?\n.*\z',
            ''
        )
        $pasteBody = [regex]::Replace(
            $pasteBody,
            '(?ms)\r?\n## Automation failure\r?\n.*\z',
            ''
        )
        $pasteBody = $pasteBody.Trim()

        $sections.Add(('<h2 style="margin-bottom:4px">{0}</h2>' -f (ConvertTo-JiraAiHtmlEncoded $d.Key))) | Out-Null
        if ($d.Summary) {
            $sections.Add(('<p style="margin-top:0;color:#555">{0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $d.Summary))) | Out-Null
        }
        $sections.Add('<p style="margin:12px 0 6px 0"><b>Copy everything in the box below:</b></p>') | Out-Null
        # Selectable plain RCA block — no extra chrome inside the copy area.
        $sections.Add(('<pre style="white-space:pre-wrap;word-wrap:break-word;background:#ffffff;border:2px solid #333;padding:14px;border-radius:4px;font-family:Consolas,Courier New,monospace;font-size:12px;line-height:1.45;user-select:all;-webkit-user-select:all">{0}</pre>' -f (ConvertTo-JiraAiHtmlEncoded $pasteBody))) | Out-Null
        if ($d.Path) {
            $sections.Add(('<p style="color:#888;font-size:11px">Local file: {0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $d.Path))) | Out-Null
        }
        $sections.Add('<hr/>') | Out-Null
    }

    $sections.Add('</body></html>') | Out-Null
    $html = $sections -join [Environment]::NewLine

    # Plain-text alternative: pure RCA for clients that prefer text copy.
    $plainParts = New-Object System.Collections.Generic.List[string]
    foreach ($d in $drafts) {
        $plainBody = [string]$d.Body
        $plainBody = [regex]::Replace($plainBody, '(?ms)\r?\n---\r?\n\r?\n## Automation failure\r?\n.*\z', '')
        $plainBody = [regex]::Replace($plainBody, '(?ms)\r?\n## Automation failure\r?\n.*\z', '')
        $plainParts.Add(('===== {0} RCA (copy below) =====' -f $d.Key)) | Out-Null
        $plainParts.Add($plainBody.Trim()) | Out-Null
        $plainParts.Add('') | Out-Null
    }
    $plainText = $plainParts -join "`r`n"

    $outbox = Join-Path (Get-JiraAiDraftsRoot) 'outbox'
    if (-not (Test-Path -LiteralPath $outbox)) {
        New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $featSlug = ($drafts[0].Key -replace '[^\w\-]', '_')
    $emlPath = Join-Path $outbox ('{0}-{1}.eml' -f $stamp, $featSlug)

    $boundary = 'jira_ai_boundary_{0}' -f ([guid]::NewGuid().ToString('N'))
    $eml = @(
        ('To: {0}' -f $to)
        ('Subject: {0}' -f $subject)
        'X-Unsent: 1'
        'MIME-Version: 1.0'
        ('Content-Type: multipart/alternative; boundary="{0}"' -f $boundary)
        ''
        ('--{0}' -f $boundary)
        'Content-Type: text/plain; charset=utf-8'
        'Content-Transfer-Encoding: 8bit'
        ''
        $plainText
        ('--{0}' -f $boundary)
        'Content-Type: text/html; charset=utf-8'
        'Content-Transfer-Encoding: 8bit'
        ''
        $html
        ('--{0}--' -f $boundary)
    ) -join "`r`n"
    [System.IO.File]::WriteAllText($emlPath, $eml, [System.Text.UTF8Encoding]::new($false))

    Write-JiraAiLog ('process: sending draft email for {0}' -f $featuredLabel)

    $delivery = 'send'
    if ($AutomationConfig -and $AutomationConfig.emailDelivery) {
        $delivery = ([string]$AutomationConfig.emailDelivery).Trim().ToLowerInvariant()
    }
    if ($delivery -notin @('send', 'draft', 'display', 'eml')) { $delivery = 'send' }

    $sentOrSaved = 'eml'
    $openEml = ($delivery -in @('eml', 'display')) -or ($AutomationConfig.emailOpenClient -eq $true)

    if ($delivery -in @('send', 'draft')) {
        $modeArg = $delivery
        $job = Start-Job -ScriptBlock {
            param($To, $Subject, $HtmlBody, $PlainBody, $Mode)
            $outlook = New-Object -ComObject Outlook.Application
            $mail = $outlook.CreateItem(0)
            $mail.To = $To
            $mail.Subject = $Subject
            $mail.BodyFormat = 2
            $mail.HTMLBody = $HtmlBody
            # Plain body helps some clients / paste workflows.
            try { $mail.Body = $PlainBody } catch { }
            if ($Mode -eq 'draft') {
                $mail.Save()
                'draft'
            }
            else {
                $mail.Send()
                'send'
            }
        } -ArgumentList $to, $subject, $html, $plainText, $modeArg

        $completed = Wait-Job -Job $job -Timeout 20
        if ($completed -and $job.State -eq 'Completed') {
            $sentOrSaved = [string](Receive-Job -Job $job)
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        }
        else {
            Stop-Job -Job $job -Force -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-JiraAiLog 'Outlook COM timed out / blocked; leaving .eml in outbox.' 'WARN'
            $sentOrSaved = 'eml-fallback'
            $openEml = $true
        }
    }

    if ($openEml -and (Test-Path -LiteralPath $emlPath)) {
        try {
            Start-Process -FilePath $emlPath | Out-Null
        }
        catch {
            Write-JiraAiLog ('Could not open .eml: {0}' -f $_.Exception.Message) 'WARN'
        }
    }

    Remove-JiraAiOutboxEmlIfSent -EmlPath $emlPath -Delivery $sentOrSaved

    if ($sentOrSaved -eq 'send') {
        Write-JiraAiLog ('process: Done sending draft email for {0}' -f $featuredLabel)
    }
    elseif ($sentOrSaved -eq 'draft') {
        Write-JiraAiLog 'process: Done creating draft email in Outlook'
    }
    else {
        Write-JiraAiLog 'process: Failed sending draft email — left .eml in outbox' 'WARN'
    }

    Write-JiraAiLog ('Draft email {0} for {1} ({2} just-finished draft(s); eml={3}).' -f $sentOrSaved, $to, $drafts.Count, $(if ($sentOrSaved -eq 'send') { 'deleted' } else { $emlPath }))
    if ($AutomationConfig.notifyToast -ne $false) {
        $toastMsg = if ($sentOrSaved -eq 'send') {
            'Emailed RCA draft for {0}' -f $featuredLabel
        } else {
            'RCA draft mail ready for {0} - check Outlook / outbox' -f $featuredLabel
        }
        Show-JiraAiToast -Title 'Jira AI RCA draft email' -Message $toastMsg
    }

    [pscustomobject]@{
        To           = $to
        Subject      = $subject
        Delivery     = $sentOrSaved
        EmlPath      = if ($sentOrSaved -eq 'send') { $null } else { $emlPath }
        DraftCount   = $drafts.Count
        FeaturedKeys = @($drafts | ForEach-Object { $_.Key })
    }
}
