<#
.SYNOPSIS
    Generates consolidated CSV Detection Report across all tracked and scanned loggers.
#>

function Write-DetectionReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $false)]
        [object[]]$TrackingRecords = @(),

        [Parameter(Mandatory = $false)]
        [object[]]$AdditionalFindings = @()
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $reportPath = Join-Path -Path $OutputDirectory -ChildPath "DetectionReport_${stamp}.csv"

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($rec in $TrackingRecords) {
        $rows.Add([PSCustomObject]@{
            ScanDate               = $rec.LastDetectedUtc
            Customer               = $rec.Customer
            Hostname               = $rec.Hostname
            Component              = $rec.Component
            FilePath               = $rec.FilePath
            LoggerName             = $rec.LoggerName
            CurrentLevel           = $rec.CurrentLevel
            FirstDetectedDate      = $rec.FirstDetectedUtc
            DurationHours          = $rec.DurationHours
            RemediationEligibility = if ($rec.CurrentStatus -eq 'ELIGIBLE') { 'ELIGIBLE' } else { $rec.CurrentStatus }
        })
    }

    foreach ($af in $AdditionalFindings) {
        if ($af.Status -in @('SERVER_UNAVAILABLE', 'FILE_NOT_FOUND', 'MANUAL_REVIEW_REQUIRED')) {
            $rows.Add([PSCustomObject]@{
                ScanDate               = $af.ScannedUtc
                Customer               = $af.Customer
                Hostname               = $af.Hostname
                Component              = $af.Component
                FilePath               = $af.FilePath
                LoggerName             = $af.LoggerName
                CurrentLevel           = $af.Level
                FirstDetectedDate      = ''
                DurationHours          = 0
                RemediationEligibility = $af.Status
            })
        }
    }

    $rows | Export-Csv -LiteralPath $reportPath -NoTypeInformation -Encoding UTF8
    return $reportPath
}
