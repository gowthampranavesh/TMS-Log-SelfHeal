<#
.SYNOPSIS
    Main orchestrator for Blue Yonder TMS Centralized DEBUG Log Detection & Self-Healing Agent.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'config\AgentConfig.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent

# Dot-source all modular components
$moduleScripts = @(
    'src\Common\Logging.ps1',
    'src\Common\ErrorHandling.ps1',
    'src\Common\Utilities.ps1',
    'src\Common\RemoteSession.ps1',
    'src\Configuration\Read-LogRegistry.ps1',
    'src\Configuration\Resolve-ServerDrive.ps1',
    'src\Discovery\Import-ServerInventory.ps1',
    'src\Discovery\Get-SplunkServers.ps1',
    'src\Scanner\Parsers\Read-Log4jXml.ps1',
    'src\Scanner\Parsers\Read-PropertiesFile.ps1',
    'src\Scanner\Find-ConfigurationFiles.ps1',
    'src\Scanner\Find-DebugConfiguration.ps1',
    'src\Tracking\TrackingStorage.ps1',
    'src\Tracking\DebugTracking.ps1',
    'src\Remediation\Backup-Configuration.ps1',
    'src\Remediation\Test-Configuration.ps1',
    'src\Remediation\Restore-Configuration.ps1',
    'src\Remediation\Set-LoggerLevel.ps1',
    'src\Reporting\Write-DetectionReport.ps1',
    'src\Reporting\Write-AuditLog.ps1'
)

foreach ($rel in $moduleScripts) {
    . (Join-Path -Path $repoRoot -ChildPath $rel)
}

$agentConfig = Import-AgentConfig -ConfigPath $ConfigPath
$logDir = Resolve-RepoPath -RepoRoot $repoRoot -PathValue $agentConfig.Paths.LogRoot
$null = Initialize-AgentLogger -LogDirectory $logDir

$lockPath = Join-Path -Path (Resolve-RepoPath -RepoRoot $repoRoot -PathValue 'data') -ChildPath 'agent.lock'
Enter-AgentExecutionLock -LockFilePath $lockPath | Out-Null

try {
    Write-AgentLog -Level 'INFO' -Component 'Main' -Message "Starting TMS-Log-SelfHeal run (DryRun=$($agentConfig.DryRun), EnableRemediation=$($agentConfig.EnableRemediation))."

    $registryPath = Resolve-RepoPath -RepoRoot $repoRoot -PathValue $agentConfig.Paths.RegistryFile
    $driveMapPath = Resolve-RepoPath -RepoRoot $repoRoot -PathValue $agentConfig.Paths.DriveMappingFile
    $trackingPath = Resolve-RepoPath -RepoRoot $repoRoot -PathValue $agentConfig.Paths.TrackingFile

    $registryEntries = Read-LogRegistry -RegistryPath $registryPath
    $driveMappings = Read-ServerDriveMapping -MappingPath $driveMapPath
    $servers = @(Get-SplunkServers -AgentConfig $agentConfig -RepoRoot $repoRoot)

    Write-AgentLog -Level 'INFO' -Component 'Main' -Message "Loaded $($servers.Count) servers and $($registryEntries.Count) enabled registry entries."

    $allFindings = New-Object System.Collections.Generic.List[object]
    $unavailableHosts = New-Object System.Collections.Generic.List[string]
    $scannedHosts = New-Object System.Collections.Generic.List[string]
    $activeSessions = @{}

    foreach ($srv in $servers) {
        $session = $null
        try {
            $session = Connect-TmsServerSession -Hostname $srv.Hostname -WinRmConfig $agentConfig.WinRM
            $activeSessions[$srv.Hostname] = $session
            $scannedHosts.Add($srv.Hostname)

            $files = @(Find-ConfigurationFiles -Server $srv -RegistryEntries $registryEntries -DriveMappings $driveMappings -Session $session)
            $findings = @(Find-DebugConfiguration -DiscoveredFiles $files -Session $session)
            foreach ($f in $findings) { $allFindings.Add($f) }
        }
        catch {
            $unavailableHosts.Add($srv.Hostname)
            Write-AgentLog -Level 'WARN' -Component 'Main' -Message "Server '$($srv.Hostname)' unavailable: $($_.Exception.Message)"
            $allFindings.Add([PSCustomObject]@{
                Customer   = $srv.Customer
                Hostname   = $srv.Hostname
                Component  = ''
                FilePath   = ''
                FileType   = ''
                LoggerName = ''
                Level      = ''
                FileHash   = ''
                ScannedUtc = (Get-Date).ToUniversalTime().ToString('o')
                Status     = 'SERVER_UNAVAILABLE'
                Detail     = $_.Exception.Message
            })
        }
    }

    $store = Read-TrackingStore -TrackingFilePath $trackingPath
    $eligible = @(Update-DebugTrackingState -Store $store `
        -ScanFindings $allFindings.ToArray() `
        -UnavailableHostnames $unavailableHosts.ToArray() `
        -ScannedHostnames $scannedHosts.ToArray() `
        -ThresholdHours ([double]$agentConfig.DebugThresholdHours))

    $remediationResults = New-Object System.Collections.Generic.List[object]
    foreach ($rec in $eligible) {
        $sess = if ($activeSessions.ContainsKey($rec.Hostname)) { $activeSessions[$rec.Hostname] } else { $null }
        if ($null -eq $sess) { continue }

        $remRes = Invoke-LoggerRemediation -TrackingRecord $rec -AgentConfig $agentConfig -Session $sess
        $remediationResults.Add($remRes)

        if ($remRes.ExecutionResult -eq 'REMEDIATED') {
            $key = Get-TrackingRecordKey -Hostname $rec.Hostname -FilePath $rec.FilePath -LoggerName $rec.LoggerName
            $store.Records[$key].CurrentStatus = 'REMEDIATED'
            $store.Records[$key].CurrentLevel = 'INFO'
            $store.Records[$key].RemediationStatus = 'REMEDIATED'
        }
        elseif ($remRes.ExecutionResult -in @('ROLLBACK_COMPLETED', 'VALIDATION_FAILED', 'MANUAL_REVIEW_REQUIRED')) {
            $key = Get-TrackingRecordKey -Hostname $rec.Hostname -FilePath $rec.FilePath -LoggerName $rec.LoggerName
            $store.Records[$key].RemediationStatus = $remRes.ExecutionResult
        }
    }

    Save-TrackingStore -TrackingFilePath $trackingPath -Store $store

    $detReport = Write-DetectionReport -OutputDirectory $logDir -TrackingRecords @($store.Records.Values) -AdditionalFindings $allFindings.ToArray()
    $audReport = Write-AuditLog -OutputDirectory $logDir -RemediationResults $remediationResults.ToArray()

    $cleaned = Invoke-FileRetentionCleanup -DirectoryPath $logDir -RetentionDays ([int]$agentConfig.RetentionDays.Logs)
    Write-AgentLog -Level 'INFO' -Component 'Main' -Message "Run complete. DetectionReport=$detReport, AuditReport=$audReport, RetainedCleaned=$cleaned"
}
finally {
    foreach ($s in $activeSessions.Values) {
        Disconnect-TmsServerSession -Session $s
    }
    Exit-AgentExecutionLock -LockFilePath $lockPath
}
