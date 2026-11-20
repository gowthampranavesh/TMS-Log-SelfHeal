<#
.SYNOPSIS
    Scans discovered configuration files, parses logger entries, and identifies DEBUG configurations.
#>

function Test-LoggerMatchesPatterns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LoggerName,

        [Parameter(Mandatory = $true)]
        [string[]]$Patterns
    )

    foreach ($p in $Patterns) {
        if ($LoggerName -like $p) {
            return $true
        }
    }
    return $false
}

function Get-StringSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Find-DebugConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$DiscoveredFiles,

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.Runspaces.PSSession]$Session = $null
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $scanUtc = (Get-Date).ToUniversalTime().ToString('o')

    foreach ($file in $DiscoveredFiles) {
        $content = $null
        $readError = $null

        try {
            if ($null -ne $Session) {
                $content = Invoke-TmsRemoteScript -Session $Session -ScriptBlock {
                    param($Path)
                    if (-not (Test-Path -LiteralPath $Path)) { return $null }
                    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
                } -ArgumentList @($file.FilePath)
            }
            else {
                if (Test-Path -LiteralPath $file.FilePath) {
                    $content = Get-Content -LiteralPath $file.FilePath -Raw -Encoding UTF8
                }
            }
        }
        catch {
            $readError = $_.Exception.Message
        }

        if ($null -eq $content) {
            $findings.Add([PSCustomObject]@{
                Customer       = $file.Customer
                Hostname       = $file.Hostname
                Component      = $file.Component
                FilePath       = $file.FilePath
                FileType       = $file.FileType
                LoggerName     = ''
                Level          = ''
                FileHash       = ''
                ScannedUtc     = $scanUtc
                Status         = if ($readError) { 'MANUAL_REVIEW_REQUIRED' } else { 'FILE_NOT_FOUND' }
                Detail         = if ($readError) { $readError } else { 'File disappeared before read.' }
            })
            continue
        }

        $fileHash = Get-StringSha256 -Text $content
        $parsed = switch ($file.FileType) {
            'xml'        { Read-Log4jXmlContent -XmlContent $content }
            'properties' { Read-PropertiesFileContent -Content $content }
            default      { [PSCustomObject]@{ IsValid = $false; Error = "Unsupported FileType '$($file.FileType)'"; Loggers = @() } }
        }

        if (-not $parsed.IsValid) {
            $findings.Add([PSCustomObject]@{
                Customer   = $file.Customer
                Hostname   = $file.Hostname
                Component  = $file.Component
                FilePath   = $file.FilePath
                FileType   = $file.FileType
                LoggerName = ''
                Level      = ''
                FileHash   = $fileHash
                ScannedUtc = $scanUtc
                Status     = 'MANUAL_REVIEW_REQUIRED'
                Detail     = $parsed.Error
            })
            continue
        }

        foreach ($logger in $parsed.Loggers) {
            if (-not (Test-LoggerMatchesPatterns -LoggerName $logger.LoggerName -Patterns $file.LoggerPatterns)) {
                continue
            }

            $status = if ($logger.Level -eq 'DEBUG') { 'DEBUG_DETECTED' } else { 'INFO_OR_OTHER' }
            $findings.Add([PSCustomObject]@{
                Customer   = $file.Customer
                Hostname   = $file.Hostname
                Component  = $file.Component
                FilePath   = $file.FilePath
                FileType   = $file.FileType
                LoggerName = $logger.LoggerName
                Level      = $logger.Level
                FileHash   = $fileHash
                ScannedUtc = $scanUtc
                Status     = $status
                Detail     = $null
            })
        }
    }

    return $findings.ToArray()
}
