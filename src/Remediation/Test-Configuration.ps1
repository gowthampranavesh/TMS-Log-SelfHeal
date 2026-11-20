<#
.SYNOPSIS
    Validates modified configuration files (XML / Properties) and confirms target logger level.
#>

function Test-Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('xml', 'properties')]
        [string]$FileType,

        [Parameter(Mandatory = $true)]
        [string]$TargetLoggerName,

        [Parameter(Mandatory = $false)]
        [string]$ExpectedLevel = 'INFO',

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    $content = $null
    if ($null -ne $Session) {
        $content = Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
            param($Path)
            if (-not (Test-Path -LiteralPath $Path)) { return $null }
            return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        } -ArgumentList @($FilePath)
    }
    else {
        if (Test-Path -LiteralPath $FilePath) {
            $content = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
        }
    }

    if ($null -eq $content) {
        return [PSCustomObject]@{ IsValid = $false; Reason = "File missing during validation: $FilePath" }
    }

    $parsed = switch ($FileType) {
        'xml'        { Read-Log4jXmlContent -XmlContent $content }
        'properties' { Read-PropertiesFileContent -Content $content }
    }

    if (-not $parsed.IsValid) {
        return [PSCustomObject]@{ IsValid = $false; Reason = $parsed.Error }
    }

    $match = $parsed.Loggers | Where-Object { $_.LoggerName -eq $TargetLoggerName } | Select-Object -First 1
    if ($null -eq $match) {
        return [PSCustomObject]@{ IsValid = $false; Reason = "Target logger '$TargetLoggerName' missing after update." }
    }

    if ($match.Level -ne $ExpectedLevel.ToUpperInvariant()) {
        return [PSCustomObject]@{ IsValid = $false; Reason = "Expected '$ExpectedLevel' but found '$($match.Level)'." }
    }

    return [PSCustomObject]@{ IsValid = $true; Reason = 'Validated' }
}
