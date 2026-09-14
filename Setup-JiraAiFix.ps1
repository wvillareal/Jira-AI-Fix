<#
.SYNOPSIS
    Interactive configuration wizard for the JIRA-AI-Fix skill.

.DESCRIPTION
    Gathers everything the JIRA-AI-Fix runbook needs into
    %USERPROFILE%\.jira-ai-config.json, explaining for every input what it is for, which
    runbook step consumes it, and what a run loses without it.

    Runs in YOUR terminal, which matters for two reasons:

      * Interactive prompts work. ssh-keygen, ssh-copy-id and password prompts need a real
        terminal; an AI agent runs commands in a captured subprocess and cannot answer them.
      * No secret ever reaches an AI context, a chat transcript, or a log. What you type here
        goes to the config file and nowhere else.

    It detects whatever it can before asking - repo root, SQL Server instances and versions,
    default data paths, free disk space, SSH tunnels, MCP servers - and asks you to confirm
    rather than to type.

    Nothing here is mandatory except the repo root. Every section you skip removes one
    capability, and the wizard records the consequence you accepted so every later run can
    disclose its own limits.

.PARAMETER ConfigPath
    Override the config file location. Default: %USERPROFILE%\.jira-ai-config.json

.PARAMETER Section
    Jump straight to one section: repo, atlassian, sql, restore, servers, ssh, helpdesk,
    sharepoint, appenv, i21connect, verify. Use this to fill one gap later without walking
    the whole wizard.

.PARAMETER Uninstall
    Remove the config and the installed skill, then exit. Runs before the config
    is even read, so a damaged or half-written config cannot block it.

.PARAMETER Yes
    With -Uninstall, answer yes to every prompt INCLUDING deleting the SSH key
    pair. For unattended teardown. Without it, each group is confirmed.

.PARAMETER TemplatePath
    Path to jira-ai-config.example.json, used to seed a new config with its inline
    documentation. Defaults to the copy beside this script or in the installed skill.

.EXAMPLE
    .\Setup-JiraAiFix.ps1
    Full guided setup.

.EXAMPLE
    .\Setup-JiraAiFix.ps1 -Section helpdesk
    Refresh just the helpdesk cookie.

.EXAMPLE
    .\Setup-JiraAiFix.ps1 -Section verify
    Re-test every configured capability and refresh the recorded status.
#>

[CmdletBinding()]
param(
    [string] $ConfigPath,
    [ValidateSet('repo', 'atlassian', 'sql', 'restore', 'servers', 'ssh', 'helpdesk', 'sharepoint', 'appenv', 'i21connect', 'verify')]
    [string] $Section,
    [string] $TemplatePath,
    [switch] $Resume,
    [switch] $Uninstall,
    [switch] $Yes,
    [switch] $PauseOnExit
)

$ErrorActionPreference = 'Stop'

# =============================================================================== presentation

$script:W = 78

function Write-Rule { param([char] $C = '-') Write-Host ([string]$C * $script:W) -ForegroundColor DarkGray }

function Write-Banner {
    param([string] $Text)
    Write-Host ''
    Write-Rule '='
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Rule '='
}

function Write-Wrapped {
    param([string] $Text, [string] $Prefix = '  ', [string] $Color = 'Gray')
    $words = $Text -split '\s+'
    $line = ''
    foreach ($w in $words) {
        if (($line.Length + $w.Length + 1) -gt ($script:W - $Prefix.Length)) {
            Write-Host "$Prefix$line" -ForegroundColor $Color
            $line = $w
        }
        elseif ($line -eq '') { $line = $w }
        else { $line = "$line $w" }
    }
    if ($line -ne '') { Write-Host "$Prefix$line" -ForegroundColor $Color }
}

# The core of this wizard: never ask for a value without saying what it is for,
# where the runbook uses it, and what is lost without it.
function Write-FieldInfo {
    param(
        [string]   $Name,
        [string]   $What,
        [string]   $Where,
        [string]   $Without,
        [string[]] $Notes
    )
    Write-Host ''
    Write-Host "  $Name" -ForegroundColor White
    Write-Host ''
    Write-Host '    WHAT IT IS' -ForegroundColor DarkCyan
    Write-Wrapped $What '      '
    Write-Host ''
    Write-Host '    WHERE THE RUNBOOK USES IT' -ForegroundColor DarkCyan
    Write-Wrapped $Where '      '
    Write-Host ''
    Write-Host '    WITHOUT IT' -ForegroundColor DarkYellow
    Write-Wrapped $Without '      '
    if ($Notes) {
        Write-Host ''
        Write-Host '    WORTH KNOWING' -ForegroundColor DarkCyan
        foreach ($n in $Notes) { Write-Wrapped "- $n" '      ' 'DarkGray' }
    }
    Write-Host ''
}

function Write-Ok     { param([string] $m) Write-Host "  [ ok ]   $m" -ForegroundColor Green }
function Write-Warn   { param([string] $m) Write-Host "  [ !  ]   $m" -ForegroundColor Yellow }
function Write-Bad    { param([string] $m) Write-Host "  [fail]   $m" -ForegroundColor Red }
function Write-Note   { param([string] $m) Write-Host "  [ .. ]   $m" -ForegroundColor DarkGray }
function Write-Found  { param([string] $m) Write-Host "  [found]  $m" -ForegroundColor Cyan }

# Sentinels usable at any prompt. Deliberately prefixed so they cannot collide with a real
# value - "back" could be a server name, "!b" could not.
$script:BACK = '!!BACK!!'

# Every prompt here loops until it gets something usable, which is right for a
# person and fatal for a redirected stdin: once the pipe runs dry Read-Host
# returns empty for ever and the loop spins - 1.5 MB of repeated menu in 45
# seconds, measured while testing. Called from the branches that reject an
# answer and go round again, so a blank line legitimately accepting a default
# never counts. Interactive sessions can never trip it: a person typing three
# rejected answers is normal, and IsInputRedirected is false for them anyway.
$script:DryReads = 0
function Assert-InputAlive {
    if (-not [Console]::IsInputRedirected) { return }
    $script:DryReads++
    if ($script:DryReads -lt 3) { return }
    Write-Host ''
    Write-Bad 'the input stream ended while a prompt was waiting'
    Write-Wrapped 'This wizard is interactive - the token prompts read the console directly, so answers cannot be piped into it. Run it in a real terminal, or copy config/jira-ai-config.example.json and fill that in by hand.' '    ' 'Yellow'
    Complete-Wizard -Unsaved
}

function Read-Text {
    param([string] $Prompt, [string] $Default, [switch] $AllowEmpty, [switch] $NoBack)
    $reflex = ''   # the y/n answer already queried once, so repeating it confirms it
    while ($true) {
        $hint = ''
        if (-not $NoBack) { $hint = '  (!b back)' }
        # Blank ACCEPTS THE DEFAULT whenever one is offered - it does not skip.
        # Callers used to label such a prompt "(blank to skip)", which told the
        # operator the opposite of what the code does and made the skip branch
        # unreachable. Skipping past a default now has its own token, and the
        # hint is rendered here so a caller's wording can never contradict the
        # behaviour again.
        $skipHint = ''
        if ($AllowEmpty -and $Default) { $skipHint = '  (!s skip)' }
        if ($Default) { $p = "  $Prompt [$Default]$skipHint$hint" } else { $p = "  $Prompt$hint" }
        $v = Read-Host $p
        if ($v -eq '!b' -and -not $NoBack) { return $script:BACK }
        # '!s' is the documented skip token. Also accept bare 'skip' and '!s skip' -
        # people type the hint text literally, and that used to be stored as a path
        # and crash later in Split-Path -Qualifier.
        if ($v -eq '!s' -or ($AllowEmpty -and $v -match '^(?i)(!s\s+)?skip$')) {
            if ($AllowEmpty) { return '' }
            Write-Warn 'this field cannot be skipped. !b to back out of this section.'
            Assert-InputAlive
            continue
        }
        if ($v -eq '!?') { Write-Note 'that field is described above - scroll up for what it is, where it is used, and what is lost without it'; continue }
        if ([string]::IsNullOrWhiteSpace($v)) {
            if ($Default) { return $Default }
            if ($AllowEmpty) { return '' }
            Write-Warn 'a value is needed. !b to back out of this section.'
            Assert-InputAlive
            continue
        }
        $v = $v.Trim()

        # A bare y/n is answered at the wrong prompt: these value prompts follow a
        # [Y/n] question, and the reflex answer used to be stored verbatim - "n"
        # became the Atlassian site URL and verification then called
        # n/rest/api/3/myself, which reads like a credential fault rather than a
        # mistyped field. Guarded only where a default is offered, because that is
        # where the confusion lives and where blank already means "keep this".
        # Repeating the answer confirms it, so a field whose value genuinely is
        # "n" is still reachable.
        if ($Default -and $v -match '^(?i)(y|yes|n|no)$' -and $reflex -ne $v.ToLower()) {
            $reflex = $v.ToLower()
            Write-Warn "'$v' looks like an answer to a Y/n question - this prompt wants a value"
            Write-Wrapped "Press Enter to keep [$Default], or type the value. If '$v' really is the value, type it again." '    ' 'Yellow'
            Assert-InputAlive
            continue
        }
        return $v
    }
}

function Test-IsBack { param($Value) return ($Value -is [string] -and $Value -eq $script:BACK) }

# URL fields used to accept any non-blank answer, and that answer went straight
# into a REST path: a site URL of "n" produced "n/rest/api/3/myself" and a DNS
# failure. Normalising and shape-checking here keeps a value that cannot be a
# host away from the network call. Pure - no prompting, no output - so it is
# unit-testable on its own.
function Resolve-UrlAnswer {
    param([string] $Value)

    $v = ''
    if ($Value) { $v = $Value.Trim() }
    if (-not $v) { return [pscustomobject] @{ Ok = $false; Value = ''; Reason = 'a URL is needed' } }

    if ($v -match '^(?i)(y|yes|n|no)$') {
        return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "'$v' is a yes/no answer, not a URL" }
    }

    $hadScheme = $v -match '^(?i)https?://'
    if (-not $hadScheme) {
        if ($v -match '^[A-Za-z][A-Za-z0-9+.-]*:') {
            return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "'$v' is not an http or https address" }
        }
        # People paste a bare host out of the address bar; that is a fair answer.
        $v = "https://$v"
    }

    $u = $null
    if (-not [Uri]::TryCreate($v, [UriKind]::Absolute, [ref] $u)) {
        return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "'$Value' is not a URL" }
    }
    if ($u.Scheme -ne 'http' -and $u.Scheme -ne 'https') {
        return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "only http and https are supported, not '$($u.Scheme)'" }
    }
    if (-not $u.Host) {
        return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "'$Value' has no host" }
    }
    # A single-label host is legitimate on an intranet (https://appserver/2710DEV),
    # but only where the operator actually typed a scheme. A lone word with no
    # scheme and no dot is a typo or an answer meant for a different prompt.
    if (-not $hadScheme -and $u.Host -notmatch '\.' -and $u.Host -notmatch '^(?i)localhost$') {
        return [pscustomobject] @{ Ok = $false; Value = $v; Reason = "'$Value' is not a host name - it has no domain" }
    }

    return [pscustomobject] @{ Ok = $true; Value = $v.TrimEnd('/'); Reason = '' }
}

# The prompting half. Keeps asking until the answer resolves, so a mistyped URL is
# never a dead end and never reaches a REST call.
function Read-Url {
    param([string] $Prompt, [string] $Default, [string] $Example, [switch] $NoBack)
    while ($true) {
        $raw = Read-Text $Prompt $Default -NoBack:$NoBack
        if (Test-IsBack $raw) { return $script:BACK }

        $r = Resolve-UrlAnswer $raw
        if ($r.Ok) {
            if ($r.Value -ne $raw) { Write-Note "reading that as $($r.Value)" }
            return $r.Value
        }

        Write-Bad $r.Reason
        $hint = 'Give the full address, scheme included.'
        if ($Example) { $hint = "Give the full address, scheme included - like $Example." }
        Write-Wrapped $hint '    ' 'Yellow'
        Assert-InputAlive
    }
}

# Offered after any failed validation, so a typo is never a dead end.
# A labelled chooser, for the places a yes/no cannot carry the answer.
# $Options is @( @{ Key = '1'; Label = '...' }, ... ) and the Key comes back.
function Read-Option {
    param(
        [Parameter(Mandatory)] [array] $Options,
        [string] $Default
    )
    foreach ($o in $Options) {
        $mark = ' '
        if ($o.Key -eq $Default) { $mark = '*' }
        Write-Host "   $mark $($o.Key)  $($o.Label)" -ForegroundColor Gray
    }
    $hint = ''
    if ($Default) { $hint = " [$Default]" }
    while ($true) {
        $v = Read-Host "  Choice$hint"
        if ([string]::IsNullOrWhiteSpace($v)) {
            if ($Default) { return $Default }
            Write-Warn ('pick one of: ' + (($Options.Key) -join ', '))
            Assert-InputAlive
            continue
        }
        $k = $v.Trim().ToLower()
        if ($Options.Key -contains $k) { return $k }
        Write-Warn ('pick one of: ' + (($Options.Key) -join ', '))
        Assert-InputAlive
    }
}

function Read-FailureChoice {
    param([string] $What)
    Write-Host ''
    Write-Host "  $What did not verify. What now?" -ForegroundColor Yellow
    Write-Host '    r  re-enter the values and try again   (default)' -ForegroundColor Gray
    Write-Host '    c  keep what I entered and carry on    (recorded as failed)' -ForegroundColor Gray
    Write-Host '    s  skip this section entirely'                     -ForegroundColor Gray
    while ($true) {
        $v = Read-Host '  Choice [r]'
        if ([string]::IsNullOrWhiteSpace($v)) { return 'retry' }

        # This prompt takes one letter, and Read-Host echoes. Someone who has
        # just been told their cookie failed naturally pastes the next cookie
        # HERE - printing the whole thing on screen, then looping because it is
        # not r, c or s. Catch it, and say the part that matters: it is exposed.
        if ($v.Length -gt 40 -and $v -match '=') {
            Write-Bad 'that looks like a pasted value, not a choice - and this prompt echoed it'
            Write-Wrapped 'Only r, c or s are accepted here. Press r and the value prompt will ask again, without echoing.' '    ' 'Yellow'
            Write-Wrapped 'What you just pasted is now visible in this window and its scrollback. Treat it as exposed: sign out of that service so the session is invalidated, then capture a fresh one.' '    ' 'Yellow'
            Assert-InputAlive
            continue
        }
        switch ($v.Trim().ToLower()) {
            'r' { return 'retry' }
            'c' { return 'continue' }
            's' { return 'skip' }
            default { Write-Warn 'r, c or s'; Assert-InputAlive }
        }
    }
}

function Read-YesNo {
    param([string] $Prompt, [bool] $Default = $true)
    if ($Default) { $hint = 'Y/n' } else { $hint = 'y/N' }
    while ($true) {
        $v = Read-Host "  $Prompt [$hint]"
        if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
        if ($v -match '^(y|yes)$') { return $true }
        if ($v -match '^(n|no)$')  { return $false }
        Assert-InputAlive
    }
}

# Secrets are read without echo and converted only in memory, on the way to the config file.
function Read-Secret {
    param([string] $Prompt, [switch] $NoBack)
    $hint = ' (not shown)'
    if (-not $NoBack) { $hint = ' (not shown, !b back)' }
    # -AsSecureString reads the console directly, so a redirected stdin never
    # reaches it - the prompt just blocks for ever. An agent that piped its
    # answers in gets told that here instead of hanging until something kills it.
    if ([Console]::IsInputRedirected) {
        Write-Host ''
        Write-Bad "'$Prompt' can only be answered at a real console"
        Write-Wrapped 'Secret prompts read the console directly, so piped answers never reach them. Run the wizard in a terminal, or copy config/jira-ai-config.example.json and fill in the secrets by hand.' '    ' 'Yellow'
        Complete-Wizard -Unsaved
    }

    $sec = Read-Host "  $Prompt$hint" -AsSecureString
    # -AsSecureString hands back $null, not an empty SecureString, when the
    # console has no more input - and `$null.Length` is a terminating error.
    if (-not $sec) { Assert-InputAlive; return '' }
    if ($sec.Length -eq 0) { return '' }
    $probe = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($probe)
        if ($plain -eq '!b' -and -not $NoBack) { return $script:BACK }
    } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($probe) }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Show-SecretShape {
    param([string] $Name, [string] $Value)
    if ([string]::IsNullOrEmpty($Value)) { Write-Note "$Name left empty"; return }
    Write-Ok "$Name set - $($Value.Length) characters (value not displayed)"
}

# =============================================================================== state

$script:Cfg    = $null
$script:Status = [ordered] @{}
$script:UserHome   = $env:USERPROFILE
if (-not $script:UserHome) { $script:UserHome = $env:HOME }

# Single source for the URL: it is both printed in the notes and handed to the
# browser, and those two drifting apart is the whole problem this fixes.
$script:AtlassianTokenUrl = 'https://id.atlassian.com/manage-profile/security/api-tokens'

function Set-Status {
    param(
        [string] $Key,
        [ValidateSet('verified', 'configured', 'partial', 'skipped', 'not-applicable', 'failed')]
        [string] $State,
        [string] $Detail,
        [string] $Consequence,
        [ValidateSet('not-yet', 'not-applicable')]
        [string] $Kind
    )
    $e = [ordered] @{ state = $State }
    if ($Detail)      { $e.detail      = $Detail }
    if ($Consequence) { $e.consequence = $Consequence }
    if ($Kind)        { $e.kind        = $Kind }
    $script:Status[$Key] = $e
}

# Every skip is spoken aloud, costed, and confirmed - never silent.
function Confirm-Skip {
    param([string] $Key, [string] $Consequence, [string] $Severity = 'normal')
    Write-Host ''
    Write-Host '  SKIPPING THIS MEANS:' -ForegroundColor Yellow
    Write-Wrapped $Consequence '    ' 'Yellow'
    if ($Severity -eq 'severe') {
        Write-Host ''
        Write-Wrapped 'This is not a normal skip. The skill will be installed but no run can complete without it.' '    ' 'Red'
    }
    Write-Host ''
    if (-not (Read-YesNo 'Skip it anyway and carry on?' $false)) { return $false }
    $forever = Read-YesNo 'Is this permanent (you will never have this) rather than "not yet"?' $false
    if ($forever) { Set-Status $Key 'not-applicable' -Consequence $Consequence -Kind 'not-applicable' }
    else          { Set-Status $Key 'skipped'        -Consequence $Consequence -Kind 'not-yet' }
    Write-Note 'recorded - every run will disclose this gap rather than quietly proving less'
    return $true
}

function Get-Node {
    param($Parent, [string] $Name)
    if ($null -eq $Parent) { return $null }
    if ($Parent -is [System.Collections.IDictionary]) {
        if (-not $Parent.Contains($Name)) { $Parent[$Name] = [ordered] @{} }
        return $Parent[$Name]
    }
    return $null
}

# =============================================================================== detection

# PowerShell 5.1 turns a native executable's stderr into NativeCommandError
# records, and $ErrorActionPreference = 'Stop' promotes the first one into a
# terminating error. Any probe written as `& git ... 2>&1 | Out-Null` therefore
# killed the whole wizard the moment git said anything on stderr - which git
# does routinely, credential-helper chatter alone - and it died before
# Save-Config had ever run, so the session's answers went with it.
#
# Swallowing the stderr is only half the problem. Left to itself an
# unauthenticated remote makes git sit on a credential prompt, so the crash
# just becomes a hang - measured at over two minutes against an ADO URL with
# no stored credential. So probes run out-of-process, with every interactive
# credential path disabled, and time-boxed on top of that.
#
# Returns the process exit code, or 124 when the timeout fired.
function Invoke-Probe {
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [string[]] $Arguments = @(),
        [int] $TimeoutSeconds = 20
    )
    return (Invoke-ProbeCore -Exe $Exe -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds).Code
}

# Same hardening, but the output comes back too - some probes are run for what
# the command says, not just whether it worked.
function Invoke-ProbeCore {
    param(
        [Parameter(Mandatory)] [string] $Exe,
        [string[]] $Arguments = @(),
        [int] $TimeoutSeconds = 20
    )

    # A repo root is allowed to contain spaces ("C:\i21 Source"), and the
    # argument string is parsed by the child, so quote before joining.
    $joined = (@(
        foreach ($a in $Arguments) {
            if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
        }
    ) -join ' ')

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Exe
    $psi.Arguments              = $joined
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true

    # Scoped to the child, so the wizard's own environment is never touched.
    # git's terminal prompt and the Windows Git Credential Manager dialog both
    # have to be off, or a probe meant to answer in seconds blocks on a login.
    $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $psi.EnvironmentVariables['GCM_INTERACTIVE']     = 'never'

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        if (-not $proc.Start()) { return [pscustomobject] @{ Code = 1; Out = ''; Err = '' } }

        # Drain both pipes while the child runs. A chatty child fills a pipe
        # buffer and deadlocks against its own WaitForExit otherwise.
        $tOut = $proc.StandardOutput.ReadToEndAsync()
        $tErr = $proc.StandardError.ReadToEndAsync()

        if ($proc.WaitForExit($TimeoutSeconds * 1000)) {
            return [pscustomobject] @{ Code = $proc.ExitCode; Out = $tOut.Result; Err = $tErr.Result }
        }
        try { $proc.Kill() } catch { }
        return [pscustomobject] @{ Code = 124; Out = ''; Err = '' }
    }
    catch {
        # Process.Start throws when the executable is not on PATH, and swallowing
        # that reported "could not reach origin" to someone whose only problem
        # was that git was not installed on PATH - a whole afternoon aimed at
        # Azure DevOps access. 127 is the conventional "command not found", and
        # the message comes back so a caller can print what actually happened.
        $ex = $_.Exception
        if ($ex.InnerException) { $ex = $ex.InnerException }
        $code = 1
        if ($ex -is [System.ComponentModel.Win32Exception] -or $ex.Message -match '(?i)cannot find the file specified|No such file or directory') { $code = 127 }
        return [pscustomobject] @{ Code = $code; Out = ''; Err = "could not start '$Exe': $($ex.Message)" }
    }
    finally { try { $proc.Dispose() } catch { } }
}

# A URL printed as text is not the same as a URL opened. On the run that
# prompted this, the dev's assistant read the description of the page and
# navigated somewhere else entirely - so the exact URL now goes to the browser
# itself, and the text is only there to copy from when that fails.
#
# Opening is offered, never forced: a dev who already holds a token says no and
# moves on. And it can never end the wizard - a machine with no registered
# browser handler throws, and under $ErrorActionPreference = 'Stop' that would
# be fatal exactly like the git probe was.
function Open-Url {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [string] $What = 'that page'
    )

    Write-Host ''
    Write-Host "    $Url" -ForegroundColor Cyan

    if (-not (Read-YesNo "Open $What in your browser now?" $true)) {
        Write-Note 'not opened - copy the URL above when you need it'
        return
    }

    # $IsWindows exists only on PowerShell 6+; on 5.1 its absence IS the answer.
    $onWindows = $true
    $winVar = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    if ($winVar) { $onWindows = [bool] $winVar.Value }

    try {
        if ($onWindows) {
            Start-Process -FilePath $Url
        }
        else {
            $macVar = Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue
            $opener = if ($macVar -and $macVar.Value) { 'open' } else { 'xdg-open' }
            if ((Invoke-Probe $opener @($Url) -TimeoutSeconds 15) -ne 0) {
                throw "$opener could not open it"
            }
        }
        Write-Ok 'opened in your default browser'
    }
    catch {
        Write-Warn "could not open a browser here: $($_.Exception.Message)"
        Write-Wrapped 'Copy the URL above into a browser by hand - this section works the same either way.' '    ' 'Yellow'
    }
}

function Find-RepoRoot {
    $hits = @()

    # Strongest signal: we may be standing inside one of the repositories already.
    try {
        $top = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and $top) {
            $parent = Split-Path -Parent ($top -replace '/', '\')
            if ($parent) { $hits += $parent }
        }
    } catch { }

    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null } | Select-Object -ExpandProperty Name
    foreach ($d in $drives) {
        foreach ($leaf in @('i21Source', 'Source', 'i21', 'src', 'Repos')) {
            $p = "${d}:\$leaf"
            if (Test-Path -LiteralPath $p) { $hits += $p }
        }
    }

    $out = @()
    foreach ($h in ($hits | Select-Object -Unique)) {
        $n = Measure-RepoCount $h
        if ($n -ge 2) { $out += [pscustomobject] @{ Path = $h; Repos = $n } }
    }
    return ($out | Sort-Object -Property Repos -Descending)
}

function Measure-RepoCount {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    try {
        $dirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue
        $n = 0
        foreach ($d in $dirs) { if (Test-Path -LiteralPath (Join-Path $d.FullName '.git')) { $n++ } }
        return $n
    } catch { return 0 }
}

function Test-IsGitWorkTree {
    param([string] $Path)
    try {
        Push-Location -LiteralPath $Path
        try {
            $r = & git rev-parse --is-inside-work-tree 2>$null
            return ($LASTEXITCODE -eq 0 -and $r -eq 'true')
        } finally { Pop-Location }
    } catch { return $false }
}

function Find-SqlInstances {
    $out = @()
    try {
        $key = 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server'
        $ii = Get-ItemProperty -Path $key -Name InstalledInstances -ErrorAction SilentlyContinue
        if ($ii -and $ii.InstalledInstances) {
            foreach ($name in @($ii.InstalledInstances)) {
                $svcName = 'MSSQLSERVER'
                if ($name -ne 'MSSQLSERVER') { $svcName = "MSSQL`$$name" }
                $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
                $state = 'unknown'
                if ($svc) { $state = [string] $svc.Status }
                $out += [pscustomobject] @{
                    Instance = $name
                    Service  = $svcName
                    State    = $state
                    Address  = $(if ($name -eq 'MSSQLSERVER') { '.' } else { ".\$name" })
                }
            }
        }
    } catch { }
    return $out
}

function Invoke-SqlScalar {
    param([string] $ConnectionString, [string] $Query, [int] $TimeoutSec = 8)
    $conn = New-Object System.Data.SqlClient.SqlConnection $ConnectionString
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = $TimeoutSec
        return [string] $cmd.ExecuteScalar()
    } finally { $conn.Dispose() }
}

# Secrets go into an in-memory connection string, never onto a command line.
function New-SqlConnectionString {
    param([string] $Server, [string] $Auth, [string] $User, [string] $Password, [int] $TimeoutSec = 8)
    $b = "Server=$Server;Database=master;Connect Timeout=$TimeoutSec;Application Name=JIRA-AI-Fix Setup;"
    if ($Auth -eq 'windows') { return $b + 'Integrated Security=True;' }
    return $b + "User ID=$User;Password=$Password;"
}

function Get-SqlDefaultPaths {
    param([string] $ConnectionString)
    try {
        $d = Invoke-SqlScalar $ConnectionString "SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultDataPath'))"
        $l = Invoke-SqlScalar $ConnectionString "SELECT CONVERT(nvarchar(4000), SERVERPROPERTY('InstanceDefaultLogPath'))"
        return [pscustomobject] @{ Data = $d; Log = $l }
    } catch { return $null }
}

function Get-SqlServiceAccount {
    $out = @()
    try {
        $svcs = Get-CimInstance Win32_Service -Filter "Name LIKE 'MSSQL%'" -ErrorAction SilentlyContinue
        foreach ($s in $svcs) { $out += [pscustomobject] @{ Name = $s.Name; Account = $s.StartName; State = $s.State } }
    } catch { }
    return $out
}

function Get-VolumeReport {
    $out = @()
    try {
        foreach ($v in (Get-PSDrive -PSProvider FileSystem)) {
            if ($null -eq $v.Free) { continue }
            $total = $v.Free + $v.Used
            if ($total -le 0) { continue }
            $out += [pscustomobject] @{
                Drive   = "$($v.Name):"
                FreeGB  = [math]::Round($v.Free / 1GB, 1)
                TotalGB = [math]::Round($total / 1GB, 1)
            }
        }
    } catch { }
    return ($out | Sort-Object -Property FreeGB -Descending)
}

function Get-FreeGBForPath {
    param([string] $Path)
    try {
        $qualifier = (Split-Path -Qualifier $Path) -replace ':', ''
        $d = Get-PSDrive -Name $qualifier -ErrorAction SilentlyContinue
        if ($d -and $null -ne $d.Free) { return [math]::Round($d.Free / 1GB, 1) }
    } catch { }
    return $null
}

# Reads TOPOLOGY from the ssh config. Never keys, never passwords.
# The jump host may itself be Windows. Its default shell is then cmd.exe, where
# the POSIX install line dies with "The syntax of the command is incorrect." -
# which this wizard reported as a bad username or password, sending people off
# to re-check credentials that were never wrong. The SSH version banner is
# exchanged BEFORE authentication, so the platform can be settled for free.
# git is the one tool nothing here works without: every branch, commit and push
# in the runbook goes through it. It is also routinely installed but missing from
# a given session's PATH, which surfaces as "'git' is not recognized" - so look
# in the usual places before declaring it absent.
function Resolve-Git {
    $cmd = Get-Command 'git' -ErrorAction SilentlyContinue
    if ($cmd) { return [pscustomobject] @{ Path = $cmd.Source; OnPath = $true } }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Git\cmd\git.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
        (Join-Path $env:ProgramFiles 'Git\bin\git.exe')
    ) | Where-Object { $_ } | Select-Object -Unique

    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return [pscustomobject] @{ Path = $c; OnPath = $false } }
    }
    return [pscustomobject] @{ Path = ''; OnPath = $false }
}

# Run once, before anything tries to use git. Repairs PATH for this session when
# git is installed but unreachable, because that is a one-line fix and the whole
# run is useless without it.
function Assert-Git {
    $g = Resolve-Git
    if ($g.OnPath) {
        $v = Invoke-ProbeCore 'git' @('--version') 15
        if ($v.Code -eq 0) { Write-Ok ("git found: " + $g.Path + " - " + $v.Out.Trim()) }
        else { Write-Warn "git is on PATH at $($g.Path) but would not run: $($v.Err.Trim())" }
        return
    }

    if (-not $g.Path) {
        Write-Bad "git is not on PATH, and is not in any of the usual install locations"
        Write-Wrapped 'Nothing in the runbook works without git - every branch, commit and push goes through it, and this wizard cannot even count your repositories. Install Git for Windows, then open a NEW terminal and re-run this.' '    ' 'Yellow'
        Write-Wrapped 'If git IS installed, find it and add its folder to PATH: Get-Command git, or dir "C:\Program Files\Git\cmd\git.exe"' '    ' 'Yellow'
        Set-Status 'git' 'failed' -Detail 'not on PATH' -Consequence 'No repository work is possible: no clone, no branch, no commit, no push.'
        return
    }

    Write-Warn "git is installed at $($g.Path) but is not on PATH for this session"
    Write-Wrapped 'That is why a git command here reports "''git'' is not recognized" while it works fine in your other terminal - the session this wizard runs in has a different PATH.' '    ' 'Yellow'
    $dir = Split-Path -Parent $g.Path
    if (Read-YesNo 'Use it for this session so setup can continue?' $true) {
        $env:PATH = $dir + ';' + $env:PATH
        $v = Invoke-ProbeCore 'git' @('--version') 15
        if ($v.Code -eq 0) {
            Write-Ok ("git now available for this session - " + $v.Out.Trim())
            Write-Wrapped ("This lasts only as long as this window. Make it permanent, or every later run hits the same wall: add " + $dir + " to your user PATH, then open a new terminal.") '    ' 'DarkGray'
            Set-Status 'git' 'partial' -Detail "PATH patched for this session only ($dir)"
        }
        else { Write-Bad "still not usable: $($v.Err.Trim())" }
    }
    else {
        Write-Wrapped ("Add this to your user PATH and open a new terminal: " + $dir) '    ' 'Yellow'
        Set-Status 'git' 'failed' -Detail 'installed but not on PATH'
    }
}

function Get-SshRemoteKind {
    param([Parameter(Mandatory)] [string] $SshHost)
    $r = Invoke-ProbeCore 'ssh' @('-v', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', $SshHost, 'exit', '0') 20
    $banner = "$($r.Err)`n$($r.Out)"
    $script:LastBannerErr = ''
    if ($banner -match '(?i)remote software version\s+(\S+)') {
        if ($Matches[1] -match '(?i)for_Windows') { return 'windows' }
        return 'posix'
    }
    $why = @($banner -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*debug\d' } | Select-Object -First 2)
    if ($why.Count -gt 0) { $script:LastBannerErr = 'ssh said: ' + (($why | ForEach-Object { $_.Trim() }) -join ' / ') }
    elseif ($r.Code -eq 124) { $script:LastBannerErr = 'ssh did not answer inside the timeout' }
    return 'unknown'
}

function Get-SshTunnels {
    $cfg = Join-Path (Join-Path $script:UserHome '.ssh') 'config'
    if (-not (Test-Path -LiteralPath $cfg)) { return @() }

    # Collect whole Host blocks before emitting, because `User` may be declared
    # after the LocalForward lines it applies to. Reading the User matters: it is
    # the account on the jump host, and the wizard used to default to
    # $env:USERNAME - the WINDOWS account, a different thing entirely, and the
    # single most-mistyped answer in the whole run. The config usually already
    # has the right answer.
    $blocks = @()
    $cur = $null
    foreach ($raw in (Get-Content -LiteralPath $cfg)) {
        $line = $raw.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -match '^(?i)Host\s+(.+)$') {
            $cur = [pscustomobject] @{ Name = $Matches[1].Trim(); User = ''; HostName = ''; Forwards = @() }
            $blocks += $cur
            continue
        }
        if (-not $cur) { continue }
        if ($line -match '^(?i)User\s+(\S+)$') { $cur.User = $Matches[1]; continue }
        if ($line -match '^(?i)HostName\s+(\S+)$') { $cur.HostName = $Matches[1]; continue }
        if ($line -match '^(?i)LocalForward\s+(\S+)\s+(\S+)$') { $cur.Forwards += ,@($Matches[1], $Matches[2]) }
    }

    # A `Host *` block applies to every host, so its User is the fallback.
    $wildUser = ''
    $wild = @($blocks | Where-Object { $_.Name -eq '*' })
    if ($wild.Count -gt 0) { $wildUser = $wild[0].User }

    $out = @()
    foreach ($b in $blocks) {
        $u = $b.User
        if (-not $u) { $u = $wildUser }
        foreach ($f in $b.Forwards) {
            $lp = $f[0]; $target = $f[1]
            if ($lp -match ':') { $lp = ($lp -split ':')[-1] }
            $rHost = $target; $rPort = ''
            if ($target -match '^(.*):(\d+)$') { $rHost = $Matches[1]; $rPort = $Matches[2] }
            $real = $b.HostName
            if (-not $real) { $real = $b.Name }
            $out += [pscustomobject] @{
                SshHost    = $b.Name
                SshUser    = $u
                RealHost   = $real
                LocalPort  = $lp
                RemoteHost = $rHost
                RemotePort = $rPort
                Address    = "127.0.0.1,$lp"
                IsSql      = ($rPort -eq '1433' -or $lp -match '1433')
            }
        }
    }
    return $out
}

function Get-ListeningLoopbackPorts {
    try {
        return @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                 Where-Object { $_.LocalAddress -eq '127.0.0.1' } |
                 Select-Object -ExpandProperty LocalPort -Unique)
    } catch { return @() }
}

function Get-McpStatus {
    $files = @(
        (Join-Path $script:UserHome '.claude.json'),
        (Join-Path (Join-Path $script:UserHome '.cursor') 'mcp.json')
    )
    $found = @{}
    foreach ($f in $files) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $text = Get-Content -LiteralPath $f -Raw
            foreach ($n in @('atlassian', 'azure-devops', 'playwright')) {
                if ($text -match [regex]::Escape($n)) { $found[$n] = $true }
            }
        } catch { }
    }
    return $found
}

function Get-GitEmail {
    try {
        $e = & git config --get user.email 2>$null
        if ($LASTEXITCODE -eq 0 -and $e) { return $e.Trim() }
    } catch { }
    return ''
}

# =============================================================================== config io

function Import-Config {
    param([string] $Path, [string] $Template)

    if (Test-Path -LiteralPath $Path) {
        Write-Ok "found an existing config: $Path"
        Write-Note 'populated values are kept; you will be asked before anything is replaced'
        try {
            $loaded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
            # Carry the previous run's status forward, so a section already verified is not
            # re-asked and a failed one can be resumed.
            if ($loaded.PSObject.Properties.Name -contains '_setupStatus') {
                $prev = $loaded._setupStatus
                if ($prev.PSObject.Properties.Name -contains 'sections' -and $prev.sections) {
                    foreach ($p in $prev.sections.PSObject.Properties) {
                        $e = [ordered] @{}
                        foreach ($q in $p.Value.PSObject.Properties) { $e[$q.Name] = $q.Value }
                        $script:Status[$p.Name] = $e
                    }
                    Write-Note "carried forward $($script:Status.Count) section state(s) from the last run"
                }
            }
            return $loaded
        }
        catch {
            Write-Bad "it does not parse as JSON: $($_.Exception.Message)"
            Write-Wrapped 'A malformed config is, to the runbook, indistinguishable from no config at all. Fix it by hand, or let this wizard start a fresh one - your current file will be renamed, not deleted.' '    ' 'Yellow'
            if (-not (Read-YesNo 'Start fresh from the template? (your file is backed up)' $false)) { exit 1 }
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Move-Item -LiteralPath $Path -Destination "$Path.bak-$stamp"
            Write-Note "backed up to $(Split-Path -Leaf "$Path.bak-$stamp")"
        }
    }

    if ($Template -and (Test-Path -LiteralPath $Template)) {
        Write-Note "starting from the template: $Template"
        return (Get-Content -LiteralPath $Template -Raw | ConvertFrom-Json)
    }
    Write-Note 'no template found - starting from an empty config'
    return (New-Object psobject)
}

function ConvertTo-Ordered {
    param($Obj)
    if ($Obj -is [psobject] -and -not ($Obj -is [string])) {
        $h = [ordered] @{}
        foreach ($p in $Obj.PSObject.Properties) { $h[$p.Name] = ConvertTo-Ordered $p.Value }
        return $h
    }
    if ($Obj -is [Array]) {
        $a = @()
        foreach ($i in $Obj) { $a += ,(ConvertTo-Ordered $i) }
        return $a
    }
    return $Obj
}

function Save-Config {
    param([string] $Path, $Cfg)

    $h = ConvertTo-Ordered $Cfg

    $verdict = Get-Verdict
    $h['_setupStatus'] = [ordered] @{
        _readme        = 'Written by Setup-JiraAiFix.ps1. Records what was configured, what was skipped and the consequence accepted, so every run can disclose its own limits instead of quietly proving less.'
        packageVersion = (Get-PackageVersion)
        completedAt    = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK')
        verdict        = $verdict
        sections       = $script:Status
    }

    $json = $h | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8

    try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json | Out-Null; Write-Ok "written and re-parsed cleanly: $Path" }
    catch {
        Write-Bad "wrote $Path but it does not parse - fix before running the skill"
        Write-Wrapped $_.Exception.Message '    ' 'Yellow'
        return
    }

    # The config holds credentials. Make it readable only by this user.
    try {
        $acl = Get-Acl -LiteralPath $Path
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in @($acl.Access)) { $acl.RemoveAccessRule($r) | Out-Null }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'Allow')))
        Set-Acl -LiteralPath $Path -AclObject $acl
        Write-Ok "permissions restricted to $me"
    } catch { Write-Warn "could not restrict file permissions - it holds credentials, so check them yourself: $($_.Exception.Message)" }
}

function Get-PackageVersion {
    foreach ($c in @((Join-Path $PSScriptRoot 'MANIFEST.json'), (Join-Path (Split-Path -Parent $PSScriptRoot) 'MANIFEST.json'))) {
        if (Test-Path -LiteralPath $c) {
            try { return (Get-Content -LiteralPath $c -Raw | ConvertFrom-Json).version } catch { }
        }
    }
    return 'unknown'
}

function Get-Verdict {
    $repo = $script:Status['i21.repoRoot']
    if ($repo -and @('skipped', 'not-applicable', 'failed') -contains $repo.state) { return 'NOT-READY' }
    if (-not $repo) { return 'NOT-READY' }
    foreach ($k in $script:Status.Keys) {
        $s = $script:Status[$k].state
        if (@('skipped', 'not-applicable', 'failed', 'partial') -contains $s) { return 'READY-NARROWED' }
    }
    return 'READY'
}

# =============================================================================== sections

function Invoke-RepoSection {
    Write-Banner '1 of 6   Where your i21 repositories live'

    Write-FieldInfo -Name 'i21.repoRoot' `
        -What 'The single parent folder holding your i21 repository clones - AP, AR, GL, Liquibase, SqlScripts and the rest as sibling folders. This is the runbook''s REPO_ROOT.' `
        -Where 'Every run. The runbook works out by itself which repository a ticket affects, then does its analysis, branching, commit and push inside that repo. It has to know where to look first.' `
        -Without 'Nothing works. No run can locate the code. This is the one setting that is effectively required.' `
        -Notes @(
            'This is the CONTAINER of repositories, not a repository. The runbook never runs git against it directly.',
            'If you have not cloned anything yet, give the path you WANT to use - the runbook clones the repo it needs on first use.'
        )

    $existing = ''
    if ($script:Cfg.PSObject.Properties.Name -contains 'i21') { $existing = [string] $script:Cfg.i21.repoRoot }

    Write-Note 'looking for it...'
    $cands = Find-RepoRoot
    foreach ($c in $cands) { Write-Found "$($c.Path)  -  $($c.Repos) repository folders" }
    if (-not $cands) { Write-Warn 'no folder with multiple git repositories found in the usual places' }

    $default = $existing
    if (-not $default -and $cands) { $default = $cands[0].Path }

    Write-Host ''
    $val = Read-Text 'Repo root path' $default -AllowEmpty

    if (-not $val) {
        if (Confirm-Skip 'i21.repoRoot' 'No run can locate your code. The skill installs but is unusable until this is set.' 'severe') { return }
        $val = Read-Text 'Repo root path' $default
    }
    if (Test-IsBack $val) { return }

    # A repo root must be absolute. A relative answer - a typo like "2", or a
    # bare folder name - used to be created silently under whatever directory
    # the wizard happened to be launched from, which is never the intent and
    # leaves junk inside an unrelated repository.
    if (-not [System.IO.Path]::IsPathRooted($val)) {
        Write-Bad "'$val' is a relative path"
        Write-Wrapped 'Give a full path such as C:\i21Source. A relative answer would be created inside the folder this wizard was launched from, not where your clones live.' '    ' 'Yellow'
        Invoke-RepoSection
        return
    }
    try { $val = [System.IO.Path]::GetFullPath($val) } catch { }

    if (-not (Test-Path -LiteralPath $val)) {
        Write-Warn "that path does not exist yet"
        if (Read-YesNo 'Create it?' $true) {
            # Unguarded, this killed the whole wizard: $ErrorActionPreference is
            # 'Stop', so a denied create (an elevated-only location, a read-only
            # or missing drive) terminated the script instead of re-prompting.
            try {
                New-Item -ItemType Directory -Path $val -Force -ErrorAction Stop | Out-Null
                Write-Ok 'created'
            }
            catch {
                Write-Bad "could not create that folder: $($_.Exception.Message)"
                Write-Wrapped 'Pick a path you can write to, or create it yourself in Explorer and re-enter it.' '    ' 'Yellow'
                Invoke-RepoSection
                return
            }
        }
    }

    if (Test-Path -LiteralPath $val) {
        if (Test-IsGitWorkTree $val) {
            Write-Bad 'that folder is itself a git repository, not the container of repositories'
            Write-Wrapped 'You have probably given the path of one repo (...\i21Source\AP) instead of its parent (...\i21Source). Every run will misbehave with this set. Try again.' '    ' 'Yellow'
            Invoke-RepoSection
            return
        }
        $n = Measure-RepoCount $val
        Write-Ok "$val - $n repository folders"
        if ($n -eq 0) { Write-Note 'empty for now; the runbook will clone what it needs' }
        Set-Status 'i21.repoRoot' 'configured' -Detail "$val ($n repos)"
    }
    else { Set-Status 'i21.repoRoot' 'configured' -Detail $val }

    $node = $script:Cfg
    if (-not ($node.PSObject.Properties.Name -contains 'i21')) {
        $node | Add-Member -NotePropertyName 'i21' -NotePropertyValue (New-Object psobject) -Force
    }
    $node.i21 | Add-Member -NotePropertyName 'repoRoot' -NotePropertyValue $val -Force

    # Push access is worth proving now, not after an analysis is already done.
    if ($n -gt 0) {
        if (Read-YesNo 'Check push access against one repo? (recommended)' $true) {
            $one = Get-ChildItem -LiteralPath $val -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } | Select-Object -First 1
            if ($one) {
                Write-Note "testing git ls-remote in $($one.Name)..."
                # "could not reach origin" on its own sent someone asking what it
                # meant, fairly: two completely different faults both exit 128,
                # and one of them is caused by this check's own no-prompt policy.
                # git's stderr separates them, so say which it is.
                # 45s, not the 20s default: the credential manager's FIRST contact
                # with a repo URL does Azure DevOps endpoint discovery over the
                # network and can outrun 20s, and being killed mid-way costs the
                # real error message - which is the whole point of this check.
                # Once that has happened it settles to well under 10s.
                $r   = Invoke-ProbeCore 'git' @('-C', $one.FullName, 'ls-remote', '--heads', 'origin') 45
                $err = [string] $r.Err
                if ($r.Code -eq 0) { Write-Ok 'push endpoint reachable and credentials accepted' }
                elseif ($r.Code -eq 124) {
                    Write-Warn 'origin did not answer in time - almost always a missing stored credential'
                    Write-Wrapped ('Sign in once by hand and it is cached for good: git -C ' + $one.FullName + ' ls-remote origin') '    ' 'Yellow'
                }
                elseif ($r.Code -eq 127) {
                    Write-Bad 'git could not be started, so this says nothing at all about origin'
                    Write-Wrapped $err '    ' 'Yellow'
                    Write-Wrapped 'Install Git for Windows, or add its folder to PATH and open a new terminal.' '    ' 'Yellow'
                }
                elseif ($err -match '(?i)could not read Username|interactivity has been disabled|terminal prompts disabled|Authentication failed|authentication may be required') {
                    Write-Warn 'no saved credential for origin yet - and this check is not allowed to ask for one'
                    Write-Wrapped ('Nothing is broken: the probe deliberately never prompts, because a login prompt with nobody to answer it used to hang the whole wizard. Sign in once by hand and it is cached for good: git -C ' + $one.FullName + ' ls-remote origin') '    ' 'Yellow'
                    Write-Wrapped 'Do it before a real run - the runbook pushes a feature branch.' '    ' 'Yellow'
                }
                elseif ($err -match '(?i)does not appear to be a git repository|Could not read from remote repository') {
                    Write-Warn "$($one.Name) has no usable 'origin' remote - so this says nothing about your other repos"
                    Write-Wrapped ('Check with: git -C ' + $one.FullName + ' remote -v. Anything the runbook cloned has an origin; a folder copied in by hand may not.') '    ' 'Yellow'
                }
                else {
                    Write-Warn 'could not reach origin - the runbook pushes a branch, so fix this before a real run'
                    # Print what actually happened. The bare verdict sent someone
                    # asking what it meant, and the answer was in this text.
                    $lines = @($err -split "`n" | Where-Object { $_.Trim() } | Select-Object -First 3)
                    if ($lines.Count -gt 0) {
                        Write-Wrapped 'git said:' '    ' 'DarkGray'
                        foreach ($l in $lines) { Write-Wrapped $l.Trim() '      ' 'DarkGray' }
                    }
                    else { Write-Wrapped "git exited $($r.Code) without saying why" '    ' 'DarkGray' }
                }
            }
        }
    }
}

function Invoke-AtlassianSection {
    Write-Banner '2 of 6   Atlassian - the highest-value section'

    Write-FieldInfo -Name 'atlassian.email + atlassian.apiToken' `
        -What 'Your Atlassian account email and an API token. Used for direct REST calls to Jira, alongside the Atlassian MCP server.' `
        -Where 'Reading a ticket''s ATTACHMENT EVIDENCE - screenshots, PDFs, attached database backups. The MCP server is blocked on attachment content, so this token is the only route to it.' `
        -Without 'Any ticket whose evidence is a screenshot or an attached database cannot be analyzed. Those runs stop and post an Information Request instead of a root cause - which tends to be exactly the tickets most worth automating. Everything else still works.' `
        -Notes @(
            "Create a token at $script:AtlassianTokenUrl - Create API token, any label, then copy it immediately: Atlassian never shows it again.",
            'It is a token, not your password. Your account password will not work.',
            'Nothing you type here is displayed, logged, or sent anywhere except this config file.'
        )

    $node = Get-CfgNode 'atlassian'

    # Reuse a token they already have rather than making them mint another.
    if ($env:ATLASSIAN_API_TOKEN) {
        Write-Found 'ATLASSIAN_API_TOKEN is already set in your environment'
        if (Read-YesNo 'Use the environment variable instead of storing a token here?' $true) {
            $email = $env:ATLASSIAN_EMAIL
            if (-not $email) { $email = Get-GitEmail }
            $node | Add-Member -NotePropertyName 'email' -NotePropertyValue (Read-Text 'Atlassian email' $email) -Force
            Set-Status 'atlassian' 'configured' -Detail 'using ATLASSIAN_API_TOKEN from the environment'
            return
        }
    }
    $tokenFile = Join-Path $script:UserHome '.atlassian-token'
    if (Test-Path -LiteralPath $tokenFile) {
        Write-Found "a token file already exists: $tokenFile"
        Write-Note 'its contents are not read or displayed by this wizard'
        if (Read-YesNo 'Point the config at that file instead of storing a second copy?' $true) {
            $email = Get-GitEmail
            $node | Add-Member -NotePropertyName 'email'     -NotePropertyValue (Read-Text 'Atlassian email' $email) -Force
            $node | Add-Member -NotePropertyName 'tokenFile' -NotePropertyValue $tokenFile -Force
            $node | Add-Member -NotePropertyName 'apiToken'  -NotePropertyValue '' -Force
            Set-Status 'atlassian' 'configured' -Detail "tokenFile -> $tokenFile"
            return
        }
    }

    $emailDefault = [string] $node.email
    if (-not $emailDefault) { $emailDefault = Get-GitEmail }
    if ($emailDefault) { Write-Found "email from git config: $emailDefault" }

    $consequence = 'Tickets whose evidence is a screenshot or attached database cannot be analyzed; those runs stop at an Information Request instead of producing a root cause.'

    Write-Host ''
    while ($true) {
        if (-not (Read-YesNo 'Configure Atlassian now?' $true)) {
            if (Confirm-Skip 'atlassian' $consequence) { return }
            continue   # they declined the skip - go round again rather than falling through
        }

        $email = Read-Text 'Atlassian email' $emailDefault
        if (Test-IsBack $email) { return }

        $site = [string] $node.siteUrl
        if (-not $site) { $site = 'https://irely.atlassian.net' }
        $site = Read-Url 'Atlassian site URL' $site -Example 'https://irely.atlassian.net'
        if (Test-IsBack $site) { return }

        # Opened here rather than earlier: this is the moment the token is needed,
        # so the page is in front of them while the prompt is waiting. The guidance
        # goes BEFORE the question - printed after it, "say n if you already have
        # one" arrived a prompt too late to act on.
        Write-Wrapped 'The next question opens the Atlassian API-token page. On it: Create API token, give it any label, then copy the token straight away - Atlassian never shows it again. Answer n if you already have one.' '    ' 'DarkGray'
        Open-Url $script:AtlassianTokenUrl 'the Atlassian API-token page'

        Write-Host ''
        Write-Wrapped 'Paste the API token now. It will not be echoed.' '    ' 'DarkGray'
        $token = Read-Secret 'API token'
        if (Test-IsBack $token) { return }
        Show-SecretShape 'atlassian.apiToken' $token

        $node | Add-Member -NotePropertyName 'email'    -NotePropertyValue $email -Force
        $node | Add-Member -NotePropertyName 'apiToken' -NotePropertyValue $token -Force
        $node | Add-Member -NotePropertyName 'siteUrl'  -NotePropertyValue $site  -Force

        if (-not $token) {
            Write-Warn 'no token entered'
            if (Confirm-Skip 'atlassian' $consequence) { return }
            continue
        }
        if (-not (Read-YesNo 'Test it now?' $true)) {
            Set-Status 'atlassian' 'configured' -Detail 'not tested'
            return
        }
        if (Test-Atlassian $site $email $token) { return }

        $choice = Read-FailureChoice 'Atlassian'
        if ($choice -eq 'continue') { Write-Note 'kept as-is and recorded as failed - re-run with -Section atlassian any time'; return }
        if ($choice -eq 'skip') { if (Confirm-Skip 'atlassian' $consequence) { return } }
        # retry: values are still on screen as defaults, so a typo is one keystroke to fix
        $emailDefault = $email
    }
}

function Test-Atlassian {
    param([string] $Site, [string] $Email, [string] $Token)
    Write-Note "calling $Site/rest/api/3/myself ..."
    try {
        $pair  = "$($Email):$($Token)"
        $b64   = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        $hdr   = @{ Authorization = "Basic $b64"; Accept = 'application/json' }
        $r     = Invoke-RestMethod -Uri "$Site/rest/api/3/myself" -Headers $hdr -Method Get -TimeoutSec 20
        Write-Ok "authenticated as $($r.displayName)"
        Set-Status 'atlassian' 'verified' -Detail "authenticated as $($r.displayName)"
        return $true
    }
    catch {
        $msg = $_.Exception.Message
        Write-Bad "failed: $msg"
        if ($msg -match '401|403') {
            Write-Wrapped 'Most common causes: an account password was pasted instead of an API token, or the token picked up leading/trailing whitespace. The email must be the Atlassian account email.' '    ' 'Yellow'
        }
        elseif ($msg -match '404|could not be resolved|No such host') {
            Write-Wrapped 'That looks like the wrong site URL rather than a credential problem - check the host.' '    ' 'Yellow'
        }
        Set-Status 'atlassian' 'failed' -Detail 'authentication failed'
        return $false
    }
}

function Invoke-SqlSection {
    Write-Banner '3 of 6   SQL Server - for data-dependent tickets'

    Write-FieldInfo -Name 'sqlServer.server / instance / auth' `
        -What 'A SQL Server instance you control, onto which the runbook can restore a customer database.' `
        -Where 'Reproducing a symptom that lives in the DATA rather than the code: the runbook restores the database reported on the ticket, reproduces the defect, proves the fix against it, then rolls back. Also the Liquibase update and rollback confirmation.' `
        -Without 'Data-dependent tickets cannot be reproduced at all. They fall back to an Information Request, and any Liquibase confirmation is reported as NOT RUN.' `
        -Notes @(
            'Where several instances exist, prefer the NEWEST: a backup taken on a newer build cannot be restored onto an older one.',
            'For a tunnelled or port-forwarded instance the address is 127.0.0.1,<port> - comma not colon, and never localhost, which resolves to ::1 and times out.'
        )

    $node = Get-CfgNode 'sqlServer'

    Write-Note 'looking for installed instances...'
    $inst = Find-SqlInstances
    if ($inst) {
        foreach ($i in $inst) { Write-Found "$($i.Instance)  -  service $($i.Service), $($i.State)" }
    }
    else { Write-Warn 'no local SQL Server instance found in the registry' }

    $consequence = 'Data-dependent tickets cannot be reproduced; they fall back to an Information Request. Liquibase confirmation reports NOT RUN.'

    $default = [string] $node.server
    if (-not $default -and $inst) { $default = $inst[0].Address }
    if (-not $default) { $default = '.' }
    $userDefault = [string] $node.user

    Write-Host ''
    while ($true) {
        if (-not (Read-YesNo 'Configure SQL Server now?' $($inst.Count -gt 0))) {
            if (Confirm-Skip 'sqlServer' $consequence) { return }
            continue
        }

        $server = Read-Text 'Server (host, .\instance, or 127.0.0.1,<port> for a tunnel)' $default
        if (Test-IsBack $server) { return }
        $default = $server

        $node | Add-Member -NotePropertyName 'server'   -NotePropertyValue $server -Force
        $node | Add-Member -NotePropertyName 'instance' -NotePropertyValue '' -Force

        # Try integrated auth before asking for any password.
        Write-Host ''
        Write-Note 'trying Windows authentication first, so you may not need a password at all...'
        try {
            $v = Invoke-SqlScalar (New-SqlConnectionString $server 'windows' '' '') 'SELECT @@VERSION'
            Write-Ok 'Windows authentication works - no password needed, nothing to store, nothing to expire'
            Write-Note (($v -split "`n")[0].Trim())
            $node | Add-Member -NotePropertyName 'auth'     -NotePropertyValue 'windows' -Force
            $node | Add-Member -NotePropertyName 'user'     -NotePropertyValue '' -Force
            $node | Add-Member -NotePropertyName 'password' -NotePropertyValue '' -Force
            Set-Status 'sqlServer' 'verified' -Detail "$server, Windows auth"
            return
        }
        catch {
            Write-Warn 'Windows authentication did not work here, so a SQL login is needed'
            Write-Note $_.Exception.Message
        }

        $user = Read-Text 'SQL login name' $userDefault
        if (Test-IsBack $user) { return }
        $userDefault = $user

        $pw = Read-Secret 'SQL password'
        if (Test-IsBack $pw) { return }
        Show-SecretShape 'sqlServer.password' $pw

        $node | Add-Member -NotePropertyName 'auth'     -NotePropertyValue 'sql' -Force
        $node | Add-Member -NotePropertyName 'user'     -NotePropertyValue $user -Force
        $node | Add-Member -NotePropertyName 'password' -NotePropertyValue $pw -Force

        $failed = $false
        try {
            $v = Invoke-SqlScalar (New-SqlConnectionString $server 'sql' $user $pw) 'SELECT @@VERSION'
            Write-Ok 'connected'
            Write-Note (($v -split "`n")[0].Trim())
            Set-Status 'sqlServer' 'verified' -Detail "$server, SQL login $user"
            return
        }
        catch {
            $msg = $_.Exception.Message
            Write-Bad "could not connect: $msg"
            # Name the likely cause, so a retry is aimed rather than blind.
            if ($msg -match 'Login failed') {
                Write-Wrapped 'The server answered and rejected the credentials - so the host is right and the login name or password is wrong. Check the login name first; it is the easier of the two to mistype.' '    ' 'Yellow'
            }
            elseif ($msg -match 'network-related|not found or was not accessible|timeout|timed out') {
                Write-Wrapped 'The server never answered, so this is the address rather than the credentials. If it is tunnelled, check the rule above: 127.0.0.1,<port> - never localhost, which resolves to ::1 and times out exactly like a server being down.' '    ' 'Yellow'
            }
            Set-Status 'sqlServer' 'failed' -Detail 'connection failed'
            $failed = $true
        }

        if ($failed) {
            $choice = Read-FailureChoice 'SQL Server'
            if ($choice -eq 'continue') { Write-Note 'kept as-is and recorded as failed - re-run with -Section sql any time'; return }
            if ($choice -eq 'skip') { if (Confirm-Skip 'sqlServer' $consequence) { return } }
        }
    }
}

function Invoke-RestoreSection {
    Write-Banner '4 of 6   Restore location and disk space'

    Write-FieldInfo -Name 'sqlServer.restore.*' `
        -What 'Where a downloaded customer database is staged and restored, and the free-space floor below which a restore should not be attempted.' `
        -Where 'The restore step, whenever a ticket needs its customer database locally. Also decides whether the restored copy is dropped afterwards.' `
        -Without 'Restores land on whatever the instance defaults to - usually the system drive. That is how a developer machine runs out of disk in the middle of an analysis.' `
        -Notes @(
            'A restore needs room for the .bak AND the fully expanded data and log files at the same time. The .bak is much smaller than what it expands to, so free space merely exceeding the backup size is not evidence it will fit.',
            'i21 customer databases are routinely tens to hundreds of GB expanded.'
        )

    $sql = Get-CfgNode 'sqlServer'
    $node = Get-CfgSubNode $sql 'restore'

    Write-Note 'volumes on this machine:'
    $vols = Get-VolumeReport
    foreach ($v in $vols) { Write-Found "$($v.Drive)  $($v.FreeGB) GB free of $($v.TotalGB) GB" }

    $svc = Get-SqlServiceAccount
    foreach ($s in $svc) { Write-Note "$($s.Name) runs as $($s.Account) ($($s.State))" }

    Write-Host ''
    if (-not (Read-YesNo 'Configure restore locations now?' $true)) {
        Confirm-Skip 'sqlServer.restore' 'Restores fall back to the instance default paths, usually on the system drive, with no free-space check first.' | Out-Null
        return
    }

    $roomiest = 'C:'
    if ($vols) { $roomiest = $vols[0].Drive }
    $stageDefault = [string] $node.backupStagingDirectory
    if (-not $stageDefault) { $stageDefault = "$roomiest\SQLBackups" }

    $stage = Read-Text 'Backup staging directory' $stageDefault
    if (-not (Test-Path -LiteralPath $stage)) {
        if (Read-YesNo "Create $stage ?" $true) { New-Item -ItemType Directory -Path $stage -Force | Out-Null; Write-Ok 'created' }
    }
    $node | Add-Member -NotePropertyName 'backupStagingDirectory' -NotePropertyValue $stage -Force

    # Offer the instance's own defaults rather than inventing paths.
    $dataDefault = [string] $node.dataDirectory
    $logDefault  = [string] $node.logDirectory
    if ($sql.server) {
        $cs = New-SqlConnectionString ([string] $sql.server) ([string] $sql.auth) ([string] $sql.user) ([string] $sql.password)
        $p = Get-SqlDefaultPaths $cs
        if ($p) {
            Write-Found "instance default data path: $($p.Data)"
            Write-Found "instance default log path:  $($p.Log)"
            if (-not $dataDefault) { $dataDefault = $p.Data }
            if (-not $logDefault)  { $logDefault  = $p.Log }
        }
    }
    Write-Note 'blank is fine for these two - it means "use the instance defaults"'
    $node | Add-Member -NotePropertyName 'dataDirectory' -NotePropertyValue (Read-Text 'Data (.mdf) directory' $dataDefault -AllowEmpty) -Force
    $node | Add-Member -NotePropertyName 'logDirectory'  -NotePropertyValue (Read-Text 'Log (.ldf) directory'  $logDefault  -AllowEmpty) -Force

    $floorDefault = 75
    if ($node.minimumFreeSpaceGB) { $floorDefault = [int] $node.minimumFreeSpaceGB }
    $floor = [int] (Read-Text 'Minimum free space before a restore is attempted (GB)' "$floorDefault")
    $node | Add-Member -NotePropertyName 'minimumFreeSpaceGB' -NotePropertyValue $floor -Force

    Write-Host ''
    Write-Wrapped 'Keeping restored databases after a run is off by default. They are large, they accumulate, and a stale copy is a real hazard: a later run can silently analyze last month''s data and reach a confident wrong conclusion.' '    ' 'DarkGray'
    $node | Add-Member -NotePropertyName 'keepRestoredDatabases' -NotePropertyValue (Read-YesNo 'Keep restored databases after a run?' $false) -Force

    # Report the space against the floor, and be blunt when it does not clear.
    Write-Host ''
    $free = Get-FreeGBForPath $stage
    $detail = "$stage"
    if ($null -ne $free) {
        $detail = "$stage, $free GB free, floor $floor GB"
        if ($free -lt $floor) {
            Write-Bad "$stage has $free GB free, below your $floor GB floor - a restore is not ready to run here"
            Write-Wrapped 'Point this at a roomier volume, or lower the floor if you know the databases you work with are small.' '    ' 'Yellow'
            Set-Status 'sqlServer.restore' 'partial' -Detail "$detail - BELOW FLOOR"
        }
        else {
            Write-Ok "$stage has $free GB free, clearing your $floor GB floor"
            $dataDir = [string] $node.dataDirectory
            # Only compare volumes when both look like rooted Windows paths.
            # Empty / "use instance default" / a mistyped skip token must not
            # reach Split-Path -Qualifier, which throws on anything without a drive.
            if ($dataDir -and $dataDir -match '^[A-Za-z]:' -and $stage -match '^[A-Za-z]:') {
                try {
                    if ((Split-Path -Qualifier $dataDir) -eq (Split-Path -Qualifier $stage)) {
                        Write-Warn 'staging and data are on the same volume, so a restore needs the SUM of both, not the larger'
                    }
                } catch { }
            }
            Set-Status 'sqlServer.restore' 'configured' -Detail $detail
        }
    }
    else { Set-Status 'sqlServer.restore' 'configured' -Detail $detail }
}

function Invoke-ServersSection {
    Write-Banner '5 of 6   Servers where databases are already restored'

    Write-FieldInfo -Name 'sqlServer.knownServers[]' `
        -What 'Servers where customer databases have already been restored by someone else - typically QA boxes, often reached through an SSH tunnel.' `
        -Where 'Before downloading anything. When a ticket or its helpdesk note says "restored to QA-SQL-03 as CustomerDB_2026", the runbook matches that name here and uses the existing database in place.' `
        -Without 'The run downloads and restores its own copy. Correct, but slow and disk-hungry. This is the biggest single time saver in the config.' `
        -Notes @(
            'Candidates are read from the LocalForward lines in your ~/.ssh/config - topology only, never keys or passwords.',
            'A read-only login is enough here: the database is already restored and the runbook only reads it. That keeps a stored password harmless on a shared server.',
            'One login normally covers every QA box, so the credentials are asked once and applied to all of them. Answer "ask me separately" only when they genuinely differ.',
            'The servers can be added in one go under the names your ssh config already uses - which is what tickets call them, since both come from the same hostname. Decline that only if a box is referred to by some other name, and you will be asked per server.'
        )

    $sql = Get-CfgNode 'sqlServer'

    Write-Note 'reading ~/.ssh/config for SQL tunnels...'
    $tunnels = Get-SshTunnels
    $listening = Get-ListeningLoopbackPorts

    if (-not $tunnels) {
        Write-Warn 'no LocalForward entries found'
    }
    else {
        foreach ($t in $tunnels) {
            $up = 'tunnel down'
            if ($listening -contains [int] $t.LocalPort) { $up = 'tunnel UP' }
            Write-Found "$($t.RemoteHost) via $($t.Address)  (ssh host $($t.SshHost), $up)"
        }
    }

    Write-Host ''
    if (-not (Read-YesNo 'Add known servers now?' $($tunnels.Count -gt 0))) {
        Confirm-Skip 'sqlServer.knownServers' 'A server named on a ticket cannot be resolved, so every run downloads and restores its own copy of the database.' | Out-Null
        return
    }

    # Being asked for the same read-only login once per QA box is the most
    # repetitive stretch of this wizard, and the answer is nearly always the
    # same for all of them - including, often, the login already given in
    # section 3. So the credential question is asked once, up front, and only
    # falls back to per-server when they really do differ.
    $shared = $null

    # A re-run usually needs no typing at all: when every entry already in the
    # config shares one login, that is the answer, and it beats section 3's -
    # these boxes are typically read-only accounts, not the admin login used to
    # restore onto your own instance.
    $existing = @()
    if ($sql.PSObject.Properties.Name -contains 'knownServers') { $existing = @($sql.knownServers | Where-Object { $_ }) }
    $existingUser = ''
    if ($existing.Count -gt 0) {
        $sqlAuthEntries = @($existing | Where-Object { $_.auth -eq 'sql' -and $_.user })
        if ($sqlAuthEntries.Count -eq $existing.Count) {
            $distinct = @($sqlAuthEntries | ForEach-Object { [string] $_.user } | Sort-Object -Unique)
            if ($distinct.Count -eq 1) { $existingUser = $distinct[0] }
        }
    }

    $opts = @()
    if ($existingUser) {
        $opts += @{ Key = 'k'; Label = "keep $existingUser - already used by all $($existing.Count) servers in your config" }
    }
    if ($sql.auth -eq 'sql' -and $sql.user -and $sql.user -ne $existingUser) {
        $opts += @{ Key = 'r'; Label = "reuse the SQL login from section 3 ($($sql.user)) for all of them" }
    }
    $opts += @{ Key = '1'; Label = 'one SQL login, used for every server here' }
    $opts += @{ Key = '2'; Label = 'Windows authentication for every server here' }
    $opts += @{ Key = '3'; Label = 'ask me separately for each server' }

    Write-Host ''
    Write-Host '  Credentials for these servers:' -ForegroundColor White
    $mode = Read-Option $opts $opts[0].Key

    if ($mode -eq 'k') {
        $src = @($existing | Where-Object { [string] $_.user -eq $existingUser })[0]
        $shared = @{ auth = 'sql'; user = $existingUser; password = [string] $src.password }
        Write-Ok "$existingUser and its stored password will be used for every server below - nothing to retype"
    }
    elseif ($mode -eq 'r') {
        $shared = @{ auth = 'sql'; user = [string] $sql.user; password = [string] $sql.password }
        Write-Ok "$($sql.user) will be used for every server added below"
    }
    elseif ($mode -eq '1') {
        $u = Read-Text 'SQL login for all of them' ([string] $sql.user)
        if (Test-IsBack $u) { return }
        $pw = Read-Secret 'SQL password for all of them'
        if (Test-IsBack $pw) { return }
        Show-SecretShape 'knownServers shared password' $pw
        $shared = @{ auth = 'sql'; user = $u; password = $pw }
    }
    elseif ($mode -eq '2') {
        $shared = @{ auth = 'windows'; user = ''; password = '' }
        Write-Note 'note: integrated auth usually fails through a tunnel - Kerberos cannot resolve the SPN via 127.0.0.1'
    }

    # Two prompts per tunnel - "add this one?" then "what is it called?" - was the
    # longest stretch of typing left in the wizard, and on a box with a dozen
    # forwards it is a dozen Enters to accept defaults that were already right.
    # Tickets name these servers exactly as ~/.ssh/config does, because both come
    # from the same hostname. So offer the bulk answer first and keep the
    # per-server walk for the real exception: a box tickets call something else.
    $bulk = $false
    if ($tunnels.Count -gt 0) {
        Write-Host ''
        Write-Wrapped 'Tickets normally name these boxes exactly as your ssh config does, so the names found above can be used as they are.' '    ' 'DarkGray'
        $bulk = Read-YesNo "Add all $($tunnels.Count) of them under those names?" $true
    }

    $entries = @()
    foreach ($t in $tunnels) {
        Write-Host ''
        Write-Host "  $($t.RemoteHost)  ->  $($t.Address)" -ForegroundColor White

        $name = [string] $t.RemoteHost
        if ($bulk) { Write-Ok "adding as $name" }
        else {
            if (-not (Read-YesNo '  Add this one?' $true)) { continue }
            $typed = Read-Text 'Server name as tickets refer to it' $t.RemoteHost
            # Unchecked, "!b" typed here was stored as the server's name.
            if (Test-IsBack $typed) { return }
            $name = $typed
        }

        $e = [ordered] @{
            name    = $name
            aliases = @($t.SshHost)
            address = $t.Address
            sshHost = $t.SshHost
        }
        if ($shared) {
            $e.auth = $shared.auth; $e.user = $shared.user; $e.password = $shared.password
        }
        elseif (Read-YesNo 'Use Windows authentication for it?' $false) {
            $e.auth = 'windows'; $e.user = ''; $e.password = ''
            Write-Note 'note: integrated auth usually fails through a tunnel - Kerberos cannot resolve the SPN via 127.0.0.1'
        }
        else {
            $e.auth = 'sql'
            $e.user = Read-Text 'SQL login (blank to add credentials later)' '' -AllowEmpty
            if ($e.user) { $e.password = Read-Secret 'SQL password'; Show-SecretShape "$($e.name) password" $e.password }
            else { $e.password = ''; Write-Note 'left without credentials - the run can still resolve the name and say what it needs' }
        }
        $entries += ,$e
    }

    while (Read-YesNo 'Add another server by hand?' $false) {
        $e = [ordered] @{
            name    = (Read-Text 'Server name' '')
            aliases = @()
            address = (Read-Text 'Address (host, or 127.0.0.1,<port> for a tunnel)' '')
            sshHost = ''
            auth    = 'sql'
        }
        if ($shared) {
            $e.auth = $shared.auth; $e.user = $shared.user; $e.password = $shared.password
            Write-Note 'using the credentials chosen for all servers above'
        }
        else {
            $e.user = Read-Text 'SQL login (blank for none)' '' -AllowEmpty
            if ($e.user) { $e.password = Read-Secret 'SQL password' } else { $e.password = '' }
        }
        $entries += ,$e
    }

    if ($entries.Count -eq 0) {
        Confirm-Skip 'sqlServer.knownServers' 'A server named on a ticket cannot be resolved, so every run downloads and restores its own copy.' | Out-Null
        return
    }

    $sql | Add-Member -NotePropertyName 'knownServers' -NotePropertyValue $entries -Force

    # Verify each one. An entry that does not answer is worse than no entry at all.
    Write-Host ''
    Write-Note 'testing each entry - an unreachable entry is worse than none, because a run will think it has a shortcut'
    $good = 0; $down = 0
    foreach ($e in $entries) {
        try {
            $cs = New-SqlConnectionString $e.address $e.auth $e.user $e.password 6
            $v = Invoke-SqlScalar $cs 'SELECT @@VERSION' 6
            Write-Ok "$($e.name) - connected"
            $good++
        }
        catch {
            if ($listening -and $e.address -match '127\.0\.0\.1,(\d+)' -and -not ($listening -contains [int] $Matches[1])) {
                Write-Warn "$($e.name) - tunnel is not up right now. Entry kept; that is the normal resting state."
                $down++
            }
            else {
                Write-Warn "$($e.name) - could not connect: $($_.Exception.Message)"
                $down++
            }
        }
    }
    if ($down -eq 0) { Set-Status 'sqlServer.knownServers' 'verified' -Detail "$good entries, all reachable" }
    else { Set-Status 'sqlServer.knownServers' 'partial' -Detail "$good reachable, $down unreachable (tunnels may be down)" }
}

function Invoke-SshSection {
    Write-Banner '6 of 6   Passwordless SSH for the tunnels'

    Write-FieldInfo -Name 'SSH key authentication' `
        -What 'A key so opening a tunnel to the jump host never prompts for a password. Nothing about this is stored in the config file - it lives in ~/.ssh.' `
        -Where 'Any run that reaches a tunnelled server. Only the tunnel: SSH carries no identity into SQL Server, which still authenticates on its own.' `
        -Without 'Every tunnel asks for your password, which no unattended or scheduled run can answer.' `
        -Notes @(
            'A passwordless SSH setup does NOT remove the need for a SQL login. They are separate layers.',
            'This section runs commands in YOUR terminal, so the prompts work normally - which is exactly what an AI agent cannot do.'
        )

    $tunnels = Get-SshTunnels
    if (-not $tunnels) {
        Write-Note 'no SSH tunnels configured, so there is nothing to do here'
        Set-Status 'ssh' 'not-applicable' -Detail 'no tunnels in ~/.ssh/config' -Kind 'not-applicable'
        return
    }

    $sshDir = Join-Path $script:UserHome '.ssh'
    $keys = @()
    if (Test-Path -LiteralPath $sshDir) {
        $keys = @(Get-ChildItem -LiteralPath $sshDir -File | Where-Object { $_.Name -match '^id_' -and $_.Extension -ne '.pub' })
    }
    foreach ($k in $keys) { Write-Found "existing key: $($k.Name)" }

    Write-Host ''
    if (-not (Read-YesNo 'Set up key-based SSH now?' $($keys.Count -eq 0))) {
        Confirm-Skip 'ssh' 'Tunnels prompt for a password each time, so unattended and scheduled runs cannot open them.' | Out-Null
        return
    }

    $keyPath = Join-Path $sshDir 'id_i21_tunnel'
    if ($keys.Count -gt 0) {
        Write-Host ''
        Write-Wrapped 'You can reuse an existing key, or generate one dedicated to these tunnels. A dedicated key can be revoked on its own if a machine is lost, and nothing else depends on it.' '    ' 'DarkGray'
        $useExisting = Read-YesNo 'Reuse an existing key?' $true
        if ($useExisting) { $keyPath = (Read-Text 'Key path' $keys[0].FullName) }
    }

    if (-not (Test-Path -LiteralPath $keyPath)) {
        Write-Host ''
        Write-Wrapped 'About to generate a key. You will be asked for a passphrase - both answers are reasonable. WITH a passphrase the key is encrypted at rest, and because the Windows agent service persists keys across reboots you realistically type it once, ever. WITHOUT one, the key file itself is the credential: anything that can read it can reach that host, but unattended runs always work.' '    '
        Write-Host ''
        Write-Note "running: ssh-keygen -t ed25519 -f `"$keyPath`" -C `"i21 tunnels`""
        & ssh-keygen -t ed25519 -f $keyPath -C 'i21 tunnels'
        $genCode = $LASTEXITCODE
        if (-not (Test-Path -LiteralPath $keyPath)) {
            Write-Bad "key generation did not produce a key (ssh-keygen exited $genCode)"
            Write-Wrapped 'Its output is above. The usual causes are no write access to ~/.ssh, or the passphrase prompts being cancelled.' '    ' 'Yellow'
            return
        }
        Write-Ok "key created: $keyPath"
    }

    # Load it into the agent so the passphrase is asked once rather than per connection.
    $svc = Get-Service -Name 'ssh-agent' -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.StartType -eq 'Disabled') {
            Write-Warn 'the OpenSSH Authentication Agent service is disabled'
            if (Read-YesNo 'Enable and start it? (needs administrator)' $true) {
                try { Set-Service -Name ssh-agent -StartupType Automatic; Start-Service ssh-agent; Write-Ok 'agent running' }
                catch { Write-Warn "could not change the service - run this wizard as administrator, or do it by hand: $($_.Exception.Message)" }
            }
        }
        elseif ($svc.Status -ne 'Running') {
            try { Start-Service ssh-agent; Write-Ok 'agent started' }
            catch { Write-Warn "could not start the agent: $($_.Exception.Message)" }
        }
        else { Write-Ok 'ssh-agent is running' }
    }
    if (Read-YesNo 'Load the key into the agent now?' $true) {
        # Left interactive on purpose - it may ask for the passphrase - so only
        # the exit code is inspected. It used to be ignored entirely, and a
        # refused key looked identical to a loaded one.
        & ssh-add $keyPath
        if ($LASTEXITCODE -eq 0) { Write-Ok 'key loaded into the agent' }
        else { Write-Warn "ssh-add exited $LASTEXITCODE - the key is NOT in the agent, so every connection will ask for the passphrase (ssh-add -l lists what is loaded)" }
    }

    # Installing the public key needs their password once. Prompts work here, so run it.
    Write-Host ''
    Write-Wrapped 'Next the public key has to be installed on the jump host. That needs your existing SSH password ONCE - and it is the last time. It is typed straight to ssh; this wizard never sees it.' '    '
    # One account normally spans every jump host, so ask for the username once
    # rather than once per host. Only worth offering when there is more than one.
    $sshAliases = @($tunnels | Sort-Object SshHost -Unique)

    # An authorized_keys file belongs to an ACCOUNT ON A MACHINE, not to an ssh
    # alias. Six aliases that all carry `HostName rdg.irely.com` and the same
    # `User` are one destination wearing six names, so installing per alias asked
    # for the same password six times and wrote the same key to the same file six
    # times. Collapse them and do it once.
    $groups = @()
    foreach ($h in $sshAliases) {
        $real = [string] $h.RealHost
        if (-not $real) { $real = [string] $h.SshHost }
        $key  = ('{0}|{1}' -f $real.ToLower(), ([string] $h.SshUser).ToLower())
        $g = @($groups | Where-Object { $_.Key -eq $key })
        if ($g.Count -gt 0) { $g[0].Aliases += $h.SshHost }
        else {
            $groups += [pscustomobject] @{
                Key      = $key
                Rep      = $h              # the alias used to connect
                RealHost = $real
                Aliases  = @($h.SshHost)
            }
        }
    }

    if ($groups.Count -lt $sshAliases.Count) {
        Write-Host ''
        Write-Ok ("$($sshAliases.Count) tunnel aliases resolve to $($groups.Count) actual host(s) - the key is installed once per host, not once per alias")
        foreach ($g in $groups) {
            Write-Note ("$($g.RealHost)  <-  " + (($g.Aliases | Sort-Object) -join ', '))
        }
    }

    $sshHosts = @($groups | ForEach-Object { $_.Rep })

    # Whatever ~/.ssh/config already declares beats $env:USERNAME, which is the
    # Windows account and frequently nothing to do with the jump host.
    $cfgUsers = @($sshHosts | Where-Object { $_.SshUser } | ForEach-Object { [string] $_.SshUser } | Sort-Object -Unique)
    $sharedDefault = $env:USERNAME
    if ($cfgUsers.Count -eq 1) {
        $sharedDefault = $cfgUsers[0]
        Write-Found "~/.ssh/config already names '$sharedDefault' on every one of these hosts"
    }

    $sharedSshUser = ''
    if ($sshHosts.Count -gt 1) {
        Write-Host ''
        Write-Note ("$($sshHosts.Count) hosts to install on: " + (($sshHosts.SshHost) -join ', '))
        if (Read-YesNo 'Use the same SSH username on all of them?' $true) {
            $sharedSshUser = Read-Text 'SSH username for all of them - the jump-host account, NOT a SQL login' $sharedDefault
            if (Test-IsBack $sharedSshUser) { return }
        }
    }

    # A REUSED private key may have no .pub file beside it, and nothing earlier
    # notices: the key list only matches id_* excluding .pub, and ssh-add works
    # from the private key alone - it reports "Identity added" either way. The
    # install then had nothing to send, and the old command answered 0 to an
    # empty key, so it printed "public key installed" having written nothing.
    if (-not (Test-Path -LiteralPath "$keyPath.pub")) {
        Write-Warn "there is no public key beside $keyPath"
        Write-Wrapped 'ssh-add does not need one, which is why nothing has complained until now - but installing on a host does need it.' '    ' 'Yellow'
        if (Read-YesNo 'Derive it from the private key now?' $true) {
            & ssh-keygen -y -f $keyPath | Set-Content -LiteralPath "$keyPath.pub" -Encoding ascii
            if (Test-Path -LiteralPath "$keyPath.pub") { Write-Ok "wrote $keyPath.pub" }
            else { Write-Bad "ssh-keygen -y did not produce a public key (exit $LASTEXITCODE)" }
        }
    }

    $pub = ''
    if (Test-Path -LiteralPath "$keyPath.pub") { $pub = ((Get-Content -LiteralPath "$keyPath.pub" -Raw) -replace '\s+$', '') }
    if (-not $pub) {
        Write-Bad "no usable public key at $keyPath.pub - there is nothing to install, so this section stops here"
        Write-Wrapped ('Create it and re-run with -Section ssh:  ssh-keygen -y -f "' + $keyPath + '" > "' + $keyPath + '.pub"') '    ' 'Yellow'
        Set-Status 'ssh' 'failed' -Detail 'public key file missing beside the private key'
        return
    }

    foreach ($t in $sshHosts) {
        Write-Host ''
        if (-not (Read-YesNo "Install the key on '$($t.SshHost)' now?" $true)) { continue }

        # Costs no password - the banner is pre-auth - and decides which install
        # command can actually run over there.
        $kind = Get-SshRemoteKind $t.SshHost
        if ($kind -eq 'windows') { Write-Note "$($t.SshHost) runs OpenSSH for Windows, so the cmd.exe form of the install is used" }
        elseif ($kind -eq 'unknown') {
            Write-Note "could not read $($t.SshHost)'s SSH banner - assuming a POSIX remote, which may be the wrong install command"
            if ($script:LastBannerErr) { Write-Wrapped $script:LastBannerErr '    ' 'DarkGray' }
        }

        $userDefault = $sharedSshUser
        if (-not $userDefault) { $userDefault = [string] $t.SshUser }
        if (-not $userDefault) { $userDefault = $env:USERNAME }

        $user  = $userDefault
        $asked = [bool] $sharedSshUser   # already answered for every host

        # A wrong username used to be unrecoverable: the prompt offered !b and
        # ignored it, the ssh ran on whatever was typed, and the loop moved to
        # the next host. Now it is confirmed before running and retryable after.
        while ($true) {
            if (-not $asked) {
                $user = Read-Text "SSH username on $($t.SshHost) - the jump-host account, NOT a SQL login" $userDefault
                if (Test-IsBack $user) { Write-Note "left $($t.SshHost) alone - nothing was run against it"; break }
            }
            $asked = $false   # a retry always asks

            $target = "$user@$($t.SshHost)"
            Write-Host ''
            Write-Note "about to install the public key with: ssh $target"
            if (-not (Read-YesNo "Is $target the right account?" $true)) {
                $userDefault = $user
                continue
            }

            if ($kind -eq 'windows') {
                # cmd.exe has no mkdir -p, no cat and no chmod, so the key goes
                # inline rather than down stdin - there is nothing over there to
                # read stdin with.
                # `md ... 2>nul &` and NOT `if not exist ... md ... & ...`:
                # cmd binds the & INSIDE the if, so on any host that already had
                # a .ssh directory the echo never ran - and the whole line still
                # exited 0, so it reported the key installed when it had written
                # nothing at all. Verified: two runs of the if-form leave one
                # line, two runs of this form leave two.
                # findstr || echo makes it idempotent: this wizard is meant to be
                # re-run (-Resume, -Section ssh), and a plain append stacks the
                # same key every time.
                # NOT ONE DOUBLE QUOTE in this command, deliberately.
                #
                # PowerShell wraps a native-exe argument in its own pair of
                # double quotes and does NOT escape any inner ones, so a command
                # containing them shatters on the way to ssh: measured, the
                # single string  findstr /c:"<key with spaces>" "<path>"  arrived
                # as three arguments split at the inner quotes. ssh rejoins them
                # with spaces, the remote loses the quoting, and findstr ends up
                # searching for just  ssh-ed25519  - which matches ANY existing
                # key. It then reports "found", the || skips the append, the
                # trailing check also reports found, and the whole thing exits 0
                # having written nothing. On a host whose authorized_keys was
                # empty it appended correctly, which is why every earlier test
                # passed; it only silently no-ops on a file that already holds a
                # key, which is every real second run.
                #
                # So: search on the base64 field alone - one token, no spaces,
                # nothing to quote - and leave the paths bare. A profile path
                # containing a space would break the bare paths, but the trailing
                # findstr then fails and the run says so, instead of lying.
                $b64 = ($pub -split '\s+')[1]
                $akw = '%USERPROFILE%\.ssh\authorized_keys'
                # `|| exit /b 13` distinguishes "cannot write the file" from
                # "wrote it but it is not there", which are different problems
                # with different owners. Measured: a denied redirect gives 13, a
                # good one gives 0.
                $remote = 'md %USERPROFILE%\.ssh 2>nul & (findstr /c:' + $b64 + ' ' + $akw + ' >nul 2>&1 || (echo ' + $pub + '>>' + $akw + ' || exit /b 13)) & findstr /c:' + $b64 + ' ' + $akw + ' >nul 2>&1'
                & ssh $target $remote
            }
            else {
                # Also quote-free, for the reason spelled out in the Windows
                # branch: the previous form used "$k" and lost its quoting in
                # transit. Idempotence comes from sort -u instead of a grep of a
                # quoted variable, and the trailing grep -qF on the bare base64
                # token makes the exit code mean "the key is in the file now".
                # chmod matters: sshd refuses keys when ~/.ssh or authorized_keys is group/world-writable.
                $b64 = ($pub -split '\s+')[1]
                Get-Content -LiteralPath "$keyPath.pub" | & ssh $target ('mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && sort -u -o ~/.ssh/authorized_keys ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; grep -qF ' + $b64 + ' ~/.ssh/authorized_keys')
            }

            # 255 is ssh's own failure - host, username or password. Anything
            # else non-zero came back FROM the remote, which means the login
            # worked and only the command failed. Reporting the second as the
            # first is what sent someone re-checking a correct password.
            $code = $LASTEXITCODE
            $installed = ($code -eq 0)
            $authFailed = ($code -eq 255)
            if ($installed) { Write-Ok 'public key installed - and confirmed present in authorized_keys' }
            elseif ($authFailed) { Write-Warn 'ssh could not connect or authenticate - that is the host, the username or the password' }
            elseif ($code -eq 13) {
                Write-Bad "signed in fine, but this account may not write its own authorized_keys on $($t.SshHost)"
                Write-Wrapped 'Nothing about your login is wrong, and no retry will help: the file grants this account Read only. Check it with:  icacls "%USERPROFILE%\.sshuthorized_keys"  - if your name shows (R) rather than (M) or (F), an administrator on that host has to append the key for you, or grant you Modify.' '    ' 'Yellow'
                Write-Wrapped 'If you OWN the file you can repair it yourself:  icacls "%USERPROFILE%\.sshuthorized_keys" /grant %USERNAME%:M  - dir /q shows the owner.' '    ' 'Yellow'
                Set-Status 'ssh' 'failed' -Detail "authorized_keys not writable by the account on $($t.SshHost)" -Consequence 'Tunnels keep asking for a password, so unattended runs cannot open them.'
            }
            else { Write-Warn "signed in fine, but the key is NOT in authorized_keys afterwards (exit $code) - so this is NOT your username or password" }

            # Verify the account that was actually used. Testing the bare host
            # would fall back to whatever ~/.ssh/config says and could report
            # success for an account this run never touched.
            Write-Note 'verifying with BatchMode, which disables prompts entirely...'
            # `exit 0`, not `true`: true is a POSIX command that does not exist
            # on a Windows remote, where cmd.exe answers "'true' is not
            # recognized" and exits 1 - so a perfectly working key was reported
            # as "key auth not working yet". `exit` is a builtin in both sh and
            # cmd. It has to be two argv elements, because a single 'exit 0'
            # gets quoted as one token and cmd then looks for a program by that
            # name. Verified against a live Windows jump host.
            $v = Invoke-ProbeCore 'ssh' @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', $target, 'exit', '0')
            if ($v.Code -eq 0) {
                $g = @($groups | Where-Object { $_.Rep.SshHost -eq $t.SshHost })
                $covers = ''
                if ($g.Count -gt 0 -and $g[0].Aliases.Count -gt 1) {
                    $covers = ' - covers ' + (($g[0].Aliases | Sort-Object) -join ', ')
                }
                Write-Ok "$($t.SshHost) - passwordless as $user, verified$covers"
                Set-Status 'ssh' 'verified' -Detail "key auth to $target$covers"
                break
            }

            Write-Warn "$($t.SshHost) - key auth not working yet. Check: agent running, key loaded (ssh-add -l), public key present in authorized_keys."

            # ssh's own words beat any checklist here: "Permission denied
            # (publickey)", "Host key verification failed" and "Connection timed
            # out" send you to three different places, and the verdict alone
            # sent someone re-checking a password that was never wrong.
            if ($v.Code -eq 127) { Write-Wrapped $v.Err '    ' 'Yellow' }
            elseif ($v.Code -eq 124) { Write-Wrapped 'ssh did not answer inside the timeout - so this is reachability, not the key' '    ' 'DarkGray' }
            else {
                $sshSaid = @($v.Err -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^\s*debug\d' } | Select-Object -First 3)
                if ($sshSaid.Count -gt 0) {
                    Write-Wrapped 'ssh said:' '    ' 'DarkGray'
                    foreach ($l in $sshSaid) { Write-Wrapped $l.Trim() '      ' 'DarkGray' }
                }
                else { Write-Wrapped "ssh exited $($v.Code) without saying why" '    ' 'DarkGray' }
            }
            if ($kind -eq 'windows') {
                Write-Wrapped 'On a Windows host there are two more rules. sshd reads an ADMINISTRATOR account''s keys from %ProgramData%\ssh\administrators_authorized_keys, not from the profile - so for an admin account the profile copy is simply never looked at. And it refuses any authorized_keys that other users can write.' '    ' 'Yellow'
                Write-Wrapped 'If this account is an administrator, append the key there instead and repair the ACL: icacls "%ProgramData%\ssh\administrators_authorized_keys" /inheritance:r /grant "SYSTEM:F" /grant "BUILTIN\Administrators:F"' '    ' 'Yellow'
            }
            Set-Status 'ssh' 'partial' -Detail "key installed but BatchMode check failed ($target)"

            # Only an ssh-level failure points at the username. A remote command
            # that failed, or a key that did not take, will not be fixed by
            # retyping the account, so do not invite that by default.
            Write-Host ''
            if ($code -eq 13) { break }   # a refused write is not a username problem
            if (-not (Read-YesNo "Try $($t.SshHost) again with a different username?" $authFailed)) { break }
            $userDefault = $user
        }
    }
}

# Walks redirects by hand, re-sending the Cookie header on every hop, and reports
# what each hop revealed. Written against HttpWebRequest rather than
# Invoke-WebRequest because this needs to see the redirect responses themselves,
# and `Invoke-WebRequest -MaximumRedirection 0` throws "Operation is not valid due
# to the current state of the object" on Windows PowerShell 5.1 - the only shell
# some of the machines this package targets have.
#
#   Final   - the URL the walk ended on (a login bounce shows up here)
#   Cleared - cookies the server sent back empty with an expiry in the past, which
#             is its way of saying it read the auth ticket and rejected it
# ---------------------------------------------------------------- browser capture
#
# Reads the cookies straight out of a real browser over the Chrome DevTools
# Protocol, so nobody has to find a Network tab, choose a cURL flavour, or paste a
# credential anywhere. It adds no dependency: every Windows machine already has
# Edge, and CDP is spoken by any Chromium build.
#
# It runs against a DEDICATED profile directory, not the everyday one. Two reasons:
# attaching to a browser that is already running cannot enable the debugging port,
# and pointing --user-data-dir at a live profile risks locking or corrupting it.
# The dedicated profile persists, so the federated Azure AD sign-in is interactive
# exactly once - after that the session is picked up silently, which is the whole
# point of doing it this way.

# Any Chromium-family browser will do - CDP is not an Edge feature. Edge is only
# tried first because it is the one guaranteed to be on a Windows box. Firefox is
# NOT usable here: it speaks its own remote protocol, not CDP.
#
# $Preferred wins outright when given (helpdesk.browserPath in the config), so a
# machine with several browsers can be pinned to one - otherwise the search order
# below decides, and "it picked the wrong browser" has no remedy.
function Get-ChromiumPath {
    param([string] $Preferred)

    if ($Preferred) {
        if (Test-Path -LiteralPath $Preferred) { return $Preferred }
        Write-Warn "helpdesk.browserPath is set but not found: $Preferred"
    }

    $rel = @(
        'Microsoft\Edge\Application\msedge.exe'
        'Google\Chrome\Application\chrome.exe'
        'BraveSoftware\Brave-Browser\Application\brave.exe'
        'Vivaldi\Application\vivaldi.exe'
        'Chromium\Application\chrome.exe'
    )
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA) | Where-Object { $_ }
    foreach ($r in $rel) {
        foreach ($root in $roots) {
            $p = Join-Path $root $r
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }

    foreach ($exe in @('msedge.exe', 'chrome.exe', 'brave.exe', 'vivaldi.exe')) {
        foreach ($root in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths',
                            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths')) {
            try {
                $p = (Get-ItemProperty -Path (Join-Path $root $exe) -ErrorAction Stop).'(default)'
                if ($p -and (Test-Path -LiteralPath $p)) { return $p }
            } catch { }
        }
    }
    return ''
}

function Get-FreeTcpPort {
    $l = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
    $l.Start()
    $port = $l.LocalEndpoint.Port
    $l.Stop()
    return $port
}

# One request/response over the DevTools socket. CDP interleaves events with
# replies on the same socket, so this reads until it sees the reply carrying our
# own id rather than trusting the first frame back.
function Invoke-CdpCommand {
    param([string] $WsUrl, [string] $Method, $Params, [int] $TimeoutSec = 25)

    $ws  = New-Object Net.WebSockets.ClientWebSocket
    $cts = New-Object Threading.CancellationTokenSource
    $cts.CancelAfter([TimeSpan]::FromSeconds($TimeoutSec))
    try {
        $ws.ConnectAsync([uri] $WsUrl, $cts.Token).Wait()

        $msg = @{ id = 1; method = $Method }
        if ($Params) { $msg['params'] = $Params }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($msg | ConvertTo-Json -Depth 6 -Compress))
        $ws.SendAsync([ArraySegment[byte]]::new($bytes), [Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait()

        $buf = New-Object byte[] 65536
        for ($frame = 0; $frame -lt 200; $frame++) {
            $sb = New-Object Text.StringBuilder
            do {
                $t = $ws.ReceiveAsync([ArraySegment[byte]]::new($buf), $cts.Token)
                $t.Wait()
                [void] $sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $t.Result.Count))
            } while (-not $t.Result.EndOfMessage)

            $obj = $null
            try { $obj = $sb.ToString() | ConvertFrom-Json } catch { continue }
            if ($obj -and ($obj.PSObject.Properties.Name -contains 'id') -and ($obj.id -eq 1)) { return $obj }
        }
        return $null
    }
    finally {
        try { $ws.Dispose() }  catch { }
        try { $cts.Dispose() } catch { }
    }
}

function Get-CdpBrowserWsUrl {
    param([int] $Port, [int] $WaitSec = 30)
    for ($i = 0; $i -lt ($WaitSec * 2); $i++) {
        try {
            $v = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 3 -ErrorAction Stop
            if ($v.webSocketDebuggerUrl) { return [string] $v.webSocketDebuggerUrl }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    return ''
}

# Cookies for the helpdesk origin, as a Cookie header. Cookies set on a parent
# domain count - the i21 apps put some on .irely.com - so a plain equality test on
# the domain would silently drop them, which is the same "half a header" failure
# hand-copying produces.
function Get-CdpCookieHeader {
    param([string] $WsUrl, [string] $HostName)

    $resp = Invoke-CdpCommand -WsUrl $WsUrl -Method 'Storage.getCookies'
    if (-not $resp -or -not $resp.result) { return '' }

    $jar = [ordered] @{}
    foreach ($c in @($resp.result.cookies)) {
        $d = ([string] $c.domain).TrimStart('.')
        if (-not $d) { continue }
        if ($HostName -ne $d -and -not $HostName.EndsWith(".$d")) { continue }
        # Host-exact beats a parent-domain cookie of the same name.
        if ($jar.Contains($c.name) -and $d -ne $HostName) { continue }
        $jar[[string] $c.name] = [string] $c.value
    }
    if (-not $jar.Count) { return '' }
    return (@($jar.Keys | ForEach-Object { "$_=$($jar[$_])" }) -join '; ')
}

# Launches the browser, waits for a session that actually WORKS, hands back the
# cookie. The success condition is deliberately the live probe rather than "the URL
# stopped saying LoginAD": this whole section was lost for a day to a cookie that
# looked signed-in and was not, so nothing here trusts appearances.
function Invoke-BrowserCookieCapture {
    param(
        [string] $BaseUrl,
        [string] $ProfileDir,
        [string] $BrowserPath,
        # 'helpdesk' / 'sharepoint' - only used to name the right config key in the
        # messages, so a failure points at the setting the reader can actually edit.
        [string] $ConfigKey = 'helpdesk',
        # Regex the name of at least one harvested cookie must match before a probe
        # is spent. Both sites hand out antiforgery/handshake cookies long before a
        # session exists, and probing those just burns requests and prints noise.
        [string] $RequireCookie = '',
        [string] $SignInHint = 'Sign in in the window that just opened.',
        [int]    $WaitSec = 420
    )

    $exe = Get-ChromiumPath -Preferred $BrowserPath
    if (-not $exe) {
        Write-Bad 'no Chromium-family browser found on this machine'
        Write-Wrapped "This route drives Edge, Chrome, Brave, Vivaldi or Chromium over the DevTools protocol. Firefox cannot be used - it does not speak CDP. Set $ConfigKey.browserPath in the config to point at one, or use a manual route instead." '    ' 'Yellow'
        return $null
    }
    Write-Note "browser: $exe"

    if (-not (Test-Path -LiteralPath $ProfileDir)) {
        New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    }
    # The profile holds live session cookies once signed in, so lock it down the
    # same way the config file is locked down.
    try {
        $acl = Get-Acl -LiteralPath $ProfileDir
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($r in @($acl.Access)) { $acl.RemoveAccessRule($r) | Out-Null }
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($me, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
        Set-Acl -LiteralPath $ProfileDir -AclObject $acl
    } catch { Write-Warn "could not restrict the profile directory: $($_.Exception.Message)" }

    $port = Get-FreeTcpPort
    $args = @(
        "--remote-debugging-port=$port"
        "--user-data-dir=`"$ProfileDir`""
        '--remote-allow-origins=*'
        '--no-first-run'
        '--no-default-browser-check'
        '--start-maximized'
        "`"$BaseUrl`""
    )

    $proc = $null
    try {
        $proc = Start-Process -FilePath $exe -ArgumentList $args -PassThru
        Write-Note "started on debugging port $port"

        $ws = Get-CdpBrowserWsUrl -Port $port
        if (-not $ws) {
            Write-Bad 'the browser started but never opened its debugging port'
            Write-Wrapped 'An existing browser process can swallow the launch. Close every Edge/Chrome window and try again, or use the clipboard route.' '    ' 'Yellow'
            return $null
        }

        $hostName = ([uri] $BaseUrl).Host
        Write-Host ''
        Write-Wrapped $SignInHint '    ' 'White'
        Write-Wrapped 'Nothing to copy and nothing to paste - the cookie is read from the browser as soon as the session works. This window is a dedicated profile, so next time it should already be signed in.' '    ' 'Gray'
        Write-Host ''

        $deadline  = (Get-Date).AddSeconds($WaitSec)
        $lastTried = ''
        $spin      = 0
        while ((Get-Date) -lt $deadline) {
            if ($proc.HasExited) { Write-Host ''; Write-Warn 'the browser was closed before a working session appeared'; return $null }

            $hdr = ''
            try { $hdr = Get-CdpCookieHeader -WsUrl $ws -HostName $hostName } catch { }

            # No session cookie yet - the handshake ones do not count.
            if ($hdr -and $RequireCookie) {
                $names = @($hdr -split ';' | Where-Object { $_ -match '=' } | ForEach-Object { ($_ -split '=', 2)[0].Trim() })
                if (@($names | Where-Object { $_ -match $RequireCookie }).Count -eq 0) { $hdr = '' }
            }

            # Only spend a request on the server when the jar actually changed.
            if ($hdr -and $hdr -ne $lastTried) {
                $lastTried = $hdr
                $probe = $null
                try { $probe = Invoke-CookieProbe -Url $BaseUrl -Cookie $hdr } catch { }
                if ($probe -and -not $probe.Looped -and -not $probe.OffHost -and $probe.Code -eq 200 `
                    -and ($probe.Final -notmatch '(?i)(/login|/signin|/loginad|returnurl=)') `
                    -and ($probe.Title -notmatch '(?i)\b(log\s*in|login|sign\s*in|signin)\b')) {
                    Write-Host ''
                    Write-Ok "signed-in session detected - $(@($hdr -split ';' | Where-Object { $_ -match '=' }).Count) cookie(s), $($hdr.Length) chars"
                    if ($probe.Title) { Write-Note "landed on: $($probe.Title)" }
                    return $hdr
                }
            }

            Write-Host ("`r    waiting for a working session... {0}  " -f '|/-\'[$spin % 4]) -NoNewline -ForegroundColor DarkGray
            $spin++
            Start-Sleep -Seconds 3
        }
        Write-Host ''
        Write-Warn 'gave up waiting for a signed-in session'
        return $null
    }
    finally {
        # Leave nothing running that the operator did not start themselves.
        if ($proc -and -not $proc.HasExited) {
            try { $proc.CloseMainWindow() | Out-Null; Start-Sleep -Milliseconds 700 } catch { }
            try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
        }
    }
}

# Pulls the cookie out of whatever the browser put on the clipboard.
#
# Every quote-anchored pattern here has failed in the field at least once, because
# the browsers do not emit one stable shape: Chromium's cmd flavour escapes a double
# quote as ^", and both Chromium and Firefox switch to bash ANSI-C quoting, $'...',
# the moment a value contains anything they think is special - which a base64
# session ticket regularly does. Each near-miss stored the whole curl command as the
# cookie, and the operator was told to "paste just the cookie string", so the
# capture route the instructions recommend was the one route that could not work.
#
# So: normalise the shell noise first, then try the flags, and fall back to finding
# the longest literal `name=value; name=value` run - which does not care how
# anything was quoted. On failure, report the SHAPE that defeated it, values masked,
# because "not found" with no evidence is what made this take three rounds.
function Get-CookieFromPaste {
    param([string] $Raw)

    $flat = [string] $Raw
    $flat = $flat -replace '\^\r?\n', ' '   # cmd      line continuation
    $flat = $flat -replace '\\\r?\n', ' '   # sh/bash  line continuation
    $flat = $flat -replace '`\r?\n',  ' '   # psh      line continuation
    $flat = $flat -replace '\r?\n',   ' '
    $flat = $flat -replace '\^"', '"'       # cmd flavour escapes " as ^"
    $flat = $flat -replace '\$([''"])', '$1' # $'...' ANSI-C quoting -> plain quote

    $cookie = ''
    $how    = ''

    if     ($flat -match '(?i)(?:-H|--header)\s+([''"])\s*cookie:\s*(?<v>.+?)\1')                { $cookie = $Matches['v']; $how = 'the -H "cookie:" header' }
    elseif ($flat -match '(?i)(?:-b|--cookie)\s+([''"])(?<v>[^''"]*=[^''"]*)\1')                 { $cookie = $Matches['v']; $how = 'the -b cookie jar' }
    # No \b after the flag letter: `--compressed` has no word boundary between its
    # first and second letter, so the lookahead never fired and the flag itself was
    # swallowed into the cookie value.
    elseif ($flat -match '(?i)(?:-H|--header)\s+cookie:\s*(?<v>\S.*?)(?=\s+-{1,2}[A-Za-z]|$)') { $cookie = $Matches['v']; $how = 'an unquoted -H cookie: header' }
    elseif ($flat -match '(?i)(?:-b|--cookie)\s+(?<v>[^\s''"]+=[^\s''"]+)')                      { $cookie = $Matches['v']; $how = 'an unquoted -b cookie jar' }
    elseif ($Raw  -match '(?im)^\s*cookie:\s*(?<v>.+)$')                                         { $cookie = $Matches['v']; $how = 'a bare "Cookie:" header line' }
    else {
        $best = ''
        foreach ($m in [regex]::Matches($flat, '[A-Za-z0-9_.\-]+=[^;\s''"]*(?:;\s*[A-Za-z0-9_.\-]+=[^;\s''"]*)+')) {
            if ($m.Value.Length -gt $best.Length) { $best = $m.Value }
        }
        if ($best) { $cookie = $best; $how = 'the longest name=value; run in the paste' }
    }

    $cookie = ([string] $cookie).Trim()
    $cookie = $cookie.Trim(';').Trim()

    # Values masked - the names are not secrets, the values are.
    $shape = ''
    $i = $flat.IndexOf('cookie', [StringComparison]::OrdinalIgnoreCase)
    if ($i -ge 0) {
        $from  = [Math]::Max(0, $i - 14)
        $len   = [Math]::Min(70, $flat.Length - $from)
        $shape = ($flat.Substring($from, $len) -replace '=[^;\s''"]{4,}', '=<value>')
    }

    return [pscustomobject] @{ Cookie = $cookie; How = $how; Shape = $shape }
}

function Invoke-CookieProbe {
    param([string] $Url, [string] $Cookie, [int] $MaxHops = 8)

    $origin  = ([uri] $Url).Authority
    $cleared = @()
    $chain   = @()
    $seen    = @{}
    $current = $Url

    # Carry cookies across hops the way a browser does. Re-sending only the
    # original header and discarding every Set-Cookie made the walk unable to
    # complete a bootstrap redirect - an app that sets a cookie and redirects to
    # itself to pick it up then redirects for ever, which surfaced as a loop that
    # looked like a broken cookie and was neither.
    $jar = [ordered] @{}
    foreach ($p in ([string] $Cookie -split ';')) {
        if ($p -match '^\s*([^=]+)=(.*)$') { $jar[$Matches[1].Trim()] = $Matches[2] }
    }

    for ($hop = 1; $hop -le $MaxHops; $hop++) {

        # Send the cookie ONLY to the host it was issued for. A browser scopes
        # cookies by origin; this walk did not, so a redirect to an identity
        # provider would have posted the operator's live session cookie to a
        # third-party host. Same-origin only, always.
        $hdr = ''
        if ($jar.Count -and (([uri] $current).Authority -eq $origin)) {
            $hdr = (@($jar.Keys | ForEach-Object { "$_=$($jar[$_])" }) -join '; ')
        }

        # A loop is a hop that makes NO progress: the same URL with the same
        # cookies. Keying on the URL alone was wrong twice over - left to run out
        # of hops it reported "expired, re-capture", the one conclusion a loop
        # does not support; and it called a legitimate bootstrap redirect a loop,
        # because an app that sets a cookie and redirects to itself to pick it up
        # visits one URL twice quite properly. The jar is what moved.
        $key = "$current|$hdr"
        if ($seen.ContainsKey($key)) {
            return [pscustomobject] @{
                Code = 0; Final = $current; Body = ''; Bytes = 0; Title = ''
                Cleared = $cleared; Chain = $chain; Looped = $true; OffHost = ''
            }
        }
        $seen[$key] = $true
        $chain += $current

        $req = [Net.HttpWebRequest]::Create($current)
        $req.Method            = 'GET'
        $req.AllowAutoRedirect = $false
        $req.Timeout           = 20000
        # Some app servers hand a bare user agent a different page than a browser.
        $req.UserAgent         = 'Mozilla/5.0'

        if ($hdr) { $req.Headers.Add('Cookie', $hdr) }

        try { $resp = $req.GetResponse() }
        catch [Net.WebException] {
            $resp = $_.Exception.Response
            if (-not $resp) { throw }
        }

        $code = [int] $resp.StatusCode
        $loc  = [string] $resp.Headers['Location']

        # Apply Set-Cookie to the jar, and note deletions for the diagnosis. A
        # deletion is `name=` with an expiry - the server's way of saying it read
        # the ticket and refused it - and it rides on the redirect rather than on
        # the page that redirect lands on, which is why every hop is inspected.
        #
        # GetValues can mis-split on the comma inside `expires=Thu, 01 Jan 1970`,
        # so fragments are required to contain a name=value before any ';' - a
        # date tail has no '=' ahead of its ';' and is skipped harmlessly.
        $scVals = @()
        try { $scVals = @($resp.Headers.GetValues('Set-Cookie')) } catch { }
        foreach ($sc in $scVals) {
            if ($sc -match '^\s*([^=;]+)=([^;]*)') {
                $n = $Matches[1].Trim()
                $v = $Matches[2]
                if ($v -eq '' -and $sc -match '(?i)expires=') {
                    if ($cleared -notcontains $n) { $cleared += $n }
                    $jar.Remove($n)
                }
                else { $jar[$n] = $v }
            }
        }

        $body = ''
        try {
            $stream = $resp.GetResponseStream()
            if ($stream) { $sr = New-Object IO.StreamReader($stream); $body = $sr.ReadToEnd(); $sr.Close() }
        } catch { }
        $resp.Close()

        if (-not $loc) {
            $title = ''
            $m = [regex]::Match($body, '(?is)<title>(.*?)</title>')
            if ($m.Success) { $title = $m.Groups[1].Value.Trim() }
            return [pscustomobject] @{
                Code = $code; Final = $current; Body = $body; Bytes = $body.Length
                Title = $title; Cleared = $cleared; Chain = $chain; Looped = $false; OffHost = ''
            }
        }

        if ($loc -notmatch '^https?://') {
            $u = [uri] $current
            $loc = "$($u.Scheme)://$($u.Authority)" + $(if ($loc.StartsWith('/')) { $loc } else { "/$loc" })
        }

        # Handed off to another host - an identity provider, typically. Stop here
        # rather than following: the cookie must not travel there, and where it
        # was sent is the useful evidence by itself.
        $nextHost = ([uri] $loc).Authority
        if ($nextHost -ne $origin) {
            $chain += $loc
            return [pscustomobject] @{
                Code = $code; Final = $loc; Body = ''; Bytes = 0; Title = ''
                Cleared = $cleared; Chain = $chain; Looped = $false; OffHost = $nextHost
            }
        }

        $current = $loc
    }

    # Out of hops without repeating a URL - a long redirect chain rather than a
    # tight loop, but still not a working session.
    return [pscustomobject] @{
        Code = 0; Final = $current; Body = ''; Bytes = 0; Title = ''
        Cleared = $cleared; Chain = $chain; Looped = $true; OffHost = ''
    }
}

function Invoke-HelpdeskSection {
    Write-Banner 'Optional   Helpdesk cookie'

    Write-FieldInfo -Name 'helpdesk.cookie' `
        -What 'A session cookie for the helpdesk web app, captured from a browser where you are signed in.' `
        -Where 'Reading a referenced helpdesk ticket - above all its Database Copy tab, which names the server and database IT already restored a customer copy onto. That feeds the known-servers shortcut. Also helpdesk-hosted images embedded in Jira descriptions, which is common because the Jira attachment field is often empty.' `
        -Without 'Helpdesk enrichment is off. The gap is recorded and the run continues on the ticket''s own evidence. Never a stop - this section is supplementary by design.' `
        -Notes @(
            'These cookies last days, not months. Going stale is expected, not a broken setup.',
            'BE SIGNED IN BEFORE YOU CAPTURE, and check it rather than assuming it. The login is federated and two-step - email plus Company, then Next, then the Microsoft/Azure AD sign-in and any MFA - and the session cookie only exists once that whole round trip has finished. If the page still says "Sign in to continue to i21", there is no session to capture yet.',
            'Capturing on the sign-in page is the single most common failure, and it does not look like one: that page hands out an antiforgery cookie and clears the app session cookie, so the paste looks plausible, is thousands of characters long, and is rejected exactly like an expired cookie - every time you retry it.',
            'Then: F12 -> Network -> reload -> right-click the top document request -> Copy -> Copy as cURL, and choose the CLIPBOARD option below. Do not paste into the prompt and do not pick the cookies out by hand - a console prompt truncates, and hand-picking drops or splits values.',
            'Paste the cURL command unedited. Both the -H "cookie:" and the -b forms are understood, in every quoting style the browsers use.'
        )

    $node = Get-CfgNode 'helpdesk'
    $baseDefault = [string] $node.baseUrl
    if (-not $baseDefault) { $baseDefault = 'https://helpdesk.irely.com/irelyi21Live' }

    $consequence = 'Helpdesk enrichment off - runs continue on the Jira''s own evidence. Never blocking.'

    Write-Host ''
    while ($true) {
        if (-not (Read-YesNo 'Configure the helpdesk cookie now?' $false)) {
            if (Confirm-Skip 'helpdesk' $consequence) { return }
            continue
        }

        $base = Read-Url 'Helpdesk base URL' $baseDefault
        if (Test-IsBack $base) { return }
        $baseDefault = $base
        $node | Add-Member -NotePropertyName 'baseUrl' -NotePropertyValue $base -Force

        # The cookie is only valid for the site it came from, so open the one
        # they just entered - not whatever helpdesk they happen to have open.
        Open-Url $base 'the helpdesk (sign in there first)'

        Write-Host ''
        # A helpdesk cookie runs to two to four THOUSAND characters, and a
        # console prompt cannot take that. Right-clicking to paste one into
        # Read-Host -AsSecureString fed it a truncated prefix - which is a real,
        # invalid cookie, so the test correctly reported a sign-in page - and
        # spilled the remainder into the NEXT prompt, where it was echoed in
        # clear text. Reading the clipboard avoids the console entirely: no
        # length limit, nothing echoed, nothing typed.
        $capOpts = @(
            @{ Key = 'b'; Label = 'open a browser and take it for me     (sign in, nothing to copy)' }
            @{ Key = 'c'; Label = 'read it straight from the clipboard   (Copy as cURL, then pick this)' }
            @{ Key = 'f'; Label = 'read it from a file I saved it to' }
            @{ Key = 'p'; Label = 'type or paste it here                 (only safe for short values)' }
        )
        Write-Host ''
        Write-Host '  How should I take the cookie?' -ForegroundColor White
        $capMode = Read-Option $capOpts 'b'

        # The browser route returns a cookie that is ALREADY proved against the
        # server, so it skips the parse, the shape report and the test below - all
        # of which exist to compensate for a hand-made capture.
        if ($capMode -eq 'b') {
            $profDir = [string] $node.browserProfileDir
            if (-not $profDir) { $profDir = Join-Path $env:USERPROFILE '.jira-ai-helpdesk-browser' }

            $got = Invoke-BrowserCookieCapture -BaseUrl $base -ProfileDir $profDir `
                -BrowserPath ([string] $node.browserPath) -ConfigKey 'helpdesk' `
                -RequireCookie 'Identity\.Application' `
                -SignInHint 'Sign in in the window that just opened. It is a two-step federated login: email/username AND Company, then Next, then the Microsoft sign-in and any MFA.'
            if (-not $got) {
                Write-Note 'browser capture did not produce a working session'
                if (Confirm-Skip 'helpdesk' $consequence) { return }
                continue
            }

            $node | Add-Member -NotePropertyName 'cookie'            -NotePropertyValue $got     -Force
            $node | Add-Member -NotePropertyName 'obtainedAt'        -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
            $node | Add-Member -NotePropertyName 'browserProfileDir' -NotePropertyValue $profDir -Force
            Show-SecretShape 'helpdesk.cookie' $got
            Write-Ok 'verified against the server during capture'
            Write-Wrapped "Refresh it any time with: Setup-JiraAiFix.ps1 -Section helpdesk - the profile at $profDir keeps the sign-in, so it should need no typing next time." '    ' 'DarkGray'
            Set-Status 'helpdesk' 'verified' -Detail 'captured from the browser, proved live'
            return
        }

        $raw = ''
        if ($capMode -eq 'c') {
            try {
                $raw = [string] (Get-Clipboard -Raw -ErrorAction Stop)
                if (-not $raw) { Write-Warn 'the clipboard is empty' }
                else { Write-Ok "read $($raw.Length) characters from the clipboard" }
            }
            catch { Write-Bad "could not read the clipboard: $($_.Exception.Message)" }
        }
        elseif ($capMode -eq 'f') {
            $f = Read-Text 'Path to the file' ''
            if (Test-IsBack $f) { return }
            if (Test-Path -LiteralPath $f) {
                try { $raw = [string] (Get-Content -LiteralPath $f -Raw -ErrorAction Stop); Write-Ok "read $($raw.Length) characters from $f" }
                catch { Write-Bad "could not read it: $($_.Exception.Message)" }
            }
            else { Write-Bad "no such file: $f" }
        }
        else {
            Write-Wrapped 'Paste either the full "Copy as cURL" command, or just the cookie string. Anything past roughly 250 characters may be cut off by the console - if that happens, use the clipboard option instead.' '    ' 'DarkGray'
            $raw = Read-Secret 'Paste here'
            if (Test-IsBack $raw) { return }
        }

        if (-not $raw) {
            if (Confirm-Skip 'helpdesk' $consequence) { return }
            continue
        }

        $parsed = Get-CookieFromPaste -Raw $raw
        $cookie = $parsed.Cookie
        if ($parsed.How) { Write-Note "took the cookie from $($parsed.How)" }

        # Nothing usable found. Print the shape it saw - values masked - rather than
        # only "paste just the cookie string", which is the advice that turned an
        # unrecognised quoting flavour into several failed rounds with no clue why.
        if (-not $cookie -or $cookie -match '(?i)^\s*curl[\s"'']') {
            Write-Bad 'no cookie could be found in what was pasted'
            if ($parsed.Shape) { Write-Wrapped "The nearest thing to a cookie in it looked like: $($parsed.Shape)" '    ' 'Yellow' }
            Write-Wrapped 'Re-copy with Copy as cURL and paste it unedited, or use F12 -> Application -> Cookies, copy the name=value pairs and join them with "; ".' '    ' 'Yellow'
            if (Confirm-Skip 'helpdesk' $consequence) { return }
            continue
        }

        # Count the pairs. A truncated capture usually still parses and still
        # looks plausible - the pair count is what gives it away, and it is safe
        # to print because names are not secrets.
        $pairs = @($cookie -split ';' | Where-Object { $_ -match '=' })
        $names = @($pairs | ForEach-Object { ($_ -split '=', 2)[0].Trim() })
        Write-Note ("$($pairs.Count) cookie(s), $($cookie.Length) chars: " + ($names -join ', '))
        if ($pairs.Count -lt 2) {
            Write-Warn 'only one cookie was found - a browser session almost always sends several'
            Write-Wrapped 'That is the shape of a truncated capture. Use the clipboard option rather than pasting.' '    ' 'Yellow'
        }

        $node | Add-Member -NotePropertyName 'cookie'     -NotePropertyValue $cookie -Force
        $node | Add-Member -NotePropertyName 'obtainedAt' -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
        Show-SecretShape 'helpdesk.cookie' $cookie

        if (-not $cookie) {
            if (Confirm-Skip 'helpdesk' $consequence) { return }
            continue
        }
        if (-not (Read-YesNo 'Test it now?' $true)) { Set-Status 'helpdesk' 'configured' -Detail 'not tested'; return }

        $failed = $false
        try {
            # A login page is served with 200, so status alone proves nothing -
            # but the old test was worse than useless. It matched the bare words
            # `sign in` / `log in` with no word boundary, so `login`, `logIn`,
            # `LoginPartial`, `data-login`, any URL containing /login - all of
            # which appear constantly on pages you are perfectly signed in to -
            # reported a WORKING cookie as expired. People then re-captured a
            # good cookie over and over.
            #
            # What is reliable is the NEGATIVE signal - being bounced to the login
            # page. Proving the positive is not: this helpdesk's login page carries
            # no password box at all (it posts to /LoginAD), and a signed-in page
            # need not contain the words "sign out" anywhere in its server-rendered
            # HTML. Requiring that proof pushed good cookies into a "cannot tell"
            # verdict that reads as a failure. So: look for login evidence, and
            # treat its absence on a 200 as working.
            #
            # The walk is deliberately hop-by-hop rather than one auto-redirecting
            # Invoke-WebRequest, because the two most decisive signals only exist
            # on the hop that is otherwise followed and discarded: the 302 to the
            # login URL, and the server clearing its own auth cookie. It also side-
            # steps two harness bugs - `-MaximumRedirection 0` throws on Windows
            # PowerShell 5.1, and $r.BaseResponse.ResponseUri does not exist on
            # PowerShell 7, where it silently left the redirect check always false.
            $probe = Invoke-CookieProbe -Url $base -Cookie $cookie

            Write-Note ("HTTP $($probe.Code), $($probe.Bytes) bytes" + $(if ($probe.Final -ne $base) { ", landed on $($probe.Final)" } else { '' }))
            if ($probe.Title)          { Write-Note "page title: $($probe.Title)" }
            if ($probe.Cleared.Count)  { Write-Note ("server cleared cookie(s): " + ($probe.Cleared -join ', ')) }

            $hasPasswordBox = ($probe.Body -match '(?i)<input[^>]+type\s*=\s*["'']?password')
            $hasSignOut     = ($probe.Body -match '(?i)(sign[\s_-]*out|log[\s_-]*out|logoff)')
            $wentToLogin    = ($probe.Final -match '(?i)(/login|/signin|/loginad|/account/login|returnurl=)')
            $titleIsLogin   = ($probe.Title -match '(?i)\b(log\s*in|login|sign\s*in|signin)\b')

            # A loop has to be judged BEFORE the login-page tests, because the URL it
            # loops through is usually the login URL - which made every loop read as
            # "expired cookie, re-capture", the one thing it is good evidence against.
            # An expired cookie does not loop: it is refused once and the login page
            # renders. Looping means the login endpoint keeps handing the session back
            # to the app and the app keeps returning it, so something is being
            # accepted. Re-capturing cannot fix that, and saying so stops the circle.
            if ($probe.Looped) {
                Write-Warn 'the site redirected in a loop - this is NOT an expired cookie'
                Write-Wrapped 'An expired cookie is refused once and the login page renders. A loop means the login endpoint keeps accepting the session and handing it back to the app, which keeps bouncing it - so part of what you pasted IS being accepted. Re-capturing the same way will loop again.' '    ' 'Yellow'
                Write-Host ''
                Write-Host '    the chain it walked:' -ForegroundColor DarkGray
                foreach ($u in $probe.Chain) { Write-Host "      $u" -ForegroundColor DarkGray }
                Write-Host ''
                Write-Wrapped 'Cookies ARE carried across hops here, and deletions are honoured, so this is not the probe failing to complete a bootstrap redirect. A no-progress loop means the app bounces the same URL back with the same cookies - usually a session that authenticates but is not authorised for this base URL, or a base URL that is not the app''s real entry point.' '    ' 'Yellow'
                Write-Wrapped "Worth trying: set the base URL to the page you actually land on after signing in, rather than $base." '    ' 'Yellow'
                if ($probe.Cleared.Count) {
                    Write-Wrapped ("For reference, the server did clear " + ($probe.Cleared -join ', ') + " along the way.") '    ' 'DarkGray'
                }
                Set-Status 'helpdesk' 'partial' -Detail 'redirect loop - cookie partly accepted, not a clean expiry'
                $failed = $true
            }
            elseif ($probe.OffHost) {
                Write-Warn "the site handed off to $($probe.OffHost) - that is a sign-in redirect"
                Write-Wrapped "The walk stopped there deliberately: your cookie belongs to $(([uri] $base).Authority) and is never sent to another host. A hand-off to an identity provider means the helpdesk did not accept the session." '    ' 'Yellow'
                Write-Wrapped 'Sign in again in the browser and re-capture - and paste the whole cURL command rather than picking cookies out of it.' '    ' 'Yellow'
                Set-Status 'helpdesk' 'failed' -Detail "redirected to $($probe.OffHost)"
                $failed = $true
            }
            elseif ($wentToLogin -or $titleIsLogin -or ($hasPasswordBox -and -not $hasSignOut)) {
                Write-Warn 'that is a sign-in page - the cookie is expired or incomplete'
                if ($wentToLogin)      { Write-Wrapped "It was redirected to $($probe.Final)" '    ' 'Yellow' }
                elseif ($titleIsLogin) { Write-Wrapped "The page title is `"$($probe.Title)`"." '    ' 'Yellow' }
                else                   { Write-Wrapped 'It contains a password box and no sign-out link.' '    ' 'Yellow' }

                # Distinguishing a stale cookie from a bad probe URL or a partial
                # capture used to be guesswork, and the guess sent people off to
                # re-capture a cookie that was already fine. The server clearing
                # its own auth cookie settles it: it parsed the ticket and refused.
                if ($probe.Cleared.Count) {
                    Write-Wrapped ("The server sent back an expiry for " + ($probe.Cleared -join ', ') + " - so it read the session and rejected it. The cookie is not a wrong URL and not a truncated capture: the server simply does not accept it.") '    ' 'Yellow'
                }
                else {
                    Write-Wrapped 'If it never worked, a partial Cookie header is the usual cause: re-capture with Copy as cURL, which cannot drop a cookie or truncate a value.' '    ' 'Yellow'
                }

                # By far the most common cause, and it used to be reported as "stale
                # cookie, re-capture and it will work" - which sent the operator round
                # the same loop, because re-capturing from the login page produces the
                # same rejected cookie every time. The login page ISSUES an antiforgery
                # cookie and CLEARS the app session cookie, so a capture taken while
                # sitting on it looks like this: fresh antiforgery, cleared session, and
                # whatever stale identity cookie the browser still had. Name it.
                $suppliedNames  = @($cookie -split ';' | Where-Object { $_ -match '=' } | ForEach-Object { ($_ -split '=', 2)[0].Trim() })
                $hasHandshake   = @($suppliedNames | Where-Object { $_ -match '(?i)(OpenIdConnect\.Nonce|\.Correlation\.)' }).Count -gt 0
                $hasIdentity    = @($suppliedNames | Where-Object { $_ -match '(?i)Identity\.Application' }).Count -gt 0
                $hasAntiforgery = @($suppliedNames | Where-Object { $_ -match '(?i)antiforgery' }).Count -gt 0

                if (-not $hasIdentity) {
                    Write-Host ''
                    Write-Wrapped 'There is no session cookie in this paste at all - nothing named .AspNetCore.Identity.Application. Whatever was captured, it was not a signed-in session.' '    ' 'Yellow'
                }

                # OpenIdConnect.Nonce and Correlation exist ONLY while an OIDC
                # sign-in is in flight - they are handshake state, deleted the moment
                # the provider redirects back. Their presence dates the capture
                # precisely: after Next, before Microsoft returned. Worth saying in
                # those words, because the operator reasonably believed they had
                # signed in, and "expired cookie" does not describe this at all.
                if ($hasHandshake) {
                    Write-Host ''
                    Write-Wrapped 'CAPTURED MID-SIGN-IN. The paste contains OpenIdConnect.Nonce and Correlation cookies, which exist only while the Microsoft round trip is still in progress - they are deleted as soon as it completes. So this was taken after you pressed Next but before the sign-in finished coming back.' '    ' 'Yellow'
                    Write-Host ''
                    Write-Wrapped 'Let the sign-in FINISH before capturing anything:' '    ' 'Gray'
                    Write-Wrapped '1. Complete the Microsoft page, including MFA, and wait for it to return you to the helpdesk.' '      ' 'Gray'
                    Write-Wrapped '2. You should be looking at the helpdesk itself - a request list, not a sign-in form.' '      ' 'Gray'
                    Write-Wrapped '3. Now press F5 to reload that finished page.' '      ' 'Gray'
                    Write-Wrapped '4. F12 -> Network -> right-click the TOP document request -> Copy as cURL.' '      ' 'Gray'
                    Write-Host ''
                    Write-Wrapped 'The reload in step 3 is the part that matters: it is what makes the top request carry the finished session rather than the handshake.' '    ' 'DarkGray'
                    Write-Host ''
                    Write-Wrapped 'Far easier: re-run this section and choose "open a browser and take it for me". It waits for the sign-in to actually work and reads the cookie itself, so none of this timing matters.' '    ' 'White'
                }
                elseif ($hasAntiforgery) {
                    Write-Host ''
                    Write-Wrapped 'MOST LIKELY: the capture was taken ON the sign-in page, not from a signed-in session. That page issues the antiforgery cookie your paste contains and clears the app session cookie, so re-capturing the same way will fail identically however many times you try.' '    ' 'Yellow'
                    Write-Host ''
                    Write-Wrapped 'Sign in properly first - it is a two-step federated login, so the session cookie only exists after the whole round trip finishes:' '    ' 'Gray'
                    Write-Wrapped '1. Enter your email/username AND pick the Company, then press Next.' '      ' 'Gray'
                    Write-Wrapped '2. Complete the Microsoft / Azure AD sign-in, including MFA if prompted.' '      ' 'Gray'
                    Write-Wrapped '3. Confirm you are looking at the helpdesk itself - NOT a page headed "Sign in to continue to i21".' '      ' 'Gray'
                    Write-Wrapped '4. Only now: F12 -> Network -> reload -> right-click the top document request -> Copy as cURL.' '      ' 'Gray'
                }
                if ($node.obtainedAt) { Write-Wrapped "The cookie being tested was captured on $($node.obtainedAt) - these last days, not months." '    ' 'DarkGray' }
                Set-Status 'helpdesk' 'failed' -Detail 'returned a login page'
                $failed = $true
            }
            elseif ($probe.Code -eq 200) {
                if ($hasSignOut) { Write-Ok 'signed-in page returned - cookie works (sign-out link present)' }
                else             { Write-Ok 'real content returned, no sign-in page - cookie works' }
                Set-Status 'helpdesk' 'verified' -Detail 'captured today'
                return
            }
            else {
                Write-Warn "unexpected HTTP $($probe.Code) - cannot tell whether the session is live"
                Write-Wrapped 'It is not a sign-in page, so this is not evidence of a bad cookie. If that URL shows real content when you open it in a browser, keep it.' '    ' 'Yellow'
                Set-Status 'helpdesk' 'partial' -Detail 'cookie stored, could not be proved either way'
                $failed = $true
            }
        }
        catch {
            Write-Warn "request failed: $($_.Exception.Message)"
            Write-Note 'non-blocking: runs continue on the Jira evidence'
            Set-Status 'helpdesk' 'failed' -Detail $_.Exception.Message
            $failed = $true
        }

        if ($failed) {
            $choice = Read-FailureChoice 'The helpdesk cookie'
            if ($choice -eq 'continue') { Write-Note 'kept as-is - re-run with -Section helpdesk when convenient'; return }
            if ($choice -eq 'skip') { if (Confirm-Skip 'helpdesk' $consequence) { return } }
        }
    }
}

function Invoke-SharePointSection {
    Write-Banner 'Optional   SharePoint cookie'

    Write-FieldInfo -Name 'sharepoint.cookie' `
        -What 'A session cookie for your SharePoint tenant, read out of a browser you have signed in to.' `
        -Where 'Downloading a database backup whose link points at SharePoint. Tickets often carry the .bak as a SharePoint link rather than an attachment, and without a cookie the runbook cannot fetch it - it has to stop and ask you to download it by hand.' `
        -Without 'SharePoint-hosted backups are handed back to you to download. Everything else is unaffected, and no run is blocked by this - it just costs you the download.' `
        -Notes @(
            'Same mechanism as the helpdesk section: it drives a browser over the DevTools protocol and reads the cookie once the session works. Nothing to copy or paste.',
            'SharePoint is Azure AD, so the sign-in is the Microsoft one with any MFA. The dedicated profile keeps it, so later refreshes should need no typing.',
            'These cookies are short-lived - days, and often fewer than the helpdesk one. Going stale is expected, not a broken setup.'
        )

    $node = Get-CfgNode 'sharepoint'
    $tenantDefault = [string] $node.tenant
    $consequence = 'SharePoint-hosted backups must be downloaded by hand. Never blocking.'

    Write-Host ''
    while ($true) {
        if (-not (Read-YesNo 'Configure the SharePoint cookie now?' $false)) {
            if (Confirm-Skip 'sharepoint' $consequence) { return }
            continue
        }

        $tenant = Read-Text 'SharePoint tenant host (e.g. contoso.sharepoint.com)' $tenantDefault
        if (Test-IsBack $tenant) { return }
        if (-not $tenant) {
            Write-Bad 'a tenant host is needed - it is the site the cookie belongs to'
            if (Confirm-Skip 'sharepoint' $consequence) { return }
            continue
        }
        # Accept a pasted URL as well as a bare host: people copy the address bar.
        $tenant = ($tenant -replace '(?i)^https?://', '') -replace '/.*$', ''
        $tenantDefault = $tenant
        $node | Add-Member -NotePropertyName 'tenant' -NotePropertyValue $tenant -Force

        $url     = "https://$tenant"
        $profDir = [string] $node.browserProfileDir
        if (-not $profDir) { $profDir = Join-Path $env:USERPROFILE '.jira-ai-sharepoint-browser' }

        # FedAuth is the SharePoint session cookie; rtFa is its cross-site
        # companion. Waiting for one of them keeps the loop from probing the
        # Azure AD handshake cookies, which appear first and prove nothing.
        $got = Invoke-BrowserCookieCapture -BaseUrl $url -ProfileDir $profDir `
            -BrowserPath ([string] $node.browserPath) -ConfigKey 'sharepoint' `
            -RequireCookie '^(FedAuth|rtFa)$' `
            -SignInHint 'Sign in to SharePoint in the window that just opened - the Microsoft sign-in, including MFA if prompted.'

        if (-not $got) {
            Write-Note 'browser capture did not produce a working SharePoint session'
            if (Confirm-Skip 'sharepoint' $consequence) { return }
            continue
        }

        $node | Add-Member -NotePropertyName 'cookie'            -NotePropertyValue $got     -Force
        $node | Add-Member -NotePropertyName 'obtainedAt'        -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
        $node | Add-Member -NotePropertyName 'browserProfileDir' -NotePropertyValue $profDir -Force
        Show-SecretShape 'sharepoint.cookie' $got
        Write-Ok 'verified against the tenant during capture'
        Write-Wrapped "Refresh it any time with: Setup-JiraAiFix.ps1 -Section sharepoint - the profile at $profDir keeps the sign-in." '    ' 'DarkGray'
        Set-Status 'sharepoint' 'verified' -Detail 'captured from the browser, proved live'
        return
    }
}

function Invoke-AppEnvSection {
    Write-Banner 'Optional   i21 app environments'

    Write-FieldInfo -Name 'appEnv' `
        -What 'One or more running i21 environments the runbook may sign in to and drive: a URL, whether it is a prod or a dev environment, and a browser profile that keeps the sign-in so later runs need no typing.' `
        -Where 'S1.7a reproduces symptoms only the client can raise - a dialog with no text in it, a column that renders blank while the query returns the value, a client-side script error, a document that renders wrong. S1.7c reads what code the environment is actually serving, which is the only way to see a hand-applied patch: a database reports its own build, it can never report the application build.' `
        -Without 'Those tickets cannot be reproduced at all. The run still exercises every cheaper layer first, and only then - at S1.8b, carrying a ledger of what it executed and what each layer produced - does it ask for an environment and stop. Nothing is guessed, and no gap is silent.' `
        -Notes @(
            'Give it both a prod and a dev environment where both exist. Comparing them is what separates "this is a live defect" from "the fix is already in dev and has not reached prod".',
            'A prod entry is only ever read from. New transactions are created on dev or on a restored copy, never on a customer environment.',
            'Sign-in happens once, in a visible browser, so you complete SSO and MFA by hand. The profile keeps it and every run after that is headless.',
            'A password is optional and is not needed while the profile holds the session. Leave it blank unless you want unattended re-login.'
        )

    $node = Get-CfgNode 'appEnv'
    $consequence = 'Client-raised symptoms cannot be reproduced. S1.8b asks for an environment and stops, after showing what it did test.'

    Write-Host ''
    if (-not (Read-YesNo 'Configure an i21 app environment now?' $false)) {
        if (Confirm-Skip 'appEnv' $consequence) { return }
    }

    $added = 0
    $proved = 0
    while ($true) {
        $key = Read-Text 'Short name for this environment (e.g. prod, dev, sucafina-te)' ''
        if (Test-IsBack $key) { break }
        if (-not $key) {
            Write-Bad 'a name is needed - it is how the runbook and you refer to this environment'
            if (Read-YesNo 'Try again?' $true) { continue }
            break
        }
        $key = ($key.Trim() -replace '[^A-Za-z0-9._-]', '-')

        $entry = Get-CfgSubNode $node $key
        $url = Read-Url 'Base URL (e.g. https://host/2710DEV)' ([string] $entry.baseUrl)
        if (Test-IsBack $url) { break }

        Write-Host ''
        Write-Host '  Which kind of environment is this?' -ForegroundColor White
        Write-Wrapped 'It decides how the runbook is allowed to use it. A prod environment is observed only; a dev environment is where new transactions and fix testing happen.' '    ' 'DarkGray'
        $kind = Read-Option -Options @(
            [pscustomobject] @{ Key = 'prod'; Label = 'production or a customer environment - read only, never written to' }
            [pscustomobject] @{ Key = 'dev';  Label = 'dev / test / a restored copy - safe to exercise' }
        ) -Default 'dev'

        $profDir = [string] $entry.browserProfileDir
        if (-not $profDir) { $profDir = Join-Path $env:USERPROFILE ".jira-ai-appenv-$key-browser" }

        # No -RequireCookie here. The helpdesk and SharePoint sections know which
        # cookie proves a session; an i21 environment's is deployment-specific, so
        # naming one would be a guess that rejects a good capture. Probing as soon
        # as any cookie appears costs a request and never rejects a live session.
        $got = Invoke-BrowserCookieCapture -BaseUrl $url -ProfileDir $profDir `
            -BrowserPath ([string] $entry.browserPath) -ConfigKey "appEnv.$key" `
            -SignInHint 'Sign in to i21 in the window that just opened, including MFA if it is prompted.'

        $entry | Add-Member -NotePropertyName 'baseUrl'          -NotePropertyValue $url     -Force
        $entry | Add-Member -NotePropertyName 'kind'             -NotePropertyValue $kind    -Force
        $entry | Add-Member -NotePropertyName 'browserProfileDir' -NotePropertyValue $profDir -Force
        $entry | Add-Member -NotePropertyName 'obtainedAt'       -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
        $added++

        if ($got) {
            $entry | Add-Member -NotePropertyName 'cookie' -NotePropertyValue $got -Force
            Show-SecretShape "appEnv.$key.cookie" $got
            Write-Ok "$key - session proved live during capture"
            $proved++
        }
        else {
            # A failed probe is not a failed sign-in. Playwright drives this profile
            # directly, so a profile that was signed in is still worth keeping even
            # when no cookie could be proved over plain HTTP - which is the normal
            # outcome for an app that keeps its session anywhere but a cookie.
            Write-Warn "$key - no session cookie could be proved from that profile"
            Write-Wrapped "The browser profile at $profDir is kept anyway: if you completed the sign-in, the runbook drives that profile directly and does not need the cookie. What it loses is the cheap direct fetch S1.7c uses to diff a served asset." '    ' 'DarkGray'
        }

        Write-Host ''
        if (-not (Read-YesNo 'Add another environment?' $false)) { break }
    }

    if ($added -eq 0) {
        if (Confirm-Skip 'appEnv' $consequence) { return }
        Set-Status 'appEnv' 'skipped' -Consequence $consequence -Kind 'not-yet'
        return
    }

    $kinds = @()
    foreach ($p in $node.PSObject.Properties) { $kinds += [string] $p.Value.kind }
    if (($kinds -notcontains 'prod') -or ($kinds -notcontains 'dev')) {
        Write-Warn 'only one kind of environment is configured'
        Write-Wrapped 'S1.7c can still reproduce and read deployed assets. What it cannot do with one kind is the prod-versus-dev comparison, which is the check that catches a fix already sitting in dev that prod has never received. Add the other kind whenever you have one: Setup-JiraAiFix.ps1 -Section appenv' '    ' 'DarkGray'
    }

    Write-Wrapped 'Refresh or add environments any time with: Setup-JiraAiFix.ps1 -Section appenv - the saved profiles keep the sign-ins.' '    ' 'DarkGray'
    if ($proved -gt 0) {
        Set-Status 'appEnv' 'verified' -Detail "$added environment(s), $proved with a proved session"
    }
    else {
        Set-Status 'appEnv' 'partial' -Detail "$added environment(s) saved, none with a proved session cookie" `
            -Consequence 'Runtime reproduction should still work through the saved browser profile. Direct asset fetches in S1.7c will not.'
    }
}

function Invoke-I21ConnectSection {
    Write-Banner 'Optional   i21 Connect - build number to branch'

    Write-FieldInfo -Name 'i21connect' `
        -What 'A signed-in session for i21 Connect, whose release list maps a build number to the branch that produced it and to when it was built.' `
        -Where 'S1.5a resolves every build stamp a ticket carries - the build field, the description, comments, the environment field, and the version read out of a restored database - to the branch that produced it. S1.5 then targets that branch instead of inferring it, and S1.7c uses the build time to tell whether an environment is behind its own branch.' `
        -Without 'S1.5 falls back to parsing the stamp. That works when the token is the branch (26.3ProdSucafina.0824.318) and fails when it is not - and the mainline shape is exactly the one it cannot recover: 24.22.0824.5121 is built from 24.2Dev, and 22.12.0829.4808 from 22.1Dev. The run records BUILD_BRANCH UNRESOLVED and discloses the fallback rather than asserting a branch it guessed.' `
        -Notes @(
            'It also settles which kind of environment a ticket was reported on. A JIRA is often reported on a Dev build and the description is not reliable about that - the resolved branch is.',
            'Same sign-in mechanism as the helpdesk and SharePoint sections: one dedicated browser profile, signed in once.',
            'If you already know the endpoint the release page itself calls, put it in releaseApi and every lookup becomes a single request instead of a driven page. Leave it blank and the runbook discovers it on a first headed run.'
        )

    $node = Get-CfgNode 'i21connect'
    $consequence = 'Build numbers cannot be resolved to branches. S1.5 falls back to parsing, which cannot recover a mainline stamp, and the run discloses BUILD_BRANCH UNRESOLVED.'

    Write-Host ''
    while ($true) {
        if (-not (Read-YesNo 'Configure i21 Connect now?' $false)) {
            if (Confirm-Skip 'i21connect' $consequence) { return }
            continue
        }

        $urlDefault = [string] $node.baseUrl
        if (-not $urlDefault) { $urlDefault = 'https://i21connect.com' }
        $url = Read-Url 'i21 Connect base URL' $urlDefault -Example 'https://i21connect.com'
        if (Test-IsBack $url) { return }

        $profDir = [string] $node.browserProfileDir
        if (-not $profDir) { $profDir = Join-Path $env:USERPROFILE '.jira-ai-i21connect-browser' }

        $got = Invoke-BrowserCookieCapture -BaseUrl $url -ProfileDir $profDir `
            -BrowserPath ([string] $node.browserPath) -ConfigKey 'i21connect' `
            -SignInHint 'Sign in to i21 Connect in the window that just opened - the corporate sign-in, including MFA if prompted.'

        $node | Add-Member -NotePropertyName 'baseUrl'          -NotePropertyValue $url     -Force
        $node | Add-Member -NotePropertyName 'browserProfileDir' -NotePropertyValue $profDir -Force
        $node | Add-Member -NotePropertyName 'obtainedAt'       -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force

        Write-Host ''
        $api = Read-Text 'Release-list API endpoint, if you know it (leave blank to have the runbook discover it)' ([string] $node.releaseApi)
        if (-not (Test-IsBack $api)) {
            if ($api) { $node | Add-Member -NotePropertyName 'releaseApi' -NotePropertyValue ($api.Trim()) -Force }
        }

        if ($got) {
            $node | Add-Member -NotePropertyName 'cookie' -NotePropertyValue $got -Force
            Show-SecretShape 'i21connect.cookie' $got
            Write-Ok 'session proved live during capture'
            Write-Wrapped "Refresh it any time with: Setup-JiraAiFix.ps1 -Section i21connect - the profile at $profDir keeps the sign-in." '    ' 'DarkGray'
            Set-Status 'i21connect' 'verified' -Detail 'captured from the browser, proved live'
            return
        }

        Write-Warn 'no session cookie could be proved from that profile'
        Write-Wrapped "The profile at $profDir is kept: the release list is a single-page app, so the runbook can drive that profile directly even when no cookie proves out over plain HTTP. Only the cheap one-request lookup is lost." '    ' 'DarkGray'
        Set-Status 'i21connect' 'partial' -Detail 'browser profile saved, no proved session cookie' `
            -Consequence 'Lookups drive the page instead of calling an endpoint. Slower, same answer.'
        return
    }
}

function Get-CfgNode {
    param([string] $Name)
    if (-not ($script:Cfg.PSObject.Properties.Name -contains $Name)) {
        $script:Cfg | Add-Member -NotePropertyName $Name -NotePropertyValue (New-Object psobject) -Force
    }
    return $script:Cfg.$Name
}

function Get-CfgSubNode {
    param($Parent, [string] $Name)
    if (-not ($Parent.PSObject.Properties.Name -contains $Name)) {
        $Parent | Add-Member -NotePropertyName $Name -NotePropertyValue (New-Object psobject) -Force
    }
    return $Parent.$Name
}

# Undo what this wizard and its installer created, so a reinstall starts clean.
#
# Two rules shape this. It shows the whole inventory BEFORE deleting anything,
# because an uninstaller that surprises you is worse than no uninstaller. And it
# only claims what this tool actually made: an SSH key that was reused rather
# than generated, the agent service, a staging directory that may hold somebody's
# database - those are listed as left alone, with the command to deal with them
# by hand, rather than quietly removed.
function Invoke-Uninstall {
    param([switch] $Yes)

    Write-Banner 'Uninstall - put this machine back the way it was'

    $home_   = $script:UserHome
    $sshDir  = Join-Path $home_ '.ssh'
    $keyPath = Join-Path $sshDir 'id_i21_tunnel'

    $configs = @()
    $cfgDir  = Split-Path -Parent $ConfigPath
    $cfgName = Split-Path -Leaf $ConfigPath
    if (Test-Path -LiteralPath $cfgDir) {
        $configs = @(Get-ChildItem -LiteralPath $cfgDir -File -Filter "$cfgName*" -ErrorAction SilentlyContinue)
    }

    $skillDirs = @()
    foreach ($rel in @('.claude\skills\jira-ai-fix', '.cursor\skills\jira-ai-fix', '.codex\skills\jira-ai-fix')) {
        $d = Join-Path $home_ $rel
        if (Test-Path -LiteralPath $d) { $skillDirs += $d }
    }

    $keyFiles = @()
    foreach ($k in @($keyPath, "$keyPath.pub")) { if (Test-Path -LiteralPath $k) { $keyFiles += $k } }

    # A key this wizard generated carries the comment it stamps on. One that was
    # reused belongs to the developer and is very likely installed on hosts with
    # nothing to do with this skill, so it is never removed by default.
    $keyIsOurs = $false
    if (Test-Path -LiteralPath "$keyPath.pub") {
        $c = (Get-Content -LiteralPath "$keyPath.pub" -Raw -ErrorAction SilentlyContinue)
        if ($c -and $c.TrimEnd() -match 'i21 tunnels$') { $keyIsOurs = $true }
    }

    Write-Host '  WILL BE REMOVED' -ForegroundColor White
    if ($configs.Count -gt 0) { foreach ($c in $configs) { Write-Host "    config   $($c.FullName)" -ForegroundColor Gray } }
    else { Write-Host '    config   (none found)' -ForegroundColor DarkGray }
    if ($skillDirs.Count -gt 0) { foreach ($d in $skillDirs) { Write-Host "    skill    $d" -ForegroundColor Gray } }
    else { Write-Host '    skill    (not installed anywhere I looked)' -ForegroundColor DarkGray }

    Write-Host ''
    Write-Host '  ASKED ABOUT SEPARATELY' -ForegroundColor White
    if ($keyFiles.Count -gt 0) {
        if ($keyIsOurs) { $tag = 'generated by this wizard' } else { $tag = 'NOT generated here - reused, so probably yours' }
        foreach ($k in $keyFiles) { Write-Host "    ssh key  $k  ($tag)" -ForegroundColor Gray }
    }
    else { Write-Host "    ssh key  (none at $keyPath)" -ForegroundColor DarkGray }

    Write-Host ''
    Write-Host '  LEFT ALONE - not ours to undo' -ForegroundColor White
    Write-Wrapped 'Public keys already installed on jump hosts. Delete the i21 tunnels line by hand if you want them gone.' '    ' 'DarkGray'
    Write-Wrapped 'The OpenSSH Authentication Agent service, if this wizard enabled it. Other tools use that service, so switching it off again could break them.' '    ' 'DarkGray'
    Write-Wrapped 'Any backup staging directory you asked it to create, and every database restored by a run. Those hold data; deleting them is your call.' '    ' 'DarkGray'
    Write-Wrapped 'Your ~/.ssh/config, ~/.atlassian-token, and anything else this wizard only ever read.' '    ' 'DarkGray'
    Write-Wrapped 'The dedicated browser profiles under your user folder (.jira-ai-helpdesk-browser, .jira-ai-sharepoint-browser, .jira-ai-appenv-*-browser, .jira-ai-i21connect-browser). They hold live sign-ins, so deleting them is your call: rmdir /s each one you want gone.' '    ' 'DarkGray'

    Write-Host ''
    if (-not $Yes) {
        if (-not (Read-YesNo 'Remove the config and the installed skill?' $false)) {
            Write-Note 'nothing was removed'
            return
        }
    }

    $removed = 0
    $failed  = 0

    foreach ($c in $configs) {
        try { Remove-Item -LiteralPath $c.FullName -Force -ErrorAction Stop; Write-Ok "removed $($c.Name)"; $removed++ }
        catch { Write-Bad "could not remove $($c.Name): $($_.Exception.Message)"; $failed++ }
    }

    foreach ($d in $skillDirs) {
        try { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction Stop; Write-Ok "removed $d"; $removed++ }
        catch {
            Write-Bad "could not remove $d : $($_.Exception.Message)"
            Write-Wrapped 'Close anything holding those files open - an editor, or an agent with the skill loaded - and run this again.' '    ' 'Yellow'
            $failed++
        }
    }

    if ($keyFiles.Count -gt 0) {
        Write-Host ''
        if (-not $keyIsOurs) { Write-Warn 'that key was reused, not generated here - deleting it would break anything else that uses it' }
        $dropKey = $false
        if ($Yes) { $dropKey = $true } else { $dropKey = Read-YesNo 'Also delete the SSH key pair?' $false }
        if ($dropKey) {
            # Out of the agent first, or it lingers there with no file behind it.
            $null = Invoke-Probe 'ssh-add' @('-d', $keyPath) 20
            foreach ($k in $keyFiles) {
                try { Remove-Item -LiteralPath $k -Force -ErrorAction Stop; Write-Ok "removed $k"; $removed++ }
                catch { Write-Bad "could not remove $k : $($_.Exception.Message)"; $failed++ }
            }
        }
        else { Write-Note 'ssh key left in place' }
    }

    Write-Host ''
    if ($failed -eq 0) {
        Write-Ok "uninstall complete - $removed item(s) removed"
        Write-Wrapped 'A fresh install now starts from nothing: unzip the package and double-click Install-JiraAiFix.cmd.' '    ' 'Gray'
    }
    else { Write-Bad "$removed removed, $failed could not be removed - see above" }
}

function Invoke-VerifyAll {
    Write-Banner 'Verification'

    $mcp = Get-McpStatus
    Write-Host '  MCP servers' -ForegroundColor White
    foreach ($n in @('atlassian', 'azure-devops', 'playwright')) {
        if ($mcp.ContainsKey($n)) { Write-Ok "$n - present in an MCP config" }
        else { Write-Warn "$n - not found in ~/.claude.json or ~/.cursor/mcp.json" }
    }
    Write-Note 'a server in the config can still be unauthenticated - run /mcp in your IDE to confirm'
    if ($mcp.ContainsKey('atlassian')) { Set-Status 'mcp.atlassian' 'configured' -Detail 'present in MCP config' }
    else { Set-Status 'mcp.atlassian' 'failed' -Detail 'not configured - the runbook cannot read Jira without it' }

    Write-Host ''
    Write-Host '  Command-line tools' -ForegroundColor White
    foreach ($t in @('git', 'ssh', 'sqlcmd')) {
        if (Get-Command $t -ErrorAction SilentlyContinue) { Write-Ok "$t - found" }
        else { Write-Warn "$t - not on PATH" }
    }

    if ($script:Cfg.PSObject.Properties.Name -contains 'atlassian') {
        $a = $script:Cfg.atlassian
        if ($a.apiToken -and $a.email) {
            Write-Host ''
            Write-Host '  Atlassian' -ForegroundColor White
            $site = [string] $a.siteUrl
            if (-not $site) { $site = 'https://irely.atlassian.net' }
            Test-Atlassian $site ([string] $a.email) ([string] $a.apiToken)
        }
    }

    if ($script:Cfg.PSObject.Properties.Name -contains 'sqlServer') {
        $s = $script:Cfg.sqlServer
        if ($s.server) {
            Write-Host ''
            Write-Host '  SQL Server' -ForegroundColor White
            try {
                $v = Invoke-SqlScalar (New-SqlConnectionString ([string]$s.server) ([string]$s.auth) ([string]$s.user) ([string]$s.password)) 'SELECT @@VERSION'
                Write-Ok (($v -split "`n")[0].Trim())
                Set-Status 'sqlServer' 'verified' -Detail "$($s.server) reachable"
            }
            catch { Write-Bad "could not connect: $($_.Exception.Message)"; Set-Status 'sqlServer' 'failed' -Detail 'connection failed' }
        }
    }

    # Both of these are browser sessions, so there is nothing to test here without
    # opening a browser - which is what their own sections do. Report what is on
    # file and how old it is, and let the operator decide whether to refresh.
    Write-Host ''
    Write-Host '  App environments and i21 Connect' -ForegroundColor White
    if ($script:Cfg.PSObject.Properties.Name -contains 'appEnv') {
        $envs = @($script:Cfg.appEnv.PSObject.Properties)
        if ($envs.Count -gt 0) {
            foreach ($p in $envs) {
                $k = [string] $p.Value.kind
                if (-not $k) { $k = 'kind not set' }
                $when = [string] $p.Value.obtainedAt
                if (-not $when) { $when = 'unknown date' }
                Write-Ok "appEnv.$($p.Name) - $k - $([string] $p.Value.baseUrl) (captured $when)"
            }
            $kinds = @($envs | ForEach-Object { [string] $_.Value.kind })
            if (($kinds -notcontains 'prod') -or ($kinds -notcontains 'dev')) {
                Write-Warn 'only one kind configured - the prod-versus-dev comparison in S1.7c cannot run'
            }
        }
        else { Write-Warn 'appEnv - section present but no environments in it' }
    }
    else { Write-Warn 'appEnv - not configured; client-raised symptoms cannot be reproduced' }

    if (($script:Cfg.PSObject.Properties.Name -contains 'i21connect') -and $script:Cfg.i21connect.browserProfileDir) {
        $when = [string] $script:Cfg.i21connect.obtainedAt
        if (-not $when) { $when = 'unknown date' }
        $how = 'drives the page'
        if ($script:Cfg.i21connect.releaseApi) { $how = 'has a release endpoint' }
        Write-Ok "i21connect - $how (captured $when)"
    }
    else { Write-Warn 'i21connect - not configured; build numbers fall back to parsing and may not resolve' }
    Write-Note 'both are browser sessions and expire - refresh with -Section appenv / -Section i21connect'
}

# The section list, in order, with the state that counts as "done".
$script:SectionOrder = @(
    [pscustomobject] @{ Key = 'i21.repoRoot';            Name = 'repo';      Label = 'Repo root' }
    [pscustomobject] @{ Key = 'atlassian';               Name = 'atlassian'; Label = 'Atlassian' }
    [pscustomobject] @{ Key = 'sqlServer';               Name = 'sql';       Label = 'SQL Server' }
    [pscustomobject] @{ Key = 'sqlServer.restore';       Name = 'restore';   Label = 'Restore + disk space' }
    [pscustomobject] @{ Key = 'sqlServer.knownServers';  Name = 'servers';   Label = 'Known servers' }
    [pscustomobject] @{ Key = 'ssh';                     Name = 'ssh';       Label = 'Passwordless SSH' }
    [pscustomobject] @{ Key = 'helpdesk';                Name = 'helpdesk';  Label = 'Helpdesk cookie' }
    [pscustomobject] @{ Key = 'sharepoint';              Name = 'sharepoint'; Label = 'SharePoint cookie' }
    [pscustomobject] @{ Key = 'appEnv';                  Name = 'appenv';    Label = 'i21 app environments' }
    [pscustomobject] @{ Key = 'i21connect';              Name = 'i21connect'; Label = 'i21 Connect (build to branch)' }
)

# What still needs attention: never touched, failed, only partly working, or deferred.
# 'verified' and 'not-applicable' are settled and are not revisited.
function Get-Unfinished {
    $out = @()
    foreach ($s in $script:SectionOrder) {
        $st = $script:Status[$s.Key]
        if (-not $st) { $out += ,([pscustomobject] @{ Section = $s; State = 'not started' }); continue }
        if (@('failed', 'partial') -contains $st.state) { $out += ,([pscustomobject] @{ Section = $s; State = $st.state }); continue }
        if ($st.state -eq 'skipped' -and $st.kind -ne 'not-applicable') { $out += ,([pscustomobject] @{ Section = $s; State = 'skipped earlier' }) }
    }
    return $out
}

function Invoke-Section {
    param([string] $Name)
    switch ($Name) {
        'repo'      { Invoke-RepoSection }
        'atlassian' { Invoke-AtlassianSection }
        'sql'       { Invoke-SqlSection }
        'restore'   { Invoke-RestoreSection }
        'servers'   { Invoke-ServersSection }
        'ssh'       { Invoke-SshSection }
        'helpdesk'  { Invoke-HelpdeskSection }
        'sharepoint' { Invoke-SharePointSection }
        'appenv'    { Invoke-AppEnvSection }
        'i21connect' { Invoke-I21ConnectSection }
        'verify'    { Invoke-VerifyAll }
    }
}

function Invoke-Resume {
    Write-Banner 'Resume - picking up where the last run left off'

    # Anything not in the unfinished list is settled for resume purposes - including
    # 'configured', which is set but was not provable here. It still gets shown, so no
    # section silently disappears from both lists.
    $todo = Get-Unfinished
    $todoKeys = @($todo | ForEach-Object { $_.Section.Key })
    $done = @()
    foreach ($s in $script:SectionOrder) {
        $st = $script:Status[$s.Key]
        if ($st -and ($todoKeys -notcontains $s.Key)) { $done += $s }
    }

    if ($done.Count -gt 0) {
        Write-Host '  Already settled, and not asked about again:' -ForegroundColor Green
        foreach ($s in $done) { Write-Host "    $($s.Label)  -  $($script:Status[$s.Key].state)" -ForegroundColor DarkGray }
        Write-Host ''
    }
    if ($todo.Count -eq 0) {
        Write-Ok 'nothing left to do - every section is settled'
        Write-Note 'use option 12 to re-test everything, or pick a section to change it'
        return
    }

    Write-Host '  Still needs attention:' -ForegroundColor Yellow
    foreach ($t in $todo) {
        $line = "    $($t.Section.Label)  -  $($t.State)"
        Write-Host $line -ForegroundColor Yellow
        $st = $script:Status[$t.Section.Key]
        if ($st -and $st.detail) { Write-Wrapped $st.detail '        ' 'DarkGray' }
    }
    Write-Host ''
    if (-not (Read-YesNo "Work through those $($todo.Count) now?" $true)) { return }

    foreach ($t in $todo) { Invoke-Section $t.Section.Name }
    Invoke-VerifyAll
}

# Single exit point, so the caller - a person or an AI agent that launched this in its own
# window - gets an unambiguous signal without having to parse the screen.
#
#   0  saved, usable, nothing failed          -> setup is complete
#   2  saved, but verdict NOT-READY           -> a foundation is missing, must resume
#   3  saved and usable, but a section failed -> resume recommended, not blocking
#   4  exited without saving                  -> nothing was recorded
function Complete-Wizard {
    param([switch] $Unsaved)

    $verdict = 'UNSAVED'
    $failed = 0
    $code = 4

    if (-not $Unsaved) {
        $verdict = Get-Verdict
        foreach ($k in $script:Status.Keys) {
            if ($script:Status[$k].state -eq 'failed') { $failed++ }
        }
        if ($verdict -eq 'NOT-READY') { $code = 2 }
        elseif ($failed -gt 0)        { $code = 3 }
        else                          { $code = 0 }
    }

    Write-Host ''
    Write-Rule '='
    # A single parseable line, for whatever launched this.
    Write-Host "  SETUP-RESULT verdict=$verdict failed=$failed exit=$code" -ForegroundColor White
    Write-Rule '='

    switch ($code) {
        0 { Write-Wrapped 'Setup is complete. Restart your IDE so it picks up the skill, then open a repo under your i21 root and name a ticket: "jira-ai-fix AP-24818".' '  ' 'Green' }
        2 { Write-Wrapped 'Setup is NOT complete - a foundation is missing, so no run can finish yet. Re-run this wizard with -Resume to fill it in; nothing already verified will be asked again.' '  ' 'Red' }
        3 { Write-Wrapped 'Setup is usable, but at least one section failed its check. Re-run with -Resume to retry just those; everything verified is left alone.' '  ' 'Yellow' }
        4 { Write-Wrapped 'Nothing was saved, so no configuration changed. Re-run the wizard whenever you are ready.' '  ' 'DarkGray' }
    }
    Write-Host ''

    if ($PauseOnExit) {
        Write-Host '  Press Enter to close this window...' -ForegroundColor DarkGray
        try { [void] (Read-Host) } catch { }
    }
    exit $code
}

function Show-Status {
    Write-Banner "Setup status   -   $(Get-Verdict)"
    if ($script:Status.Count -eq 0) { Write-Note 'nothing recorded yet'; return }
    foreach ($k in $script:Status.Keys) {
        $e = $script:Status[$k]
        $line = ("  {0,-26} {1,-16}" -f $k, $e.state)
        if ($e.detail) { $line += " $($e.detail)" }
        $color = 'Gray'
        if ($e.state -eq 'verified')  { $color = 'Green' }
        if ($e.state -eq 'partial')   { $color = 'Yellow' }
        if ($e.state -eq 'skipped')   { $color = 'Yellow' }
        if ($e.state -eq 'failed')    { $color = 'Red' }
        Write-Host $line -ForegroundColor $color
        if ($e.consequence) { Write-Wrapped $e.consequence '      -> ' 'DarkGray' }
    }

    # Always say what to do next, so a partial setup is never a dead end.
    $todo = Get-Unfinished
    Write-Host ''
    if ($todo.Count -eq 0) {
        Write-Ok 'every section is settled'
    }
    else {
        Write-Host "  $($todo.Count) section(s) still need attention:" -ForegroundColor Yellow
        foreach ($t in $todo) { Write-Host "    $($t.Section.Label)  ($($t.State))" -ForegroundColor Yellow }
        Write-Host ''
        Write-Wrapped 'Pick "r" from the menu to work through just those, or re-run this wizard later with -Resume. Nothing you have already verified will be asked again.' '  ' 'Gray'
    }
}

# =============================================================================== main

if (-not $ConfigPath) { $ConfigPath = Join-Path $script:UserHome '.jira-ai-config.json' }
if (-not $TemplatePath) {
    foreach ($c in @(
        (Join-Path $PSScriptRoot 'jira-ai-config.example.json'),
        (Join-Path (Join-Path $PSScriptRoot 'config') 'jira-ai-config.example.json'),
        (Join-Path (Join-Path $PSScriptRoot 'skill') 'config\jira-ai-config.example.json')
    )) { if (Test-Path -LiteralPath $c) { $TemplatePath = $c; break } }
}

Write-Rule '='
Write-Host '  JIRA-AI-Fix   configuration wizard' -ForegroundColor White
Write-Rule '='
Write-Wrapped "This gathers what the JIRA-AI-Fix runbook needs, and explains for every input what it is for, where the runbook uses it, and what a run loses without it." '  '
Write-Host ''
Write-Wrapped "Nothing is mandatory except the repo root. Skipping a section removes one capability - the wizard tells you which, and records it so every later run says so out loud instead of quietly proving less." '  ' 'DarkGray'
Write-Host ''
Write-Wrapped "Secrets you type are never echoed and go only to the config file. They do not pass through any AI context." '  ' 'DarkGray'
Write-Host ''
Write-Host "  config: $ConfigPath" -ForegroundColor DarkGray
Write-Host ''

# Before Import-Config on purpose. Loading the config can offer to start fresh
# and RENAME the existing file to a .bak - which is absurd on the way to deleting
# it, and it happened: an uninstall run showed the live config already renamed
# before the inventory was even printed. Uninstall needs no config and no git.
if ($Uninstall) {
    Invoke-Uninstall -Yes:$Yes
    Complete-Wizard -Unsaved
}

$script:Cfg = Import-Config -Path $ConfigPath -Template $TemplatePath

# Before any section, because every one of them that matters shells out to git,
# and a missing git otherwise shows up much later disguised as a network or
# credentials problem.
Write-Host ''
Assert-Git

if ($Section) {
    Invoke-Section $Section
    Save-Config -Path $ConfigPath -Cfg $script:Cfg
    Show-Status
    Complete-Wizard
}

if ($Resume) {
    Invoke-Resume
    Save-Config -Path $ConfigPath -Cfg $script:Cfg
    Show-Status
    Complete-Wizard
}

# An interrupted or partly-failed previous run should not have to be restarted from the top.
$pending = Get-Unfinished
if ($script:Status.Count -gt 0 -and $pending.Count -gt 0 -and $pending.Count -lt $script:SectionOrder.Count) {
    Write-Host ''
    Write-Warn "a previous run left $($pending.Count) section(s) unfinished"
    foreach ($t in $pending) { Write-Host "    $($t.Section.Label)  ($($t.State))" -ForegroundColor Yellow }
    Write-Host ''
    if (Read-YesNo 'Pick up from there instead of starting over?' $true) {
        Invoke-Resume
        Save-Config -Path $ConfigPath -Cfg $script:Cfg
        Show-Status
        Complete-Wizard
    }
}

while ($true) {
    Write-Host ''
    Write-Rule
    Write-Host '  What would you like to do?' -ForegroundColor White
    Write-Host ''
    Write-Host '   1  Configure everything, in order   (recommended)' -ForegroundColor Gray
    Write-Host '   2  Repo root            - required for any run'    -ForegroundColor Gray
    Write-Host '   3  Atlassian            - attachment evidence'     -ForegroundColor Gray
    Write-Host '   4  SQL Server           - data-dependent tickets'  -ForegroundColor Gray
    Write-Host '   5  Restore + disk space'                           -ForegroundColor Gray
    Write-Host '   6  Known servers        - skip whole restores'     -ForegroundColor Gray
    Write-Host '   7  Passwordless SSH     - for tunnels'             -ForegroundColor Gray
    Write-Host '   8  Helpdesk cookie      - optional'                -ForegroundColor Gray
    Write-Host '   9  SharePoint cookie    - optional'                -ForegroundColor Gray
    Write-Host '  10  i21 app environments - client-raised symptoms'  -ForegroundColor Gray
    Write-Host '  11  i21 Connect          - build number to branch'  -ForegroundColor Gray
    Write-Host '  12  Verify everything now'                          -ForegroundColor Gray
    Write-Host '   r  Resume  - only what is unfinished or failed'     -ForegroundColor Gray
    Write-Host '   s  Show status'                                    -ForegroundColor Gray
    Write-Host '   u  Uninstall  - remove the config and the skill'    -ForegroundColor Gray
    Write-Host '   w  Save and exit'                                  -ForegroundColor Green
    Write-Host '   q  Quit without saving'                            -ForegroundColor DarkGray
    Write-Host ''
    $choice = Read-Host '  Choice'

    # Read-Host returns $null - not '' - once a redirected stdin has run dry, and
    # $null.Trim() is a terminating error, so an exhausted pipe has to be caught
    # here rather than in the switch's default branch: the switch never gets to
    # run. Left unhandled this threw, the menu redrew, and it spun - 1.8 MB of
    # output in a 60-second test run.
    if ([string]::IsNullOrWhiteSpace($choice)) {
        Assert-InputAlive
        Write-Warn 'pick a number, or s / u / w / q'
        continue
    }

    # A terminating error inside any section used to end the whole wizard, and it
    # ended before Save-Config had run, so the session's answers died with it.
    # Catch it at the menu instead: $script:Cfg still holds every answer, so the
    # operator retries the section or saves what they already have. `exit` is
    # flow control, not an exception, so Complete-Wizard still exits from here.
    try {
    switch ($choice.Trim().ToLower()) {
        '1' {
            Invoke-RepoSection; Invoke-AtlassianSection; Invoke-SqlSection
            Invoke-RestoreSection; Invoke-ServersSection; Invoke-SshSection
            Invoke-HelpdeskSection; Invoke-SharePointSection
            Invoke-AppEnvSection; Invoke-I21ConnectSection; Invoke-VerifyAll
            Save-Config -Path $ConfigPath -Cfg $script:Cfg
            Show-Status
            Complete-Wizard
        }
        '2' { Invoke-RepoSection }
        '3' { Invoke-AtlassianSection }
        '4' { Invoke-SqlSection }
        '5' { Invoke-RestoreSection }
        '6' { Invoke-ServersSection }
        '7' { Invoke-SshSection }
        '8' { Invoke-HelpdeskSection }
        '9' { Invoke-SharePointSection }
        '10' { Invoke-AppEnvSection }
        '11' { Invoke-I21ConnectSection }
        '12' { Invoke-VerifyAll }
        'r' { Invoke-Resume }
        's' { Show-Status }
        'u' { Invoke-Uninstall }
        'w' {
            Save-Config -Path $ConfigPath -Cfg $script:Cfg
            Show-Status
            Complete-Wizard
        }
        'q' {
            if (Read-YesNo 'Quit without saving anything from this session?' $false) { Complete-Wizard -Unsaved }
        }
        default { Write-Warn 'pick a number, or s / u / w / q'; Assert-InputAlive }
    }
    }
    catch {
        Write-Bad "that section stopped on an unexpected error: $($_.Exception.Message)"
        Write-Wrapped 'Nothing was lost - every answer so far is still held in this session. Retry the section, or press w to save what you have.' '    ' 'Yellow'
    }
}
