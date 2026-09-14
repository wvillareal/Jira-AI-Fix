#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$IssueKey,
    [switch]$SkipWait
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JiraAiAutomation.ps1')

$auto = Get-JiraAiAutomationConfig
$userBundle = Get-JiraAiUserConfig
$auth = Get-AtlassianAuth -UserCfg $userBundle.Cfg
$store = Get-ProcessedStore

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
    Write-JiraAiLog ('Polling Jira (lookback {0}m)...' -f $lookback)
    $issues = @(Find-NewlyAssignedJiras -Auth $auth -AutomationConfig $auto -LookbackMinutes $lookback)
    Write-JiraAiLog ('Found {0} candidate(s).' -f $issues.Count)
}

if ($issues.Count -eq 0) {
    Write-JiraAiLog 'No matching assignments.'
    return
}

$apiKey = $null
$apiBase = 'https://api.cursor.com'
if ($auto.cursorApiBase) { $apiBase = [string]$auto.cursorApiBase }
if (-not $DryRun) {
    $apiKey = Get-CursorApiKey -AutomationConfig $auto
}

foreach ($issue in $issues) {
    $key = $issue.Key
    if ($store.Items.ContainsKey($key) -and -not $IssueKey) {
        Write-JiraAiLog ('Skip {0} (already processed).' -f $key)
        continue
    }

    Write-JiraAiLog ('Processing {0}: {1}' -f $key, $issue.Summary)
    $repo = Resolve-RepoForIssue -Issue $issue -AutomationConfig $auto
    if (-not $repo -or -not $repo.url) {
        Write-JiraAiLog ('No defaultRepo/repoByProject for {0} - skip.' -f $key) 'ERROR'
        continue
    }

    $prompt = New-DraftOnlyPrompt -JiraKey $key
    $agentName = 'jira-ai-fix {0} (draft RCA)' -f $key

    if ($DryRun) {
        $placeholder = @(
            '# Root Cause Analysis'
            ''
            '**Summary (non-technical):**'
            ''
            ('DRY-RUN placeholder for {0} - {1}. Replace by a real Cloud Agent run.' -f $key, $issue.Summary)
            ''
            '**Delivery:**'
            ''
            '* **Feature branch:** (not created - dry run)'
            ''
            '**Acceptance Verification-**'
            ''
            '*Verified by the automated analysis run, not by manual developer testing - QA sign-off is still required.*'
            ''
            '**Criteria source:** derived - dry-run placeholder'
            ''
            '**Acceptance verdict:** 0 of 0 criteria satisfied and observed - dry-run only'
        ) -join [Environment]::NewLine

        $meta = [ordered]@{
            jiraKey     = $key
            dryRun      = $true
            summary     = $issue.Summary
            finishedAt  = (Get-Date).ToString('o')
            agentId     = $null
            runId       = $null
            agentUrl    = $null
            branch      = $null
            repoUrl     = [string]$repo.url
            startingRef = [string]$repo.startingRef
            prCreated   = $false
        }
        $saved = Save-JiraRcaDraft -JiraKey $key -Body $placeholder -Meta $meta
        Write-JiraAiLog ('Dry-run draft written: {0}' -f $saved.MarkdownPath)
        if ($auto.notifyToast -ne $false) {
            Show-JiraAiToast -Title 'Jira AI draft (dry-run)' -Message ('{0} -> {1}' -f $key, $saved.MarkdownPath)
        }
        $store.Items[$key] = @{
            finishedAt = $meta.finishedAt
            dryRun     = $true
            draft      = $saved.MarkdownPath
        }
        Save-ProcessedStore -Store $store
        continue
    }

    try {
        $created = Start-CursorCloudAgent `
            -ApiKey $apiKey `
            -ApiBase $apiBase `
            -PromptText $prompt `
            -RepoUrl ([string]$repo.url) `
            -StartingRef ([string]$repo.startingRef) `
            -Name $agentName `
            -AutoCreatePR ([bool]$auto.autoCreatePR)

        $agentId = [string]$created.agent.id
        $runId = [string]$created.run.id
        $agentUrl = [string]$created.agent.url
        Write-JiraAiLog ('Started agent {0} run {1} ({2})' -f $agentId, $runId, $agentUrl)

        $run = $null
        $draftBody = $null
        $branch = $null

        $shouldWait = -not $SkipWait
        if ($auto.waitForCompletion -eq $false) { $shouldWait = $false }

        if ($shouldWait) {
            $pollSec = 30
            if ($auto.agentPollSeconds) { $pollSec = [int]$auto.agentPollSeconds }
            $timeoutMin = 180
            if ($auto.agentTimeoutMinutes) { $timeoutMin = [int]$auto.agentTimeoutMinutes }

            $run = Wait-CursorAgentRun -ApiKey $apiKey -ApiBase $apiBase -AgentId $agentId -RunId $runId `
                -PollSeconds $pollSec -TimeoutMinutes $timeoutMin

            $resultText = [string]$run.result
            if ($run.git -and $run.git.branches -and $run.git.branches.Count -gt 0) {
                $branch = [string]$run.git.branches[0].branch
            }
            $draftBody = Extract-JiraRcaDraft -Text $resultText
            if (-not $draftBody) {
                Write-JiraAiLog 'No jira-rca-draft fence in agent result; saving full result as fallback.' 'WARN'
                if ($resultText) {
                    $draftBody = $resultText
                }
                else {
                    $draftBody = '(no result text; status={0})' -f ([string]$run.status)
                }
            }
        }
        else {
            $draftBody = @(
                '# Root Cause Analysis'
                ''
                '**Summary (non-technical):**'
                ''
                ('Cloud Agent started for {0} but this poller run did not wait for completion.' -f $key)
                ('Open: {0}' -f $agentUrl)
                'Re-run without -SkipWait (and with waitForCompletion true) to harvest the section 6 draft.'
            ) -join [Environment]::NewLine
        }

        $meta = [ordered]@{
            jiraKey     = $key
            dryRun      = $false
            summary     = $issue.Summary
            finishedAt  = (Get-Date).ToString('o')
            agentId     = $agentId
            runId       = $runId
            agentUrl    = $agentUrl
            runStatus   = if ($run) { [string]$run.status } else { 'LAUNCHED' }
            branch      = $branch
            repoUrl     = [string]$repo.url
            startingRef = [string]$repo.startingRef
            prCreated   = $false
        }
        $saved = Save-JiraRcaDraft -JiraKey $key -Body $draftBody -Meta $meta
        Write-JiraAiLog ('Draft written: {0}' -f $saved.MarkdownPath)
        if ($auto.notifyToast -ne $false) {
            Show-JiraAiToast -Title 'Jira AI RCA draft ready' -Message ('{0} -> {1}' -f $key, $saved.MarkdownPath)
        }
        $store.Items[$key] = @{
            finishedAt = $meta.finishedAt
            agentId    = $agentId
            runId      = $runId
            agentUrl   = $agentUrl
            draft      = $saved.MarkdownPath
        }
        Save-ProcessedStore -Store $store
    }
    catch {
        Write-JiraAiLog ('Failed {0}: {1}' -f $key, $_.Exception.Message) 'ERROR'
    }
}

Write-JiraAiLog 'Poller pass complete.'
