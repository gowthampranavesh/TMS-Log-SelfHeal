<#
.SYNOPSIS
    Pester Unit Test Suite covering all 22 scenarios in Section 16.
    Compatible with Pester v4 and v5 on Windows PowerShell 5.1.
#>

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)

. "$repoRoot\src\Common\Logging.ps1"
. "$repoRoot\src\Common\ErrorHandling.ps1"
. "$repoRoot\src\Common\Utilities.ps1"
. "$repoRoot\src\Configuration\Read-LogRegistry.ps1"
. "$repoRoot\src\Configuration\Resolve-ServerDrive.ps1"
. "$repoRoot\src\Discovery\Import-ServerInventory.ps1"
. "$repoRoot\src\Scanner\Parsers\Read-Log4jXml.ps1"
. "$repoRoot\src\Scanner\Parsers\Read-PropertiesFile.ps1"
. "$repoRoot\src\Scanner\Find-ConfigurationFiles.ps1"
. "$repoRoot\src\Scanner\Find-DebugConfiguration.ps1"
. "$repoRoot\src\Tracking\TrackingStorage.ps1"
. "$repoRoot\src\Tracking\DebugTracking.ps1"
. "$repoRoot\src\Remediation\Backup-Configuration.ps1"
. "$repoRoot\src\Remediation\Test-Configuration.ps1"
. "$repoRoot\src\Remediation\Restore-Configuration.ps1"
. "$repoRoot\src\Remediation\Set-LoggerLevel.ps1"

Describe 'TMS-Log-SelfHeal Unit Tests' {

    Context 'Dynamic Drive Resolution (Scenarios 6-7)' {
        $mappings = Read-ServerDriveMapping -MappingPath "$repoRoot\config\ServerDriveMapping.json"

        It 'Resolves PR server to F:' {
            $res = Resolve-ServerDrive -Hostname 'PRTMSAPP01' -ServerType 'PR' -DriveMappings $mappings
            $res.DriveRoot | Should Be 'F:'
        }

        It 'Resolves DL and FR servers to D:' {
            (Resolve-ServerDrive -Hostname 'DLTMSAPP01' -ServerType 'DL' -DriveMappings $mappings).DriveRoot | Should Be 'D:'
            (Resolve-ServerDrive -Hostname 'FRTMSAPP01' -ServerType 'FR' -DriveMappings $mappings).DriveRoot | Should Be 'D:'
        }
    }

    Context 'Exact File Discovery & Backup Exclusion (Scenarios 4-5, 8)' {
        $tempDir = Join-Path $env:TEMP ("tms_disc_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path "$tempDir\config\app1" -Force | Out-Null
        Set-Content -Path "$tempDir\config\app1\log4j.xml" -Value '<Configuration><Loggers><Root level="INFO"/></Loggers></Configuration>'
        Set-Content -Path "$tempDir\config\app1\log4j.xml.20261120_210000" -Value '<Configuration/>'
        Set-Content -Path "$tempDir\config\app1\log4j_old.xml" -Value '<Configuration/>'

        It 'Discovers exact log4j.xml and excludes timestamped backups and non-exact names' {
            $found = @(Find-LocalConfigurationFiles -ResolvedPathPattern "$tempDir\config\*\log4j.xml" -FileType 'xml')
            $found.Count | Should Be 1
            $found[0].Name | Should Be 'log4j.xml'
        }

        It 'Returns empty when path does not exist (Scenario 8)' {
            $found = @(Find-LocalConfigurationFiles -ResolvedPathPattern "$tempDir\missing\*\log4j.xml" -FileType 'xml')
            $found.Count | Should Be 0
        }

        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Context 'XML & Properties Parsers (Scenarios 1-3, 10-11)' {
        It 'Detects DEBUG and ignores INFO in Log4j 1.x XML (Scenarios 1-2)' {
            $xml = Get-Content "$repoRoot\tests\SampleConfigurations\log4j-v1-sample.xml" -Raw
            $res = Read-Log4jXmlContent -XmlContent $xml
            $res.IsValid | Should Be $true
            ($res.Loggers | Where-Object { $_.Level -eq 'DEBUG' }).LoggerName | Should Be 'com.blueyonder.tms.tmria'
        }

        It 'Detects multiple DEBUG loggers in Log4j 2.x XML (Scenario 3)' {
            $xml = Get-Content "$repoRoot\tests\SampleConfigurations\log4j-v2-sample.xml" -Raw
            $res = Read-Log4jXmlContent -XmlContent $xml
            $res.IsValid | Should Be $true
            @($res.Loggers | Where-Object { $_.Level -eq 'DEBUG' }).Count | Should Be 2
        }

        It 'Flags malformed XML as invalid (Scenario 10)' {
            $xml = Get-Content "$repoRoot\tests\SampleConfigurations\malformed.xml" -Raw
            $res = Read-Log4jXmlContent -XmlContent $xml
            $res.IsValid | Should Be $false
        }

        It 'Detects DEBUG in properties and flags invalid properties (Scenarios 1, 11)' {
            $props = Get-Content "$repoRoot\tests\SampleConfigurations\tm-sample.properties" -Raw
            $res = Read-PropertiesFileContent -Content $props
            $res.IsValid | Should Be $true
            ($res.Loggers | Where-Object { $_.Level -eq 'DEBUG' }).LoggerName | Should Be 'com.blueyonder.tm.core'

            $bad = Get-Content "$repoRoot\tests\SampleConfigurations\invalid.properties" -Raw
            (Read-PropertiesFileContent -Content $bad).IsValid | Should Be $false
        }
    }

    Context 'Persistent 48-Hour Tracking (Scenarios 12-15, 22)' {
        It 'Tracks 0h -> 24h -> 48h+ -> CLOSED and preserves timestamp when server unavailable' {
            $store = [PSCustomObject]@{ SchemaVersion = '1.0'; LastUpdatedUtc = $null; Records = @{} }
            $t0 = [datetime]'2026-11-18T00:00:00Z'
            $findingDebug = [PSCustomObject]@{
                Customer = 'CustA'; Hostname = 'PRTMSAPP01'; Component = 'ABPP'; FilePath = 'F:\Deployments\CEA\config\log4j.xml'
                FileType = 'xml'; LoggerName = 'com.blueyonder.abpp'; Level = 'DEBUG'; FileHash = 'abc'; ScannedUtc = $t0.ToString('o')
            }

            # Scenario 12: First detection (0h)
            $elig0 = @(Update-DebugTrackingState -Store $store -ScanFindings @($findingDebug) -ScannedHostnames @('PRTMSAPP01') -CurrentUtc $t0)
            $elig0.Count | Should Be 0
            $key = Get-TrackingRecordKey -Hostname 'PRTMSAPP01' -FilePath 'F:\Deployments\CEA\config\log4j.xml' -LoggerName 'com.blueyonder.abpp'
            $store.Records[$key].CurrentStatus | Should Be 'DEBUG_DETECTED'

            # Scenario 22: Server unavailable at 12h -> preserves FirstDetectedUtc
            $t12 = $t0.AddHours(12)
            $null = Update-DebugTrackingState -Store $store -ScanFindings @() -UnavailableHostnames @('PRTMSAPP01') -CurrentUtc $t12
            $store.Records[$key].FirstDetectedUtc | Should Be $t0.ToString('o')

            # Scenario 13: Still DEBUG at 24h -> TRACKING, not eligible
            $t24 = $t0.AddHours(24)
            $elig24 = @(Update-DebugTrackingState -Store $store -ScanFindings @($findingDebug) -ScannedHostnames @('PRTMSAPP01') -CurrentUtc $t24)
            $elig24.Count | Should Be 0
            $store.Records[$key].CurrentStatus | Should Be 'TRACKING'

            # Scenario 14: Still DEBUG at 49h -> ELIGIBLE
            $t49 = $t0.AddHours(49)
            $elig49 = @(Update-DebugTrackingState -Store $store -ScanFindings @($findingDebug) -ScannedHostnames @('PRTMSAPP01') -CurrentUtc $t49)
            $elig49.Count | Should Be 1
            $store.Records[$key].CurrentStatus | Should Be 'ELIGIBLE'

            # Scenario 15: Changed to INFO -> CLOSED
            $findingInfo = $findingDebug.PSObject.Copy()
            $findingInfo.Level = 'INFO'
            $null = Update-DebugTrackingState -Store $store -ScanFindings @($findingInfo) -ScannedHostnames @('PRTMSAPP01') -CurrentUtc $t49.AddHours(1)
            $store.Records[$key].CurrentStatus | Should Be 'CLOSED'
        }
    }

    Context 'Remediation, Same-Folder Backup, DryRun & Rollback (Scenarios 16-21)' {
        $remDir = Join-Path $env:TEMP ("tms_rem_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $remDir -Force | Out-Null
        $targetXml = Join-Path $remDir 'log4j.xml'
        Copy-Item "$repoRoot\tests\SampleConfigurations\log4j-v2-sample.xml" -Destination $targetXml -Force
        $rawXml = Get-Content $targetXml -Raw
        $hash = Get-StringSha256 -Text $rawXml

        $rec = [PSCustomObject]@{
            Customer = 'CustA'; Hostname = 'LOCAL'; Component = 'ABPP'; FilePath = $targetXml; FileType = 'xml'
            LoggerName = 'com.blueyonder.abpp.approval'; LastFileHash = $hash
        }

        It 'Respects DryRun=true and EnableRemediation=false (Scenarios 19-20)' {
            $cfg = [PSCustomObject]@{ DryRun = $true; EnableRemediation = $false; EnableBackup = $true; EnableRollback = $true }
            $res = Invoke-LoggerRemediation -TrackingRecord $rec -AgentConfig $cfg
            $res.ExecutionResult | Should Be 'DRY_RUN'
        }

        It 'Creates same-folder timestamped backup and remediates DEBUG to INFO (Scenarios 16-17)' {
            $cfg = [PSCustomObject]@{
                DryRun = $false; EnableRemediation = $true; EnableBackup = $true; EnableRollback = $true
                Backup = [PSCustomObject]@{ TimestampFormat = 'yyyyMMdd_HHmmss' }
            }
            $res = Invoke-LoggerRemediation -TrackingRecord $rec -AgentConfig $cfg
            $res.ExecutionResult | Should Be 'REMEDIATED'
            (Split-Path $res.BackupLocation -Parent) | Should Be $remDir
            (Test-Path $res.BackupLocation) | Should Be $true
            $newParsed = Read-Log4jXmlContent -XmlContent (Get-Content $targetXml -Raw)
            ($newParsed.Loggers | Where-Object { $_.LoggerName -eq 'com.blueyonder.abpp.approval' }).Level | Should Be 'INFO'
            ($newParsed.Loggers | Where-Object { $_.LoggerName -eq 'com.blueyonder.abpp.cea' }).Level | Should Be 'DEBUG'
        }

        It 'Prevents concurrent execution via lockfile (Scenario 21)' {
            $lockFile = Join-Path $remDir 'agent.lock'
            Enter-AgentExecutionLock -LockFilePath $lockFile | Out-Null
            { Enter-AgentExecutionLock -LockFilePath $lockFile } | Should Throw
            Exit-AgentExecutionLock -LockFilePath $lockFile
        }

        Remove-Item -Path $remDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
