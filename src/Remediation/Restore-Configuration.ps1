<#
.SYNOPSIS
    Restores original configuration file from timestamped backup when validation fails.
#>

function Restore-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    if ($null -ne $Session) {
        $ok = Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
            param($SrcBak, $DstOrig)
            if (-not (Test-Path -LiteralPath $SrcBak)) {
                throw "Backup file missing for rollback: $SrcBak"
            }
            Copy-Item -LiteralPath $SrcBak -Destination $DstOrig -Force -ErrorAction Stop
            return $true
        } -ArgumentList @($BackupPath, $FilePath)
        return $ok
    }
    else {
        if (-not (Test-Path -LiteralPath $BackupPath)) {
            throw "Backup file missing for rollback: $BackupPath"
        }
        Copy-Item -LiteralPath $BackupPath -Destination $FilePath -Force -ErrorAction Stop
        return $true
    }
}
