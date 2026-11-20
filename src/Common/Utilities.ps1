<#
.SYNOPSIS
    Shared utilities: config loader, single-instance mutex/lock, path helpers, retention cleanup.
#>

function Import-AgentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "Agent configuration file not found: $ConfigPath"
    }

    $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
    $config = $raw | ConvertFrom-Json

    if ($null -eq $config) {
        throw "Failed to parse AgentConfig JSON at: $ConfigPath"
    }

    return $config
}

function Resolve-RepoPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$PathValue
    )

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }
    return Join-Path -Path $RepoRoot -ChildPath $PathValue
}

function Enter-AgentExecutionLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockFilePath
    )

    $parent = Split-Path -Path $LockFilePath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LockFilePath) {
        try {
            $existing = Get-Content -LiteralPath $LockFilePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($existing -and $existing.Pid) {
                $proc = Get-Process -Id ([int]$existing.Pid) -ErrorAction SilentlyContinue
                if ($proc) {
                    throw "Another instance of TMS-Log-SelfHeal is already running (PID: $($existing.Pid), Started: $($existing.StartedUtc))."
                }
            }
        }
        catch {
            if ($_.Exception.Message -like 'Another instance*') {
                throw
            }
            # Stale or unreadable lock file; overwrite safely
        }
    }

    $lockPayload = [PSCustomObject]@{
        Pid        = $PID
        Hostname   = $env:COMPUTERNAME
        StartedUtc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 3

    Set-Content -LiteralPath $LockFilePath -Value $lockPayload -Encoding UTF8
    return $LockFilePath
}

function Exit-AgentExecutionLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LockFilePath
    )

    if (Test-Path -LiteralPath $LockFilePath) {
        Remove-Item -LiteralPath $LockFilePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-FileRetentionCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath,

        [Parameter(Mandatory = $true)]
        [int]$RetentionDays,

        [Parameter(Mandatory = $false)]
        [string[]]$IncludePatterns = @('*.log', '*.csv')
    )

    if ($RetentionDays -le 0 -or -not (Test-Path -LiteralPath $DirectoryPath)) {
        return 0
    }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $removed = 0

    foreach ($pattern in $IncludePatterns) {
        $oldFiles = Get-ChildItem -LiteralPath $DirectoryPath -Filter $pattern -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff }

        foreach ($f in $oldFiles) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    return $removed
}
