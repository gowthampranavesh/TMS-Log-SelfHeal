<#
.SYNOPSIS
    Manages WinRM PSSession connections (supporting gMSA Kerberos authentication) and remote execution.
#>

function Connect-TmsServerSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [object]$WinRmConfig
    )

    $sessionOpt = New-PSSessionOption -OperationTimeout ($WinRmConfig.OperationTimeoutSec * 1000) -OpenTimeout 15000

    $params = @{
        ComputerName  = $Hostname
        SessionOption = $sessionOpt
        ErrorAction   = 'Stop'
    }

    if ($WinRmConfig.UseSSL -eq $true) {
        $params['UseSSL'] = $true
    }
    if ($WinRmConfig.Port) {
        $params['Port'] = [int]$WinRmConfig.Port
    }
    if ($WinRmConfig.Authentication -and $WinRmConfig.Authentication -ne 'Default') {
        $params['Authentication'] = [string]$WinRmConfig.Authentication
    }

    return New-PSSession @params
}

function Disconnect-TmsServerSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session
    )

    if ($null -ne $Session) {
        Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
    }
}

function Invoke-TmsRemoteScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]$Session,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [Parameter(Mandatory = $false)]
        [object[]]$ArgumentList = @()
    )

    return Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}
