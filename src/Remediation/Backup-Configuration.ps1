<#
.SYNOPSIS
    Creates a timestamped backup in the same folder with date and time as the extension.
    Example: log4j.xml -> log4j.xml.20261120_212335
#>

function Backup-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string]$TimestampFormat = 'yyyyMMdd_HHmmss',

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    $stamp = (Get-Date).ToString($TimestampFormat)
    $backupPath = "{0}.{1}" -f $FilePath, $stamp

    if ($null -ne $Session) {
        $result = Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
            param($Src, $Dst)
            if (-not (Test-Path -LiteralPath $Src)) {
                throw "Source file not found for backup: $Src"
            }
            Copy-Item -LiteralPath $Src -Destination $Dst -Force -ErrorAction Stop
            return (Test-Path -LiteralPath $Dst)
        } -ArgumentList @($FilePath, $backupPath)

        if (-not $result) {
            throw "Remote backup verification failed for: $backupPath"
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $FilePath)) {
            throw "Source file not found for backup: $FilePath"
        }
        Copy-Item -LiteralPath $FilePath -Destination $backupPath -Force -ErrorAction Stop
    }

    return $backupPath
}
