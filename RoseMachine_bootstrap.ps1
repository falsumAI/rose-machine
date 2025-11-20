# RoseMachine_bootstrap.ps1
# Single-shot bootstrap for Project ROSE / FalsumAI
# PowerShell 7

#requires -Version 7.0

$root          = Join-Path $env:USERPROFILE "RoseMachine"
$reposRoot     = Join-Path $root "repos"
$logsRoot      = Join-Path $root "logs"
$rcptRoot      = Join-Path $root "receipts"
$bundleRoot    = Join-Path $root "bundles"
$docsRoot      = Join-Path $root "docs"
$licensesRoot  = Join-Path $root "licenses"
$bootstrapRoot = Join-Path $root "bootstrap"

$timestampUtc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHHmmssZ")
$logPath       = Join-Path $logsRoot ("RoseMachine_{0}.log" -f $timestampUtc)

$internalProtocol = [PSCustomObject]@{
    protocolVersion = "MIL1-2025-11-18"
    description     = "Internal bootstrap protocol for RoseMachine."
    author          = "Gregg Anthony Haynes"
    timezone        = [System.TimeZoneInfo]::Local.Id
    createdLocal    = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssK")
}

function Log {
    param(
        [string] $Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string] $Level = "INFO"
    )
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
    $line  = "[{0}] [{1}] {2}" -f $stamp, $Level, $Message
    Write-Host $line
    if (-not (Test-Path $logsRoot)) {
        New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
    }
    Add-Content -Path $logPath -Value $line
}

function Ensure-Directory {
    param([string] $Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Log ("Created directory: {0}" -f $Path)
    }
}

function Check-GitAvailable {
    try {
        git --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Run-Git {
    param(
        [string] $RepoPath,
        [string[]] $Arguments
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "git"
    $psi.WorkingDirectory       = $RepoPath
    $psi.Arguments              = ($Arguments -join " ")
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($stdout.Trim().Length -gt 0) {
        Log ("git {0}`n{1}" -f ($Arguments -join " "), $stdout.Trim())
    }
    if ($proc.ExitCode -ne 0) {
        Log ("git {0} failed with exit code {1}: {2}" -f ($Arguments -join " "), $proc.ExitCode, $stderr.Trim()) "ERROR"
        throw "Git command failed: git $($Arguments -join ' ')"
    }
    return $stdout
}

$repos = @(
    @{
        Name   = "rose-ledger-foundation"
        Url    = "https://github.com/falsumAI/rose-ledger-foundation.git"
        Role   = "ConstitutionAndSpecs"
        Branch = "main"
    },
    @{
        Name   = "rose-coherence-benchmark"
        Url    = "https://github.com/falsumAI/rose-coherence-benchmark.git"
        Role   = "CoherenceMathBenchmark"
        Branch = "main"
    },
    @{
        Name   = "falsumai-core"
        Url    = "https://github.com/falsumAI/falsumai-core.git"
        Role   = "ApplicationCore"
        Branch = "main"
    }
)

Log "RoseMachine bootstrap start."

Ensure-Directory $root
Ensure-Directory $reposRoot
Ensure-Directory $logsRoot
Ensure-Directory $rcptRoot
Ensure-Directory $bundleRoot
Ensure-Directory $docsRoot
Ensure-Directory $licensesRoot
Ensure-Directory $bootstrapRoot

if (-not (Check-GitAvailable)) {
    Log "Git not found on PATH." "ERROR"
    throw "Git not found."
}

$repoStates = @()

foreach ($repo in $repos) {
    $name   = $repo.Name
    $url    = $repo.Url
    $role   = $repo.Role
    $branch = $repo.Branch
    $path   = Join-Path $reposRoot $name

    Log ("Repo {0} ({1}) from {2}" -f $name, $role, $url)

    if (-not (Test-Path $path)) {
        Ensure-Directory $reposRoot
        Log ("Cloning {0}" -f $name)
        Run-Git -RepoPath $reposRoot -Arguments @("clone", $url, $name)
    } else {
        Log ("Updating {0}" -f $name)
        Run-Git -RepoPath $path -Arguments @("fetch", "--all", "--prune")
    }

    try {
        Run-Git -RepoPath $path -Arguments @("checkout", $branch)
    } catch {
        Log ("Branch {0} missing for {1}, creating from origin." -f $branch, $name) "WARN"
        Run-Git -RepoPath $path -Arguments @("checkout", "-b", $branch, "origin/$branch")

    Run-Git -RepoPath $path -Arguments @("pull", "origin", $branch)
    $commit    = (Run-Git -RepoPath $path -Arguments @("rev-parse", "HEAD")).Trim()
    $curBranch = (Run-Git -RepoPath $path -Arguments @("rev-parse", "--abbrev-ref", "HEAD")).Trim()
    $remoteUrl = (Run-Git -RepoPath $path -Arguments @("config", "--get", "remote.origin.url")).Trim()

    Log ("{0} at {1} on {2}" -f $name, $commit, $curBranch)

    Get-ChildItem -Path $path -Recurse -File -Include "LICENSE*", "COPYING*" |
        ForEach-Object {
            $destName = "{0}__{1}" -f $name, $_.Name
            $destPath = Join-Path $licensesRoot $destName
            Copy-Item -Path $_.FullName -Destination $destPath -Force
        }

    Get-ChildItem -Path $path -Recurse -File -Include "*.pdf" |
        ForEach-Object {
            $destName = "{0}__{1}" -f $name, $_.Name
            $destPath = Join-Path $docsRoot $destName
            Copy-Item -Path $_.FullName -Destination $destPath -Force
        }

    $repoStates += [PSCustomObject]@{
        name   = $name
        url    = $remoteUrl
        role   = $role
        path   = $path
        commit = $commit
        branch = $curBranch
    }
}

if ($scriptPath -and (Test-Path $scriptPath)) {
    $scriptHash = (Get-FileHash -Algorithm SHA256 -Path $scriptPath).Hash
} else {
    $scriptHash = ""
    Log "Script path not found for hashing." "WARN"
}

$sysInfo = [PSCustomObject]@{
    machineName   = $env:COMPUTERNAME
    userName      = $env:USERNAME
    osVersion     = [Environment]::OSVersion.VersionString
    psVersion     = $PSVersionTable.PSVersion.ToString()
    rootDirectory = $root
}

function Get-FileHashes {
    param([string] $Directory)
    if (Test-Path $Directory) {
        Get-ChildItem -Path $Directory -File -Recurse | ForEach-Object {
            try {
                $h = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
                $hashes[$_.Name] = $h
            } catch {
                Log ("Failed to hash file {0}: {1}" -f $_.FullName, $_.Exception.Message) "ERROR"
            }
        }
    }
    return $hashes
}

$licenseHashes = Get-FileHashes -Directory $licensesRoot
$docHashes     = Get-FileHashes -Directory $docsRoot

$bundleName = ("RoseMachineBundle_{0}.zip" -f $timestampUtc)
$bundlePath = Join-Path $bundleRoot $bundleName

if (Test-Path $bundlePath) {
    Remove-Item $bundlePath -Force
}

try {
    Compress-Archive -Path (Join-Path $root "*") -DestinationPath $bundlePath -Force
    Log ("Bundle created: {0}" -f $bundlePath)
} catch {
    Log ("Bundle creation failed: {0}" -f $_) "ERROR"
}

if (Test-Path $bundlePath) {
    $bundleHash = (Get-FileHash -Algorithm SHA256 -Path $bundlePath).Hash
} else {
    $bundleHash = ""
    Log "Bundle path not found for hashing." "WARN"
}

$receipt = [PSCustomObject]@{
    RoseReceiptVersion = "1.0"
    CreatedUtc         = $timestampUtc
    Creator            = "Gregg Anthony Haynes (falsumAI)"
    AssistantWitness   = "GPT-5.1 Thinking"
    WorkspaceRoot      = $root
    ScriptPath         = $scriptPath
    ScriptSha256       = $scriptHash
    BundlePath         = $bundlePath
    BundleSha256       = $bundleHash
    InternalProtocol   = $internalProtocol
    System             = $sysInfo
    GitRepositories    = $repoStates
    LicenseHashes      = $licenseHashes
    DocHashes          = $docHashes
    Notes              = "Unified Project ROSE machine snapshot: repos, licenses, docs, and script state."
}

$receiptFileName = ("RoseReceipt_{0}.json" -f $timestampUtc)
$receiptPath     = Join-Path $rcptRoot $receiptFileName

$receipt | ConvertTo-Json -Depth 8 | Out-File -FilePath $receiptPath -Encoding UTF8

try {
    $desktop = [Environment]::GetFolderPath("Desktop")
} catch {
    $desktop = $env:USERPROFILE
    Log ("Desktop path fallback: {0}" -f $desktop) "WARN"
}

try {
    if ($scriptPath -and (Test-Path $scriptPath)) {
        Copy-Item -Path $scriptPath -Destination (Join-Path $desktop (Split-Path $scriptPath -Leaf)) -Force
    }
    if (Test-Path $receiptPath) {
        Copy-Item -Path $receiptPath -Destination (Join-Path $desktop (Split-Path $receiptPath -Leaf)) -Force
    }
    if (Test-Path $bundlePath) {
        Copy-Item -Path $bundlePath -Destination (Join-Path $desktop (Split-Path $bundlePath -Leaf)) -Force
    }
    Log ("Artifacts copied to Desktop.")
} catch {
    Log ("Failed to copy artifacts to Desktop: {0}" -f $_) "WARN"
}

Log "RoseMachine bootstrap complete."
Write-Host "RoseMachine bootstrap complete." -ForegroundColor Cyan
Write-Host ("Workspace root : {0}" -f $root)
Write-Host ("Receipt        : {0}" -f $receiptPath)
Write-Host ("Bundle         : {0}" -f $bundlePath)
Log ("Receipt written: {0}" -f $receiptPath)
    $hashes = @{}
$scriptPath = $MyInvocation.MyCommand.Path
            Log ("License captured: {0}" -f $destName)


