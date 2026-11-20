<#
.SYNOPSIS
    Discovers configuration files from resolved registry paths while strictly excluding backup files.
#>

function Test-IsExactConfigFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedPattern,

        [Parameter(Mandatory = $true)]
        [string]$FileType
    )

    # Explicitly reject backup files created in the same folder (e.g. log4j.xml.20261120_212335, *.bak, *_backup*)
    if ($FileName -match '\.(bak|backup|old|orig|tmp)$' -or
        $FileName -match '\.\d{8}(_\d{6})?$' -or
        $FileName -match '\.\d{8}(_\d{6})?\.bak$') {
        return $false
    }

    $ext = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    if ($FileType -eq 'xml' -and $ext -ne '.xml') { return $false }
    if ($FileType -eq 'properties' -and $ext -ne '.properties') { return $false }

    # Enforce exact filename match against the leaf of ExpectedPattern (e.g. 'log4j.xml' or '*.properties')
    $leafPattern = Split-Path -Path $ExpectedPattern -Leaf
    if ($leafPattern -notmatch '[\*\?]') {
        return ($FileName -ieq $leafPattern)
    }

    return ($FileName -like $leafPattern)
}

function Find-LocalConfigurationFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResolvedPathPattern,

        [Parameter(Mandatory = $true)]
        [string]$FileType
    )

    $results = New-Object System.Collections.Generic.List[object]

    # PowerShell Resolve-Path / Get-ChildItem expands wildcards in parent folders as well as leaf
    $candidates = Get-ChildItem -Path $ResolvedPathPattern -File -ErrorAction SilentlyContinue
    foreach ($item in $candidates) {
        if (Test-IsExactConfigFile -FileName $item.Name -ExpectedPattern $ResolvedPathPattern -FileType $FileType) {
            $results.Add([PSCustomObject]@{
                FullName      = $item.FullName
                Name          = $item.Name
                LastWriteTime = $item.LastWriteTimeUtc.ToString('o')
                Length        = $item.Length
            })
        }
    }

    return $results.ToArray()
}

function Find-ConfigurationFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Server,

        [Parameter(Mandatory = $true)]
        [object[]]$RegistryEntries,

        [Parameter(Mandatory = $true)]
        [object[]]$DriveMappings,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    $driveInfo = Resolve-ServerDrive -Hostname $Server.Hostname -ServerType $Server.ServerType -DriveMappings $DriveMappings
    $discovered = New-Object System.Collections.Generic.List[object]

    foreach ($entry in $RegistryEntries) {
        if ($entry.ServerPattern -and ($Server.Hostname -notmatch $entry.ServerPattern)) {
            continue
        }

        $resolvedPath = Expand-RegistryPathForServer -RegistryFilePath $entry.FilePath -DriveLetter $driveInfo.DriveLetter

        $matchedFiles = @()
        if ($null -ne $Session) {
            $remoteScript = {
                param($PathPattern, $FType)
                $leafPattern = Split-Path -Path $PathPattern -Leaf
                $items = Get-ChildItem -Path $PathPattern -File -ErrorAction SilentlyContinue
                $out = @()
                foreach ($item in $items) {
                    $fn = $item.Name
                    if ($fn -match '\.(bak|backup|old|orig|tmp)$' -or
                        $fn -match '\.\d{8}(_\d{6})?$' -or
                        $fn -match '\.\d{8}(_\d{6})?\.bak$') {
                        continue
                    }
                    $ext = [System.IO.Path]::GetExtension($fn).ToLowerInvariant()
                    if ($FType -eq 'xml' -and $ext -ne '.xml') { continue }
                    if ($FType -eq 'properties' -and $ext -ne '.properties') { continue }
                    if ($leafPattern -notmatch '[\*\?]' -and ($fn -ine $leafPattern)) { continue }
                    if ($leafPattern -match '[\*\?]' -and ($fn -notlike $leafPattern)) { continue }

                    $out += [PSCustomObject]@{
                        FullName      = $item.FullName
                        Name          = $item.Name
                        LastWriteTime = $item.LastWriteTimeUtc.ToString('o')
                        Length        = $item.Length
                    }
                }
                return $out
            }
            $matchedFiles = @(Invoke-TmsRemoteScript -Session $Session -ScriptBlock $remoteScript -ArgumentList @($resolvedPath, $entry.FileType))
        }
        else {
            $matchedFiles = @(Find-LocalConfigurationFiles -ResolvedPathPattern $resolvedPath -FileType $entry.FileType)
        }

        foreach ($mf in $matchedFiles) {
            if ($null -eq $mf -or [string]::IsNullOrWhiteSpace($mf.FullName)) { continue }
            $discovered.Add([PSCustomObject]@{
                Customer       = $Server.Customer
                Hostname       = $Server.Hostname
                ServerType     = $Server.ServerType
                DriveRoot      = $driveInfo.DriveRoot
                Component      = $entry.Component
                FileType       = $entry.FileType
                FilePath       = $mf.FullName
                LoggerPatterns = $entry.LoggerPatterns
            })
        }
    }

    return $discovered.ToArray()
}
