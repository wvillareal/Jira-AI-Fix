#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$IssueKey
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JiraAiAutomation.ps1')

$auto = Get-JiraAiAutomationConfig
$userBundle = Get-JiraAiUserConfig
$auth = Get-AtlassianAuth -UserCfg $userBundle.Cfg
$store = Get-ProcessedStore
$mode = Get-JiraAiAutomationMode -AutomationConfig $auto

if ($mode -eq 'cloud') {
    Write-JiraAiLog 'mode=cloud is retired. Forcing local. Set "mode": "local" in config.json.' 'WARN'
    $mode = 'local'
}

$lookback = 15
if ($auto.pollLookbackMinutes) { $lookback = [int]$auto.pollLookbackMinutes }

$issues = @()
if ($IssueKey) {
    $issues = @(
        [pscustomobject]@{
            Key     = $IssueKey.ToUpperInvariant()
            Summary = '(manual)'
            Status  = 'Open'
            Type    = 'Bug'
            Project = ($IssueKey -split '-')[0]
            Updated = (Get-Date).ToString('o')
        }
    )
    Write-JiraAiLog ('Manual issue: {0}' -f $issues[0].Key)
}
else {
    Write-JiraAiLog ('Polling Jira (lookback {0}m, mode={1})...' -f $lookback, $mode)
    $issues = @(Find-NewlyAssignedJiras -Auth $auth -AutomationConfig $auto -LookbackMinutes $lookback)
    Write-JiraAiLog ('Found {0} candidate(s).' -f $issues.Count)

    # An in-progress item can remain after shutdown/restart. The scheduled task
    # uses IgnoreNew, so a live owner PID means another poller still owns it.
    $knownKeys = @{}
    foreach ($candidate in $issues) { $knownKeys[[string]$candidate.Key] = $true }
    foreach ($recoverKey in @($store.Items.Keys)) {
        $prior = $store.Items[$recoverKey]
        if (-not $prior) { continue }

        # Only recover interrupted in-progress runs. Failed investigations keep
        # their RCA draft (with failure note) and must not be retried forever.
        if ([string]$prior.lifecycle -ne 'in-progress') { continue }

        $ownerIsAlive = $false
        if ($prior.ownerPid) {
            $ownerIsAlive = $null -ne (Get-Process -Id ([int]$prior.ownerPid) -ErrorAction SilentlyContinue)
        }
        if ($ownerIsAlive -or $knownKeys.ContainsKey($recoverKey)) { continue }

        Write-JiraAiLog ('Recovering interrupted investigation for {0}.' -f $recoverKey) 'WARN'
        $issues += [pscustomobject]@{
            Key        = $recoverKey
            Summary    = [string]$prior.summary
            Status     = if ($prior.jiraStatus) { [string]$prior.jiraStatus } else { 'Open' }
            Type       = if ($prior.issueType) { [string]$prior.issueType } else { 'Bug' }
            Project    = ($recoverKey -split '-')[0]
            Updated    = if ($prior.startedAt) { [string]$prior.startedAt } else { (Get-Date).ToString('o') }
            Recovering = $true
        }
    }
}

if ($issues.Count -eq 0) {
    Write-JiraAiLog 'No matching assignments.'
    return
}

$featuredForEmail = New-Object System.Collections.Generic.List[string]

foreach ($issue in $issues) {
    $key = $issue.Key
    $existingDraftPath = Join-Path (Get-JiraAiDraftsRoot) ('{0}-rca.md' -f $key)
    if (Test-Path -LiteralPath $existingDraftPath) {
        Write-JiraAiLog ('Skip {0} (RCA draft already exists: {1}).' -f $key, $existingDraftPath)
        $store.Items[$key] = @{
            lifecycle  = 'completed'
            finishedAt = (Get-Item -LiteralPath $existingDraftPath).LastWriteTime.ToString('o')
            mode       = 'existing-draft'
            summary    = [string]$issue.Summary
            jiraStatus = [string]$issue.Status
            draft      = $existingDraftPath
            status     = 'skipped-existing-draft'
            ok         = $true
        }
        Save-ProcessedStore -Store $store
        continue
    }

    $priorItem = if ($store.Items.ContainsKey($key)) { $store.Items[$key] } else { $null }
    $recovering = [bool]($priorItem -and [string]$priorItem.lifecycle -eq 'in-progress')
    if ($priorItem -and -not $IssueKey -and -not $recovering) {
        Write-JiraAiLog ('Skip {0} (already processed).' -f $key)
        continue
    }

    Write-JiraAiLog ('Processing {0}: {1}' -f $key, $issue.Summary)
    $repo = Resolve-RepoForIssue -Issue $issue -AutomationConfig $auto
    $browseUrl = '{0}/browse/{1}' -f $auth.SiteUrl, $key

    try {
        $jiraBundle = Get-JiraIssueBundle -Auth $auth -JiraKey $key
        if ($jiraBundle.Summary) { $issue.Summary = $jiraBundle.Summary }
        if ($jiraBundle.Status) { $issue.Status = $jiraBundle.Status }
        if ($jiraBundle.Type) { $issue.Type = $jiraBundle.Type }
        if ($jiraBundle.BrowseUrl) { $browseUrl = $jiraBundle.BrowseUrl }
        Write-JiraAiLog ('Fetched Jira {0}: {1}' -f $key, $jiraBundle.Summary)
    }
    catch {
        Write-JiraAiLog ('Jira fetch failed for {0}: {1}' -f $key, $_.Exception.Message) 'WARN'
    }

    if ($mode -eq 'notify') {
        $prompt = New-DesktopAnalyzePrompt -JiraKey $key
        $saved = Save-JiraAssignNotify `
            -JiraKey $key `
            -Summary ([string]$issue.Summary) `
            -BrowseUrl $browseUrl `
            -PromptText $prompt `
            -Repo $repo `
            -DryRun:([bool]$DryRun)

        if ($auto.notifyClipboard -ne $false) {
            Set-JiraAiClipboard -Text $prompt
        }

        $toastTitle = if ($DryRun) { 'Jira assigned (dry-run)' } else { 'Jira assigned - run jira-ai-fix' }
        $toastMsg = ("{0}: paste in Cursor: jira-ai-fix {0}" -f $key)
        if ($auto.notifyToast -ne $false) {
            Show-JiraAiToast -Title $toastTitle -Message $toastMsg
        }

        Write-JiraAiLog ('Notify written: {0}' -f $saved.MarkdownPath)
        $store.Items[$key] = @{
            finishedAt = (Get-Date).ToString('o')
            mode       = if ($DryRun) { 'notify-dry-run' } else { 'notify' }
            summary    = [string]$issue.Summary
            browseUrl  = $browseUrl
            notify     = $saved.MarkdownPath
            prompt     = $prompt
        }
        Save-ProcessedStore -Store $store
        if (-not $DryRun) { $featuredForEmail.Add($key) | Out-Null }
        continue
    }

    # mode = local (Cursor SDK on this machine — real jira-ai-fix skill)
    $startedAt = (Get-Date).ToString('o')
    if (-not $DryRun) {
        $store.Items[$key] = @{
            lifecycle  = 'in-progress'
            startedAt  = $startedAt
            resumed    = $recovering
            ownerPid   = $PID
            mode       = 'local'
            summary    = [string]$issue.Summary
            jiraStatus = [string]$issue.Status
            issueType  = [string]$issue.Type
            browseUrl  = $browseUrl
            cwd        = if ($auto.localCwd) { [string]$auto.localCwd } else { $null }
        }
        Save-ProcessedStore -Store $store

        $startPhase = if ($recovering) { 'resumed' } else { 'started' }
        try {
            Send-JiraAiLifecycleEmail `
                -AutomationConfig $auto `
                -JiraKey $key `
                -Phase $startPhase `
                -Summary ([string]$issue.Summary) `
                -JiraStatus ([string]$issue.Status) `
                -BrowseUrl $browseUrl | Out-Null
        }
        catch {
            Write-JiraAiLog ('Started email failed for {0}: {1}' -f $key, $_.Exception.Message) 'WARN'
        }
        if ($auto.notifyToast -ne $false) {
            $startToast = if ($recovering) { 'Local investigation resumed' } else { 'Local investigation started' }
            Show-JiraAiToast -Title 'Jira AI in progress' -Message ('{0}: {1}' -f $key, $startToast)
        }
    }

    try {
        $local = Start-JiraAiLocalAgent -JiraKey $key -AutomationConfig $auto -DryRun:$DryRun
        if ($auto.notifyToast -ne $false) {
            $toastTitle = if ($DryRun) { 'Jira AI local (dry-run)' } else { 'Jira AI local finished' }
            $toastMsg = if ($local.DraftPath) { '{0} -> {1}' -f $key, $local.DraftPath } else { '{0} status={1}' -f $key, $local.Status }
            Show-JiraAiToast -Title $toastTitle -Message $toastMsg
        }

        $failurePath = $null
        $draftAfterFailure = $null
        if (-not $local.Ok -and -not $DryRun) {
            $failurePath = $local.FailurePath
            if (-not $failurePath -or -not (Test-Path -LiteralPath $failurePath)) {
                $failurePath = Write-JiraAiFailureReport `
                    -JiraKey $key `
                    -ProcessName 'local Cursor SDK agent' `
                    -Phase $(if ($local.FailurePhase) { $local.FailurePhase } else { 'local-agent-execution' }) `
                    -Why $(if ($local.FailureWhy) { $local.FailureWhy } else { ('Local agent exited with code {0} (status={1}).' -f $local.ExitCode, $local.Status) }) `
                    -RootCause $(if ($local.RootCause) { $local.RootCause } else { 'Runner returned non-zero without a structured failure report.' }) `
                    -Details ($(if ($local.StdErr) { $local.StdErr } else { $local.RawOutput })) `
                    -ExitCode $local.ExitCode `
                    -Status ([string]$local.Status) `
                    -Cwd ([string]$local.Cwd) `
                    -RunId ([string]$local.RunId)
            }
            else {
                # Runner already wrote logs/failures; still preserve/annotate the RCA draft.
                Save-JiraAiFailureNoteInDraft `
                    -JiraKey $key `
                    -Phase $(if ($local.FailurePhase) { $local.FailurePhase } else { 'local-agent-execution' }) `
                    -Why $(if ($local.FailureWhy) { $local.FailureWhy } else { ('Local agent exited with code {0} (status={1}).' -f $local.ExitCode, $local.Status) }) `
                    -RootCause $(if ($local.RootCause) { $local.RootCause } else { 'Runner returned non-zero without a structured failure report.' }) `
                    -FailureLogPath $failurePath `
                    -ProcessName 'local Cursor SDK agent' `
                    -ExitCode $local.ExitCode `
                    -Status ([string]$local.Status) | Out-Null
            }
            $draftAfterFailure = Join-Path (Get-JiraAiDraftsRoot) ('{0}-rca.md' -f $key)
            if (-not (Test-Path -LiteralPath $draftAfterFailure)) { $draftAfterFailure = $null }
        }

        $store.Items[$key] = @{
            lifecycle = if ($local.Ok) { 'completed' } else { 'failed' }
            startedAt = $startedAt
            finishedAt = (Get-Date).ToString('o')
            mode       = if ($DryRun) { 'local-dry-run' } else { 'local' }
            summary    = [string]$issue.Summary
            jiraStatus = [string]$issue.Status
            browseUrl  = $browseUrl
            draft      = if ($local.Ok) { $local.DraftPath } else { $draftAfterFailure }
            failure    = if ($local.Ok) { $null } else { $failurePath }
            status     = $local.Status
            runId      = $local.RunId
            cwd        = $local.Cwd
            ok         = [bool]$local.Ok
        }
        Save-ProcessedStore -Store $store

        if ($local.Ok -and -not $DryRun) {
            $featuredForEmail.Add($key) | Out-Null
            Write-JiraAiLog ('Local agent OK for {0}: {1}' -f $key, $local.DraftPath)
        }
        elseif (-not $local.Ok) {
            Write-JiraAiLog ('Local agent failed for {0}: exit={1} status={2}' -f $key, $local.ExitCode, $local.Status) 'ERROR'
            if (-not $DryRun) {
                $failDetails = 'Exit code: {0}; runner status: {1}' -f $local.ExitCode, $local.Status
                if ($failurePath) { $failDetails = '{0}; failure report: {1}' -f $failDetails, $failurePath }
                if ($draftAfterFailure) { $failDetails = '{0}; RCA draft kept: {1}' -f $failDetails, $draftAfterFailure }
                if ($local.FailureWhy) { $failDetails = '{0}`nWhy: {1}' -f $failDetails, $local.FailureWhy }
                if ($local.RootCause) { $failDetails = '{0}`nRoot cause: {1}' -f $failDetails, $local.RootCause }
                try {
                    Send-JiraAiLifecycleEmail `
                        -AutomationConfig $auto `
                        -JiraKey $key `
                        -Phase failed `
                        -Summary ([string]$issue.Summary) `
                        -JiraStatus ([string]$issue.Status) `
                        -BrowseUrl $browseUrl `
                        -Details $failDetails | Out-Null
                }
                catch {
                    Write-JiraAiLog ('Failure email failed for {0}: {1}' -f $key, $_.Exception.Message) 'WARN'
                }
            }
        }
    }
    catch {
        $failureMessage = $_.Exception.Message
        Write-JiraAiLog ('Failed {0}: {1}' -f $key, $failureMessage) 'ERROR'
        if (-not $DryRun) {
            $failurePath = Write-JiraAiFailureReport `
                -JiraKey $key `
                -ProcessName 'automation poller' `
                -Phase 'poller-exception' `
                -Why $failureMessage `
                -RootCause 'Unhandled exception while starting or waiting on the local investigation.' `
                -Details $_.Exception.ToString() `
                -Status 'exception'
            $draftAfterFailure = Join-Path (Get-JiraAiDraftsRoot) ('{0}-rca.md' -f $key)
            if (-not (Test-Path -LiteralPath $draftAfterFailure)) { $draftAfterFailure = $null }
            $store.Items[$key] = @{
                lifecycle  = 'failed'
                startedAt  = $startedAt
                finishedAt = (Get-Date).ToString('o')
                mode       = 'local'
                summary    = [string]$issue.Summary
                jiraStatus = [string]$issue.Status
                browseUrl  = $browseUrl
                draft      = $draftAfterFailure
                failure    = $failurePath
                status     = 'exception'
                error      = $failureMessage
                ok         = $false
            }
            Save-ProcessedStore -Store $store
            try {
                Send-JiraAiLifecycleEmail `
                    -AutomationConfig $auto `
                    -JiraKey $key `
                    -Phase failed `
                    -Summary ([string]$issue.Summary) `
                    -JiraStatus ([string]$issue.Status) `
                    -BrowseUrl $browseUrl `
                    -Details ('{0}`nFailure report: {1}' -f $failureMessage, $failurePath) | Out-Null
            }
            catch {
                Write-JiraAiLog ('Failure email failed for {0}: {1}' -f $key, $_.Exception.Message) 'WARN'
            }
        }
    }
}

if ($featuredForEmail.Count -gt 0 -and $auto.notifyEmail -ne $false) {
    try {
        Send-JiraAiDraftsEmail -AutomationConfig $auto -FeaturedKeys @($featuredForEmail) | Out-Null
    }
    catch {
        Write-JiraAiLog ('Draft email step failed: {0}' -f $_.Exception.Message) 'ERROR'
    }
}

Write-JiraAiLog 'Poller pass complete.'
