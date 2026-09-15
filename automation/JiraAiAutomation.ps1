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

function Get-JiraAiFailureLogsRoot {
    $dir = Join-Path (Get-JiraAiAutomationRoot) 'logs\failures'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $dir
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

    $model = 'auto'
    if ($AutomationConfig -and $AutomationConfig.localModel) {
        $model = [string]$AutomationConfig.localModel
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

    Write-JiraAiLog ('Starting local jira-ai-fix for {0} (cwd={1}, model={2})' -f $JiraKey, $cwd, $model)

    $argList = @(
        ('"{0}"' -f $script),
        '--jira', $JiraKey,
        '--cwd', ('"{0}"' -f $cwd),
        '--model', $model
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

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $code = $proc.ExitCode
    if ($stderr) { Write-JiraAiLog ($stderr.Trim()) $(if ($code -eq 0) { 'INFO' } else { 'WARN' }) }

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

    [pscustomobject]@{
        Ok           = ($code -eq 0)
        DryRun       = $false
        Prompt       = $prompt
        DraftPath    = $draftPath
        FailurePath  = if ($summary -and $summary.failurePath) { [string]$summary.failurePath } else { $null }
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
      Writes %USERPROFILE%\.jira-ai-automation\logs\failures\<KEY>-failure.txt
      describing why a process failed, which part failed, and the root cause.
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
    $dir = Get-JiraAiFailureLogsRoot
    $path = Join-Path $dir ('{0}-failure.txt' -f $key)
    $lines = @(
        ('Jira: {0}' -f $key)
        ('Time: {0}' -f (Get-Date).ToString('o'))
        ('Process: {0}' -f $ProcessName)
        ('Failed part: {0}' -f $Phase)
        ('Why it failed: {0}' -f $Why)
        ('Root cause: {0}' -f $RootCause)
        ('Status: {0}' -f $Status)
        ('Exit code: {0}' -f $ExitCode)
        ('Cwd: {0}' -f $Cwd)
        ('Run id: {0}' -f $RunId)
        ''
        'Details / stack:'
        $(if ([string]::IsNullOrWhiteSpace($Details)) { '(none)' } else { $Details })
        ''
    )
    Set-Content -LiteralPath $path -Value ($lines -join [Environment]::NewLine) -Encoding UTF8
    Write-JiraAiLog ('Failure report written: {0}' -f $path)
    return $path
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
    #>
    param(
        $AutomationConfig,
        [Parameter(Mandatory)][string]$JiraKey,
        [Parameter(Mandatory)][ValidateSet('started', 'resumed', 'failed')][string]$Phase,
        [string]$Summary,
        [string]$JiraStatus,
        [string]$BrowseUrl,
        [string]$Details
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

    $phaseLabel = switch ($Phase) {
        'started' { 'Investigation started' }
        'resumed' { 'Investigation resumed' }
        'failed'  { 'Investigation failed' }
    }
    $statusLabel = if ([string]::IsNullOrWhiteSpace($JiraStatus)) { 'Unknown' } else { $JiraStatus.Trim() }
    $subject = if ($Phase -eq 'failed') {
        '[{0}] {1}' -f $JiraKey, $phaseLabel
    } else {
        '[{0}] {1} - {2}' -f $JiraKey, $phaseLabel, $statusLabel
    }

    $safeKey = ConvertTo-JiraAiHtmlEncoded $JiraKey
    $safeSummary = ConvertTo-JiraAiHtmlEncoded $Summary
    $safeStatus = ConvertTo-JiraAiHtmlEncoded $statusLabel
    $safeDetails = ConvertTo-JiraAiHtmlEncoded $Details
    $safeUrl = ConvertTo-JiraAiHtmlEncoded $BrowseUrl
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

    Write-JiraAiLog ('Lifecycle email {0} for {1}: {2} ({3}).' -f $sentOrSaved, $JiraKey, $Phase, $emlPath)
    [pscustomobject]@{
        To       = $to
        Subject  = $subject
        Delivery = $sentOrSaved
        EmlPath  = $emlPath
        Phase    = $Phase
    }
}

function Send-JiraAiDraftsEmail {
    <#
      Emails local RCA drafts. Featured keys (just finished) appear first; remaining
      investigated drafts from ~/.jira-ai-drafts follow.

      Delivery:
      - Always writes an .eml under ~/.jira-ai-drafts/outbox/ (reliable fallback).
      - emailDelivery=send|draft tries Outlook COM (with timeout); falls back to .eml.
      - emailDelivery=eml|display opens/leaves the .eml for the mail client.
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

    $exclude = @('(?i)^ST-SMOKE', '(?i)^ST-99999$')
    if ($AutomationConfig -and $AutomationConfig.emailExcludeKeyRegexes) {
        $exclude = @($AutomationConfig.emailExcludeKeyRegexes)
    }

    $drafts = @(Get-JiraAiDraftInventory -FeaturedKeys $FeaturedKeys -ExcludeKeyRegexes $exclude)
    if ($drafts.Count -eq 0) {
        Write-JiraAiLog 'Draft email skipped: no RCA drafts found.' 'WARN'
        return $null
    }

    $featured = @($drafts | Where-Object { $_.Featured })
    $featuredLabel = if ($featured.Count -gt 0) {
        ($featured | ForEach-Object { $_.Key }) -join ', '
    } else {
        ($drafts | Select-Object -First 3 | ForEach-Object { $_.Key }) -join ', '
    }

    $subject = if ($featured.Count -eq 1) {
        'Jira AI drafts ready: {0} (+{1} prior)' -f $featured[0].Key, [Math]::Max(0, $drafts.Count - 1)
    } elseif ($featured.Count -gt 1) {
        'Jira AI drafts ready: {0} (+{1} prior)' -f $featuredLabel, [Math]::Max(0, $drafts.Count - $featured.Count)
    } else {
        'Jira AI investigated drafts ({0})' -f $drafts.Count
    }

    $sections = New-Object System.Collections.Generic.List[string]
    $sections.Add('<html><body style="font-family:Segoe UI,Arial,sans-serif;font-size:13px;color:#222">') | Out-Null
    $sections.Add('<p>Jira AI automation finished analysis. Draft RCA comments below (local only - not posted to Jira).</p>') | Out-Null
    if ($featured.Count -gt 0) {
        $featKeys = ($featured | ForEach-Object { $_.Key }) -join ', '
        $sections.Add(('<p><b>Just completed:</b> {0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $featKeys))) | Out-Null
    }
    $sections.Add('<hr/>') | Out-Null

    foreach ($d in $drafts) {
        $badge = if ($d.Featured) { ' <span style="background:#dff0d8;padding:2px 6px;border-radius:3px;">new</span>' } else { '' }
        if ($d.IsPlaceholder) { $badge += ' <span style="background:#fcf8e3;padding:2px 6px;border-radius:3px;">placeholder</span>' }
        $sections.Add(('<h2 style="margin-bottom:4px">{0}{1}</h2>' -f (ConvertTo-JiraAiHtmlEncoded $d.Key), $badge)) | Out-Null
        if ($d.Summary) {
            $sections.Add(('<p style="margin-top:0;color:#555">{0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $d.Summary))) | Out-Null
        }
        if ($d.AgentUrl) {
            $safeUrl = ConvertTo-JiraAiHtmlEncoded $d.AgentUrl
            $sections.Add(('<p><a href="{0}">Agent link</a></p>' -f $safeUrl)) | Out-Null
        }
        $sections.Add(('<p style="color:#888;font-size:11px">{0}</p>' -f (ConvertTo-JiraAiHtmlEncoded $d.Path))) | Out-Null
        $sections.Add(('<pre style="white-space:pre-wrap;background:#f7f7f7;border:1px solid #ddd;padding:12px;border-radius:4px">{0}</pre>' -f (ConvertTo-JiraAiHtmlEncoded $d.Body))) | Out-Null
        $sections.Add('<hr/>') | Out-Null
    }

    $sections.Add('<p style="color:#888;font-size:11px">Review in Cursor, then ask: post jira comment draft for &lt;KEY&gt;</p>') | Out-Null
    $sections.Add('</body></html>') | Out-Null
    $html = $sections -join [Environment]::NewLine

    $outbox = Join-Path (Get-JiraAiDraftsRoot) 'outbox'
    if (-not (Test-Path -LiteralPath $outbox)) {
        New-Item -ItemType Directory -Force -Path $outbox | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $featSlug = if ($featured.Count -gt 0) { ($featured[0].Key -replace '[^\w\-]', '_') } else { 'drafts' }
    $emlPath = Join-Path $outbox ('{0}-{1}.eml' -f $stamp, $featSlug)

    # RFC822-ish .eml Outlook / default mail client can open.
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
        } -ArgumentList $to, $subject, $html, $modeArg

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

    Write-JiraAiLog ('Draft email {0} for {1} ({2} draft(s); featured={3}; eml={4}).' -f $sentOrSaved, $to, $drafts.Count, $featuredLabel, $emlPath)
    if ($AutomationConfig.notifyToast -ne $false) {
        $toastMsg = if ($sentOrSaved -eq 'send') {
            'Emailed {0} draft(s) to {1}' -f $drafts.Count, $to
        } else {
            'Drafts mail ready ({0}) - check Outlook / outbox' -f $featSlug
        }
        Show-JiraAiToast -Title 'Jira AI drafts email' -Message $toastMsg
    }

    [pscustomobject]@{
        To           = $to
        Subject      = $subject
        Delivery     = $sentOrSaved
        EmlPath      = $emlPath
        DraftCount   = $drafts.Count
        FeaturedKeys = @($featured | ForEach-Object { $_.Key })
    }
}
