<#
.SYNOPSIS
    Safe parser and targeted updater for Log4j 1.x and Log4j 2.x XML configuration files.
#>

function Read-Log4jXmlContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlContent
    )

    try {
        $xmlDoc = New-Object System.Xml.XmlDocument
        $xmlDoc.PreserveWhitespace = $true
        $xmlDoc.LoadXml($XmlContent)
    }
    catch {
        return [PSCustomObject]@{
            IsValid       = $false
            StructureType = 'INVALID_XML'
            Error         = $_.Exception.Message
            Loggers       = @()
        }
    }

    $loggers = New-Object System.Collections.Generic.List[object]
    $root = $xmlDoc.DocumentElement
    if ($null -eq $root) {
        return [PSCustomObject]@{
            IsValid       = $false
            StructureType = 'EMPTY_XML'
            Error         = 'XML document has no root element.'
            Loggers       = @()
        }
    }

    $recognizedStructure = $false

    # Log4j 1.x: <log4j:configuration> or <configuration> with <category> / <logger> / <root>
    $v1Nodes = $xmlDoc.SelectNodes("//*[local-name()='category' or local-name()='logger' or local-name()='root']")
    foreach ($node in $v1Nodes) {
        $localName = $node.LocalName

        # Check Log4j 2.x attributes first: <Logger name="..." level="DEBUG"> or <Root level="DEBUG">
        if ($node.HasAttribute('level')) {
            $recognizedStructure = $true
            $loggerName = if ($localName -eq 'Root' -or $localName -eq 'root') { 'ROOT' } else { $node.GetAttribute('name') }
            if (-not [string]::IsNullOrWhiteSpace($loggerName)) {
                $loggers.Add([PSCustomObject]@{
                    LoggerName = $loggerName
                    Level      = $node.GetAttribute('level').Trim().ToUpperInvariant()
                    Schema     = 'Log4j2'
                    NodeName   = $localName
                })
            }
            continue
        }

        # Check Log4j 1.x child elements: <priority value="DEBUG"/> or <level value="DEBUG"/>
        $levelChild = $node.SelectSingleNode("./*[local-name()='priority' or local-name()='level']")
        if ($null -ne $levelChild -and $levelChild.HasAttribute('value')) {
            $recognizedStructure = $true
            $loggerName = if ($localName -eq 'root') { 'ROOT' } else { $node.GetAttribute('name') }
            if (-not [string]::IsNullOrWhiteSpace($loggerName)) {
                $loggers.Add([PSCustomObject]@{
                    LoggerName = $loggerName
                    Level      = $levelChild.GetAttribute('value').Trim().ToUpperInvariant()
                    Schema     = 'Log4j1'
                    NodeName   = $localName
                })
            }
        }
    }

    if (-not $recognizedStructure) {
        return [PSCustomObject]@{
            IsValid       = $false
            StructureType = 'UNKNOWN_XML_SCHEMA'
            Error         = 'No recognized Log4j 1.x or Log4j 2.x logger elements found.'
            Loggers       = @()
        }
    }

    return [PSCustomObject]@{
        IsValid       = $true
        StructureType = 'LOG4J_XML'
        Error         = $null
        Loggers       = $loggers.ToArray()
    }
}

function Set-Log4jXmlLoggerLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlContent,

        [Parameter(Mandatory = $true)]
        [string]$TargetLoggerName,

        [Parameter(Mandatory = $false)]
        [string]$NewLevel = 'INFO'
    )

    $xmlDoc = New-Object System.Xml.XmlDocument
    $xmlDoc.PreserveWhitespace = $true
    $xmlDoc.LoadXml($XmlContent)

    $updatedCount = 0
    $nodes = $xmlDoc.SelectNodes("//*[local-name()='category' or local-name()='logger' or local-name()='Logger' or local-name()='root' or local-name()='Root']")

    foreach ($node in $nodes) {
        $localName = $node.LocalName
        $nodeLoggerName = if ($localName -ieq 'root') { 'ROOT' } else { $node.GetAttribute('name') }

        if ($nodeLoggerName -ne $TargetLoggerName) { continue }

        if ($node.HasAttribute('level')) {
            $node.SetAttribute('level', $NewLevel)
            $updatedCount++
            continue
        }

        $levelChild = $node.SelectSingleNode("./*[local-name()='priority' or local-name()='level']")
        if ($null -ne $levelChild -and $levelChild.HasAttribute('value')) {
            $levelChild.SetAttribute('value', $NewLevel)
            $updatedCount++
        }
    }

    if ($updatedCount -eq 0) {
        throw "Target logger '$TargetLoggerName' was not found or could not be updated in XML."
    }

    # Serialize preserving formatting
    $sw = New-Object System.IO.StringWriter
    $xw = New-Object System.Xml.XmlTextWriter($sw)
    $xmlDoc.Save($xw)
    $xw.Flush()
    return $sw.ToString()
}
