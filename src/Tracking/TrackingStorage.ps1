<#
.SYNOPSIS
    Atomic JSON persistent storage for DEBUG logger tracking records.
#>

function Get-TrackingRecordKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string]$LoggerName
    )

    return ("{0}|{1}|{2}" -f $Hostname.Trim().ToUpperInvariant(), $FilePath.Trim().ToLowerInvariant(), $LoggerName.Trim())
}

function Read-TrackingStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrackingFilePath
    )

    if (-not (Test-Path -LiteralPath $TrackingFilePath)) {
        return [PSCustomObject]@{
            SchemaVersion = '1.0'
            LastUpdatedUtc = $null
            Records        = @{}
        }
    }

    $raw = Get-Content -LiteralPath $TrackingFilePath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [PSCustomObject]@{
            SchemaVersion = '1.0'
            LastUpdatedUtc = $null
            Records        = @{}
        }
    }

    $parsed = $raw | ConvertFrom-Json
    $dict = @{}
    if ($parsed.Records) {
        foreach ($prop in $parsed.Records.PSObject.Properties) {
            $dict[$prop.Name] = $prop.Value
        }
    }

    return [PSCustomObject]@{
        SchemaVersion  = if ($parsed.SchemaVersion) { $parsed.SchemaVersion } else { '1.0' }
        LastUpdatedUtc = $parsed.LastUpdatedUtc
        Records        = $dict
    }
}

function Save-TrackingStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TrackingFilePath,

        [Parameter(Mandatory = $true)]
        [object]$Store
    )

    $parent = Split-Path -Path $TrackingFilePath -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $Store.LastUpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $json = $Store | ConvertTo-Json -Depth 10

    $tempPath = "$TrackingFilePath.tmp"
    $bakPath = "$TrackingFilePath.bak"

    Set-Content -LiteralPath $tempPath -Value $json -Encoding UTF8
    if (Test-Path -LiteralPath $TrackingFilePath) {
        Copy-Item -LiteralPath $TrackingFilePath -Destination $bakPath -Force
    }
    Move-Item -LiteralPath $tempPath -Destination $TrackingFilePath -Force
}
