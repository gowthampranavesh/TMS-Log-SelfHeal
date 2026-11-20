<#
.SYNOPSIS
    Reads and validates the centralized LogFileRegistry.xml configuration.
#>

function Read-LogRegistry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryPath,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDisabled
    )

    if (-not (Test-Path -LiteralPath $RegistryPath)) {
        throw "LogFileRegistry.xml not found at: $RegistryPath"
    }

    [xml]$xmlDoc = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8

    if (-not $xmlDoc.LogConfigurations -or -not $xmlDoc.LogConfigurations.Component) {
        throw "Invalid LogFileRegistry.xml schema: missing <LogConfigurations>/<Component> nodes."
    }

    $entries = New-Object System.Collections.Generic.List[object]

    foreach ($comp in $xmlDoc.LogConfigurations.Component) {
        $compName = [string]$comp.name
        if ([string]::IsNullOrWhiteSpace($compName)) {
            throw "Registry component entry is missing required 'name' attribute."
        }

        $isEnabled = $true
        if ($comp.HasAttribute('enabled')) {
            $isEnabled = ($comp.enabled -eq 'true' -or $comp.enabled -eq '1')
        }

        if (-not $IncludeDisabled -and -not $isEnabled) {
            continue
        }

        $fileType = ([string]$comp.FileType).Trim().ToLowerInvariant()
        if ($fileType -notin @('xml', 'properties')) {
            throw "Unsupported FileType '$fileType' for component '$compName'. Supported: xml, properties."
        }

        # Support single <FilePath> or multiple <FilePaths><FilePath>
        $filePaths = New-Object System.Collections.Generic.List[string]
        if ($comp.FilePath) {
            foreach ($fp in @($comp.FilePath)) {
                $trimmed = ([string]$fp).Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $filePaths.Add($trimmed)
                }
            }
        }
        if ($comp.FilePaths -and $comp.FilePaths.FilePath) {
            foreach ($fp in @($comp.FilePaths.FilePath)) {
                $trimmed = ([string]$fp).Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $filePaths.Add($trimmed)
                }
            }
        }

        if ($filePaths.Count -eq 0) {
            throw "Component '$compName' has no <FilePath> configured."
        }

        # Support <LoggerPatterns><Pattern> or direct <Pattern>
        $patterns = New-Object System.Collections.Generic.List[string]
        if ($comp.LoggerPatterns -and $comp.LoggerPatterns.Pattern) {
            foreach ($p in @($comp.LoggerPatterns.Pattern)) {
                $pt = ([string]$p).Trim()
                if (-not [string]::IsNullOrWhiteSpace($pt)) { $patterns.Add($pt) }
            }
        }
        elseif ($comp.Pattern) {
            foreach ($p in @($comp.Pattern)) {
                $pt = ([string]$p).Trim()
                if (-not [string]::IsNullOrWhiteSpace($pt)) { $patterns.Add($pt) }
            }
        }

        if ($patterns.Count -eq 0) {
            $patterns.Add('*')
        }

        # Optional server filter
        $serverPattern = if ($comp.ServerPattern) { ([string]$comp.ServerPattern).Trim() } else { '.*' }

        foreach ($fp in $filePaths) {
            $entries.Add([PSCustomObject]@{
                Component      = $compName
                Enabled        = $isEnabled
                FilePath       = $fp
                FileType       = $fileType
                LoggerPatterns = $patterns.ToArray()
                ServerPattern  = $serverPattern
            })
        }
    }

    return $entries.ToArray()
}
