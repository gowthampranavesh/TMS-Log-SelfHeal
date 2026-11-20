<#
.SYNOPSIS
    Generates consolidated CSV Remediation & Audit Report.
#>

function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [object[]]$RemediationResults = @()
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $reportPath = Join-Path -Path $OutputDirectory -ChildPath "RemediationAudit_${stamp}.csv"

    @($RemediationResults) | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
    return $reportPath
}
