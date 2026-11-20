<#
.SYNOPSIS
    Resolves drive letters per server from ServerDriveMapping.json and expands {DRIVE} placeholders.
#>

function Read-ServerDriveMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MappingPath
    )

    if (-not (Test-Path -LiteralPath $MappingPath)) {
        throw "ServerDriveMapping.json not found at: $MappingPath"
    }

    $parsed = Get-Content -LiteralPath $MappingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $parsed -or -not $parsed.DriveMappings) {
        throw "Invalid ServerDriveMapping.json: missing 'DriveMappings' array."
    }

    return @($parsed.DriveMappings)
}

function Resolve-ServerDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hostname,

        [Parameter(Mandatory = $false)]
        [string]$ServerType = '',

        [Parameter(Mandatory = $true)]
        [object[]]$DriveMappings
    )

    $candidate = if (-not [string]::IsNullOrWhiteSpace($ServerType)) { $ServerType } else { $Hostname }

    foreach ($rule in $DriveMappings) {
        $pattern = [string]$rule.ServerPattern
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }

        # Match against Hostname first, then ServerType
        if ($Hostname -match $pattern -or ($ServerType -and $ServerType -match $pattern)) {
            $drive = ([string]$rule.Drive).Trim()
            # Normalize to single letter without colon for {DRIVE}:\... replacement, and with colon
            $letter = $drive.TrimEnd(':')
            return [PSCustomObject]@{
                DriveLetter = $letter
                DriveRoot   = "${letter}:"
                MatchedRule = $pattern
            }
        }
    }

    return [PSCustomObject]@{
        DriveLetter = 'D'
        DriveRoot   = 'D:'
        MatchedRule = 'FALLBACK_DEFAULT'
    }
}

function Expand-RegistryPathForServer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RegistryFilePath,

        [Parameter(Mandatory = $true)]
        [string]$DriveLetter
    )

    $cleanLetter = $DriveLetter.Trim().TrimEnd(':')
    return ($RegistryFilePath -replace '\{DRIVE\}', $cleanLetter)
}
