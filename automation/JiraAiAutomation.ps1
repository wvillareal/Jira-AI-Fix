#Requires -Version 5.1
<#
.SYNOPSIS
  Helpers for Jira-assign -> Cursor Cloud Agent -> local RCA draft automation.
#>

function Get-JiraAiAutomationRoot {
    Join-Path $env:USERPROFILE '.jira-ai-automation'
}

function Get-JiraAiDraftsRoot {
    Join-Path $env:USERPROFILE '.jira-ai-drafts'
}

function Write-JiraAiLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $root = Get-JiraAiAutomationRoot
    $logDir = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    }
    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
    $logFile = Join-Path $logDir ('poller-{0:yyyyMMdd}.log' -f (Get-Date))
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

function Get-JiraAiAutomationConfig {
    $path = Join-Path (Get-JiraAiAutomationRoot) 'config.json'
    $example = Join-Path (Get-JiraAiAutomationRoot) 'config.example.json'
    if (-not (Test-Path -LiteralPath $path)) {
        if (Test-Path -LiteralPath $example) {
            Copy-Item -LiteralPath $example -Destination $path
            Write-JiraAiLog 'Created config.json from example. Set cursorApiKey and defaultRepo before live runs.' 'WARN'
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

function Get-CursorApiKey {
    param($AutomationConfig)
    $direct = [string]$AutomationConfig.cursorApiKey
    if ($direct -and $direct.Trim()) { return $direct.Trim() }

    $envName = 'CURSOR_API_KEY'
    if ($AutomationConfig.cursorApiKeyEnv) { $envName = [string]$AutomationConfig.cursorApiKeyEnv }
    foreach ($scope in @('Process', 'User', 'Machine')) {
        $v = [Environment]::GetEnvironmentVariable($envName, $scope)
        if ($v) { return $v }
    }
    throw "Cursor API key not set. Put cursorApiKey in config.json or set env $envName."
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

    $uri = '{0}/rest/api/3/search' -f $Auth.SiteUrl
    $fields = @('summary', 'status', 'issuetype', 'assignee', 'updated', 'project')

    $invokeSearch = {
        param([string]$Jql)
        $bodyObj = @{ jql = $Jql; maxResults = 50; fields = $fields }
        $body = $bodyObj | ConvertTo-Json -Depth 6
        Invoke-RestMethod -Method Post -Uri $uri -Headers $Auth.Headers -Body $body
    }

    # Single-quoted so PowerShell does not treat currentUser() as a subexpression.
    $jqlPrimary = 'assignee = currentUser() AND status in (' + $statusList + ') AND issuetype in (' + $typeList + ') AND assignee changed AFTER -' + $LookbackMinutes + 'm'
    try {
        $resp = & $invokeSearch $jqlPrimary
    }
    catch {
        Write-JiraAiLog ('JQL assignee-changed failed ({0}); falling back to updated lookback.' -f $_.Exception.Message) 'WARN'
        $jqlFallback = 'assignee = currentUser() AND status in (' + $statusList + ') AND issuetype in (' + $typeList + ') AND updated >= -' + $LookbackMinutes + 'm'
        $resp = & $invokeSearch $jqlFallback
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

function New-DraftOnlyPrompt {
    param([Parameter(Mandatory)][string]$JiraKey)
    $fenceOpen = '```' + 'jira-rca-draft'
    $fenceClose = '```'
    @(
        "analyze and fix $JiraKey"
        ''
        'Mode: DRAFT_JIRA_COMMENT only.'
        '- Follow jira-ai-fix / JIRA-AI-Fix runbook end-to-end (analyze, fix, push feature branch).'
        '- Do NOT post any comment to Jira (no Atlassian MCP addComment, no REST comment).'
        '- Author the comment body using runbook section 6 (Root Cause Analysis / Acceptance Verification)'
        '  exactly as for a live post - same blocks, acceptance entries, and honesty rules.'
        '- At the end, emit exactly one fenced block containing that full section 6 body:'
        ''
        $fenceOpen
        '...full section 6 RCA / Acceptance Verification markdown...'
        $fenceClose
    ) -join [Environment]::NewLine
}

function Get-CursorAuthHeaders {
    param([Parameter(Mandatory)][string]$ApiKey)
    $b64 = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(('{0}:' -f $ApiKey)))
    @{
        Authorization  = "Basic $b64"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }
}

function Start-CursorCloudAgent {
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [string]$ApiBase = 'https://api.cursor.com',
        [Parameter(Mandatory)][string]$PromptText,
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$StartingRef,
        [string]$Name = 'jira-ai-fix draft',
        [bool]$AutoCreatePR = $false
    )

    $uri = '{0}/v1/agents' -f $ApiBase.TrimEnd('/')
    $payload = @{
        prompt       = @{ text = $PromptText }
        name         = $Name
        autoCreatePR = [bool]$AutoCreatePR
        repos        = @(
            @{
                url         = $RepoUrl
                startingRef = $StartingRef
            }
        )
    }
    $json = $payload | ConvertTo-Json -Depth 8
    $headers = Get-CursorAuthHeaders -ApiKey $ApiKey
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json
}

function Get-CursorAgentRun {
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [string]$ApiBase = 'https://api.cursor.com',
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$RunId
    )
    $uri = '{0}/v1/agents/{1}/runs/{2}' -f $ApiBase.TrimEnd('/'), $AgentId, $RunId
    $headers = Get-CursorAuthHeaders -ApiKey $ApiKey
    Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
}

function Wait-CursorAgentRun {
    param(
        [Parameter(Mandatory)][string]$ApiKey,
        [string]$ApiBase = 'https://api.cursor.com',
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$RunId,
        [int]$PollSeconds = 30,
        [int]$TimeoutMinutes = 180
    )
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $terminal = @('FINISHED', 'ERROR', 'CANCELLED', 'EXPIRED')
    do {
        $run = Get-CursorAgentRun -ApiKey $ApiKey -ApiBase $ApiBase -AgentId $AgentId -RunId $RunId
        $status = [string]$run.status
        Write-JiraAiLog "Agent $AgentId run $RunId status=$status"
        if ($terminal -contains $status.ToUpperInvariant()) { return $run }
        Start-Sleep -Seconds $PollSeconds
    } while ((Get-Date) -lt $deadline)
    throw "Timed out waiting for agent $AgentId run $RunId after $TimeoutMinutes minutes."
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
