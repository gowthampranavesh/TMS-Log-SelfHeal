<#
.SYNOPSIS
    Updates persistent 48-hour DEBUG tracking state and evaluates remediation eligibility.
#>

function Update-DebugTrackingState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Store,

        [Parameter(Mandatory = $true)]
        [object[]]$ScanFindings,

        [Parameter(Mandatory = $false)]
        [string[]]$UnavailableHostnames = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ScannedHostnames = @(),

        [Parameter(Mandatory = $false)]
        [double]$ThresholdHours = 48,

        [Parameter(Mandatory = $false)]
        [datetime]$CurrentUtc = (Get-Date).ToUniversalTime()
    )

    $nowIso = $CurrentUtc.ToString('o')
    $seenKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($finding in $ScanFindings) {
        if ([string]::IsNullOrWhiteSpace($finding.LoggerName)) { continue }

        $key = Get-TrackingRecordKey -Hostname $finding.Hostname -FilePath $finding.FilePath -LoggerName $finding.LoggerName
        $null = $seenKeys.Add($key)

        $existing = $Store.Records[$key]

        if ($finding.Level -eq 'DEBUG') {
            if ($null -eq $existing -or $existing.CurrentStatus -in @('CLOSED', 'REMEDIATED', 'INACTIVE')) {
                # First detection (or re-enabled after previous closure)
                $Store.Records[$key] = [PSCustomObject]@{
                    Customer          = $finding.Customer
                    Hostname          = $finding.Hostname
                    Component         = $finding.Component
                    FilePath          = $finding.FilePath
                    FileType          = $finding.FileType
                    LoggerName        = $finding.LoggerName
                    CurrentLevel      = 'DEBUG'
                    FirstDetectedUtc  = $nowIso
                    LastDetectedUtc   = $nowIso
                    DurationHours     = 0.0
                    CurrentStatus     = 'DEBUG_DETECTED'
                    RemediationStatus = 'PENDING'
                    LastFileHash      = $finding.FileHash
                }
            }
            else {
                # Retain original FirstDetectedUtc
                $firstDt = [datetime]::Parse($existing.FirstDetectedUtc).ToUniversalTime()
                $hours = [math]::Round(($CurrentUtc - $firstDt).TotalHours, 2)
                $status = if ($hours -ge $ThresholdHours) { 'ELIGIBLE' } else { 'TRACKING' }

                $existing.LastDetectedUtc = $nowIso
                $existing.DurationHours = $hours
                $existing.CurrentLevel = 'DEBUG'
                $existing.CurrentStatus = $status
                $existing.LastFileHash = $finding.FileHash
                $Store.Records[$key] = $existing
            }
        }
        else {
            # Logger changed from DEBUG to INFO (or other non-DEBUG)
            if ($null -ne $existing -and $existing.CurrentStatus -in @('DEBUG_DETECTED', 'TRACKING', 'ELIGIBLE')) {
                $existing.CurrentLevel = $finding.Level
                $existing.LastDetectedUtc = $nowIso
                $existing.CurrentStatus = 'CLOSED'
                $existing.RemediationStatus = 'RESOLVED_EXTERNALLY'
                $Store.Records[$key] = $existing
            }
        }
    }

    # Handle records not seen in this scan:
    # - If server was unavailable, preserve tracking timestamp untouched.
    # - If server WAS scanned and logger/file disappeared, mark INACTIVE.
    foreach ($key in @($Store.Records.Keys)) {
        if ($seenKeys.Contains($key)) { continue }
        $rec = $Store.Records[$key]
        if ($rec.CurrentStatus -notin @('DEBUG_DETECTED', 'TRACKING', 'ELIGIBLE')) { continue }

        if ($UnavailableHostnames -contains $rec.Hostname) {
            continue
        }

        if ($ScannedHostnames -contains $rec.Hostname) {
            $rec.CurrentStatus = 'INACTIVE'
            $rec.RemediationStatus = 'FILE_OR_LOGGER_MISSING'
            $Store.Records[$key] = $rec
        }
    }

    $eligible = @($Store.Records.Values | Where-Object { $_.CurrentStatus -eq 'ELIGIBLE' })
    return $eligible
}
