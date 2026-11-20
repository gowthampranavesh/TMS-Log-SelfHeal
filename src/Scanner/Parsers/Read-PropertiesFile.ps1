<#
.SYNOPSIS
    Safe parser and formatting-preserving updater for Java .properties logging configuration files.
#>

function Read-PropertiesFileContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    if ([string]::IsNullOrWhiteSpace($Content)) {
        return [PSCustomObject]@{
            IsValid       = $false
            StructureType = 'EMPTY_PROPERTIES'
            Error         = 'Properties file is empty.'
            Loggers       = @()
        }
    }

    $lines = $Content -split "`r?`n"
    $loggers = New-Object System.Collections.Generic.List[object]
    $hasKeyValues = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()

        # Skip blank lines and comments
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('!')) {
            continue
        }

        # Expect key=value or key:value
        if ($trimmed -notmatch '^([^=:]+?)\s*([=:])\s*(.*)$') {
            # Allow line continuations or report malformed if no valid keys exist
            continue
        }

        $hasKeyValues = $true
        $key = $matches[1].Trim()
        $val = $matches[3].Trim()

        # Pattern 1: Log4j 1.x -> log4j.rootLogger=DEBUG, appender1  OR log4j.logger.com.foo=DEBUG, appender1
        if ($key -match '^log4j\.(rootLogger|rootCategory|logger\.(.+)|category\.(.+))$') {
            $loggerName = if ($matches[1] -in @('rootLogger', 'rootCategory')) { 'ROOT' } elseif ($matches[2]) { $matches[2] } else { $matches[3] }
            $firstToken = ($val -split ',')[0].Trim().ToUpperInvariant()
            if ($firstToken -in @('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'OFF', 'ALL')) {
                $loggers.Add([PSCustomObject]@{
                    LoggerName = $loggerName
                    Key        = $key
                    Level      = $firstToken
                    LineNumber = $i + 1
                    Schema     = 'Log4j1Properties'
                })
            }
            continue
        }

        # Pattern 2: Log4j 2.x properties -> logger.<id>.level = DEBUG / rootLogger.level = DEBUG
        if ($key -match '^(rootLogger\.level|logger\.[^.]+\.level)$' -or $key -match '(?i)(^|\.)(log\.?level|logging\.level\..+)$') {
            $firstToken = ($val -split ',')[0].Trim().ToUpperInvariant()
            if ($firstToken -in @('TRACE', 'DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL', 'OFF', 'ALL')) {
                $loggers.Add([PSCustomObject]@{
                    LoggerName = $key
                    Key        = $key
                    Level      = $firstToken
                    LineNumber = $i + 1
                    Schema     = 'PropertiesLevelKey'
                })
            }
        }
    }

    if (-not $hasKeyValues) {
        return [PSCustomObject]@{
            IsValid       = $false
            StructureType = 'INVALID_PROPERTIES'
            Error         = 'No valid key=value property entries found.'
            Loggers       = @()
        }
    }

    return [PSCustomObject]@{
        IsValid       = $true
        StructureType = 'JAVA_PROPERTIES'
        Error         = $null
        Loggers       = $loggers.ToArray()
    }
}

function Set-PropertiesFileLoggerLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$TargetLoggerName,

        [Parameter(Mandatory = $false)]
        [string]$NewLevel = 'INFO'
    )

    $newline = if ($Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = $Content -split "`r?`n"
    $updated = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('!')) {
            continue
        }

        if ($line -match '^(\s*)([^=:]+?)(\s*[=:]\s*)(.*)$') {
            $indent = $matches[1]
            $key = $matches[2].Trim()
            $sep = $matches[3]
            $val = $matches[4]

            $matchesTarget = $false
            if ($key -eq $TargetLoggerName) {
                $matchesTarget = $true
            }
            elseif ($TargetLoggerName -eq 'ROOT' -and $key -in @('log4j.rootLogger', 'log4j.rootCategory')) {
                $matchesTarget = $true
            }
            elseif ($key -eq "log4j.logger.$TargetLoggerName" -or $key -eq "log4j.category.$TargetLoggerName") {
                $matchesTarget = $true
            }

            if ($matchesTarget) {
                # Preserve trailing appenders (e.g. "DEBUG, fileAppender" -> "INFO, fileAppender")
                $parts = $val -split ',', 2
                if ($parts.Count -eq 2) {
                    $lines[$i] = "{0}{1}{2}{3},{4}" -f $indent, $key, $sep, $NewLevel, $parts[1]
                }
                else {
                    $lines[$i] = "{0}{1}{2}{3}" -f $indent, $key, $sep, $NewLevel
                }
                $updated = $true
            }
        }
    }

    if (-not $updated) {
        throw "Target logger '$TargetLoggerName' was not found in properties file."
    }

    return ($lines -join $newline)
}
