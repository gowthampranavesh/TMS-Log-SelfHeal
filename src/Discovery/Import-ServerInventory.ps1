<#
.SYNOPSIS
    Imports, normalizes, deduplicates, and filters TMS server inventory from CSV, JSON, or XML.
#>

function Import-ServerInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string[]]$IncludeServerTypes = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeServerTypes = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeHostnames = @()
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Server inventory file not found: $FilePath"
    }

    $ext = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    $rawRecords = @()

    switch ($ext) {
        '.csv' {
            $rawRecords = Import-Csv -LiteralPath $FilePath -Encoding UTF8
        }
        '.json' {
            $rawRecords = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        '.xml' {
            [xml]$xmlDoc = Get-Content -LiteralPath $FilePath -Raw -Encoding UTF8
            if ($xmlDoc.Servers -and $xmlDoc.Servers.Server) {
                $rawRecords = @($xmlDoc.Servers.Server)
            }
            elseif ($xmlDoc.results -and $xmlDoc.results.result) {
                # Splunk XML export format
                $rawRecords = @($xmlDoc.results.result)
            }
            else {
                throw "Unsupported XML inventory structure in: $FilePath"
            }
        }
        default {
            throw "Unsupported inventory file format '$ext'. Supported: .csv, .json, .xml."
        }
    }

    return ConvertTo-NormalizedServerInventory -Records $rawRecords `
        -IncludeServerTypes $IncludeServerTypes `
        -ExcludeServerTypes $ExcludeServerTypes `
        -ExcludeHostnames $ExcludeHostnames
}

function ConvertTo-NormalizedServerInventory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [object[]]$Records = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$IncludeServerTypes = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeServerTypes = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludeHostnames = @()
    )

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $normalized = New-Object System.Collections.Generic.List[object]

    foreach ($rec in $Records) {
        if ($null -eq $rec) { continue }

        $hostname = Get-FirstPropertyValue -Object $rec -Names @('Hostname', 'hostname', 'Host', 'host', 'ServerName', 'server_name')
        if ([string]::IsNullOrWhiteSpace($hostname)) { continue }
        $hostname = $hostname.Trim().ToUpperInvariant()

        # Basic hostname validation (alphanumeric, hyphen, dot)
        if ($hostname -notmatch '^[A-Z0-9\-\.]+$') {
            if (Get-Command -Name 'Write-AgentLog' -ErrorAction SilentlyContinue) {
                Write-AgentLog -Level 'WARN' -Component 'Inventory' -Message "Skipping invalid hostname '$hostname'."
            }
            continue
        }

        if ($ExcludeHostnames -contains $hostname) { continue }
        if (-not $seen.Add($hostname)) { continue }

        $customer = Get-FirstPropertyValue -Object $rec -Names @('Customer', 'customer', 'CustomerName', 'customer_name')
        if ([string]::IsNullOrWhiteSpace($customer)) { $customer = 'UNKNOWN' }

        $serverType = Get-FirstPropertyValue -Object $rec -Names @('ServerType', 'server_type', 'Type', 'type')
        if ([string]::IsNullOrWhiteSpace($serverType) -and $hostname.Length -ge 2) {
            $serverType = $hostname.Substring(0, 2)
        }
        $serverType = ([string]$serverType).Trim().ToUpperInvariant()

        if ($IncludeServerTypes.Count -gt 0 -and ($IncludeServerTypes -notcontains $serverType)) { continue }
        if ($ExcludeServerTypes.Count -gt 0 -and ($ExcludeServerTypes -contains $serverType)) { continue }

        $envName = Get-FirstPropertyValue -Object $rec -Names @('Environment', 'environment', 'Env', 'env')
        $status  = Get-FirstPropertyValue -Object $rec -Names @('Status', 'status', 'State', 'state')

        $normalized.Add([PSCustomObject]@{
            Customer    = $customer.Trim()
            Hostname    = $hostname
            ServerType  = $serverType
            Environment = if ($envName) { $envName.Trim() } else { '' }
            Status      = if ($status) { $status.Trim() } else { 'Active' }
        })
    }

    return $normalized.ToArray()
}

function Get-FirstPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($n in $Names) {
        $prop = $Object.PSObject.Properties[$n]
        if ($prop -and -not [string]::IsNullOrWhiteSpace([string]$prop.Value)) {
            return [string]$prop.Value
        }
    }
    return $null
}
