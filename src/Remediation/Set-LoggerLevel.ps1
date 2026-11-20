<#
.SYNOPSIS
    Executes safe, pre-flight-checked DEBUG-to-INFO remediation with backup, validation, and rollback.
#>

function Invoke-LoggerRemediation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$TrackingRecord,

        [Parameter(Mandatory = $true)]
        [object]$AgentConfig,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    $nowIso = (Get-Date).ToUniversalTime().ToString('o')
    $result = [PSCustomObject]@{
        Customer         = $TrackingRecord.Customer
        Hostname         = $TrackingRecord.Hostname
        Component        = $TrackingRecord.Component
        FilePath         = $TrackingRecord.FilePath
        Logger           = $TrackingRecord.LoggerName
        OriginalLevel    = 'DEBUG'
        NewLevel         = 'INFO'
        BackupLocation   = ''
        RemediationUtc   = $nowIso
        ValidationStatus = 'SKIPPED'
        RollbackStatus   = 'NOT_NEEDED'
        ExecutionResult  = 'DRY_RUN'
    }

    if ($AgentConfig.DryRun -eq $true -or $AgentConfig.EnableRemediation -ne $true) {
        $result.ExecutionResult = 'DRY_RUN'
        return $result
    }

    # Pre-flight 1: Re-read current file content and verify hash + DEBUG state
    $currentContent = $null
    if ($null -ne $Session) {
        $currentContent = Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
            param($Path)
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } -ArgumentList @($TrackingRecord.FilePath)
    }
    elseif (Test-Path -LiteralPath $TrackingRecord.FilePath) {
        $currentContent = Get-Content -LiteralPath $TrackingRecord.FilePath -Raw -Encoding UTF8
    }

    if ($null -eq $currentContent) {
        $result.ExecutionResult = 'FILE_NOT_FOUND'
        return $result
    }

    $currentHash = Get-StringSha256 -Text $currentContent
    if ($TrackingRecord.LastFileHash -and ($currentHash -ne $TrackingRecord.LastFileHash)) {
        $result.ExecutionResult = 'MANUAL_REVIEW_REQUIRED'
        $result.ValidationStatus = 'ABORTED_FILE_CHANGED_BETWEEN_SCAN_AND_REMEDIATION'
        return $result
    }

    $parsed = switch ($TrackingRecord.FileType) {
        'xml'        { Read-Log4jXmlContent -XmlContent $currentContent }
        'properties' { Read-PropertiesFileContent -Content $currentContent }
    }

    if (-not $parsed.IsValid) {
        $result.ExecutionResult = 'MANUAL_REVIEW_REQUIRED'
        return $result
    }

    $targetLogger = $parsed.Loggers | Where-Object { $_.LoggerName -eq $TrackingRecord.LoggerName } | Select-Object -First 1
    if ($null -eq $targetLogger -or $targetLogger.Level -ne 'DEBUG') {
        $result.ExecutionResult = 'SKIPPED_NOT_DEBUG'
        return $result
    }

    # Step 1: Backup in same folder with date & time as extension
    if ($AgentConfig.EnableBackup -eq $true) {
        $tsFormat = if ($AgentConfig.Backup -and $AgentConfig.Backup.TimestampFormat) { $AgentConfig.Backup.TimestampFormat } else { 'yyyyMMdd_HHmmss' }
        $result.BackupLocation = Backup-Configuration -FilePath $TrackingRecord.FilePath -TimestampFormat $tsFormat -Session $Session
    }

    # Step 2: Modify only targeted logger
    $updatedContent = switch ($TrackingRecord.FileType) {
        'xml'        { Set-Log4jXmlLoggerLevel -XmlContent $currentContent -TargetLoggerName $TrackingRecord.LoggerName -NewLevel 'INFO' }
        'properties' { Set-PropertiesFileLoggerLevel -Content $currentContent -TargetLoggerName $TrackingRecord.LoggerName -NewLevel 'INFO' }
    }

    if ($null -ne $Session) {
        Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
            param($Path, $Text)
            Set-Content -LiteralPath $Path -Value $Text -Encoding UTF8 -NoNewline
        } -ArgumentList @($TrackingRecord.FilePath, $updatedContent) | Out-Null
    }
    else {
        Set-Content -LiteralPath $TrackingRecord.FilePath -Value $updatedContent -Encoding UTF8 -NoNewline
    }

    # Step 3: Validate
    $val = Test-Configuration -FilePath $TrackingRecord.FilePath -FileType $TrackingRecord.FileType -TargetLoggerName $TrackingRecord.LoggerName -ExpectedLevel 'INFO' -Session $Session
    if ($val.IsValid) {
        $result.ValidationStatus = 'PASSED'
        $result.ExecutionResult = 'REMEDIATED'
        return $result
    }

    # Step 4: Rollback on validation failure
    $result.ValidationStatus = "VALIDATION_FAILED: $($val.Reason)"
    if ($AgentConfig.EnableRollback -eq $true -and -not [string]::IsNullOrWhiteSpace($result.BackupLocation)) {
        $null = Restore-Configuration -FilePath $TrackingRecord.FilePath -BackupPath $result.BackupLocation -Session $Session
        $result.RollbackStatus = 'ROLLBACK_COMPLETED'
        $result.ExecutionResult = 'ROLLBACK_COMPLETED'
    }
    else {
        $result.ExecutionResult = 'VALIDATION_FAILED'
    }

    return $result
}
