<#
.SYNOPSIS
    Structured logging helper for TMS-Log-SelfHeal (PowerShell 5.1 compatible).
#>

$script:AgentLogFile = $null

function Initialize-AgentLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $false)]
        [string]$Prefix = 'tms-log-agent'
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyyMMdd')
    $script:AgentLogFile = Join-Path -Path $LogDirectory -ChildPath "${Prefix}_${stamp}.log"
    return $script:AgentLogFile
}

function Write-AgentLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $false)]
        [string]$Component = 'Agent',

        [Parameter(Mandatory = $false)]
        [string]$LogFile = $script:AgentLogFile
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
    $entry = "[$timestamp] [$Level] [$Component] $Message"

    switch ($Level) {
        'ERROR' { Write-Warning $entry }
        'WARN'  { Write-Warning $entry }
        default { Write-Verbose $entry }
    }

    if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
        $parent = Split-Path -Path $LogFile -Parent
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -LiteralPath $LogFile -Value $entry -Encoding UTF8
    }
}
