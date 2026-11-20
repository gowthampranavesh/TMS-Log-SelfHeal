<#
.SYNOPSIS
    Standardized error handling and safe execution wrappers.
#>

function Format-ExceptionDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $ex = $ErrorRecord.Exception
    $msg = if ($ex) { $ex.Message } else { $ErrorRecord.ToString() }
    $pos = if ($ErrorRecord.InvocationInfo) {
        "at $($ErrorRecord.InvocationInfo.ScriptName):$($ErrorRecord.InvocationInfo.ScriptLineNumber)"
    } else {
        ''
    }

    return ("{0} {1}" -f $msg, $pos).Trim()
}

function Invoke-SafeStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $false)]
        [string]$Component = 'Agent',

        [Parameter(Mandatory = $false)]
        [switch]$ThrowOnError
    )

    try {
        $result = & $Action
        return [PSCustomObject]@{
            Success = $true
            Result  = $result
            Error   = $null
        }
    }
    catch {
        $detail = Format-ExceptionDetail -ErrorRecord $_
        if (Get-Command -Name 'Write-AgentLog' -ErrorAction SilentlyContinue) {
            Write-AgentLog -Level 'ERROR' -Component $Component -Message "Step '$StepName' failed: $detail"
        }
        if ($ThrowOnError) {
            throw
        }
        return [PSCustomObject]@{
            Success = $false
            Result  = $null
            Error   = $detail
        }
    }
}
