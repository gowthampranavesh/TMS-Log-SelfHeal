<#
.SYNOPSIS
    Retrieves TMS server inventory from Splunk REST API or falls back to local inventory file.
#>

function Get-SplunkServers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$AgentConfig,

        [Parameter(Mandatory = $true)]
        [string]$RepoRoot
    )

    $invCfg = $AgentConfig.Inventory
    if (-not $invCfg) {
        throw "AgentConfig is missing 'Inventory' section."
    }

    $includeTypes = if ($AgentConfig.Filters -and $AgentConfig.Filters.IncludeServerTypes) { @($AgentConfig.Filters.IncludeServerTypes) } else { @() }
    $excludeTypes = if ($AgentConfig.Filters -and $AgentConfig.Filters.ExcludeServerTypes) { @($AgentConfig.Filters.ExcludeServerTypes) } else { @() }
    $excludeHosts = if ($AgentConfig.Filters -and $AgentConfig.Filters.ExcludeHostnames) { @($AgentConfig.Filters.ExcludeHostnames) } else { @() }

    if ($invCfg.SourceType -eq 'File' -or -not $invCfg.Splunk) {
        $invPath = Resolve-RepoPath -RepoRoot $RepoRoot -PathValue $invCfg.FilePath
        Write-AgentLog -Level 'INFO' -Component 'Discovery' -Message "Loading server inventory from file: $invPath"
        return Import-ServerInventory -FilePath $invPath `
            -IncludeServerTypes $includeTypes `
            -ExcludeServerTypes $excludeTypes `
            -ExcludeHostnames $excludeHosts
    }

    # Splunk REST API mode (ready for future activation)
    $splunk = $invCfg.Splunk
    $credPath = Resolve-RepoPath -RepoRoot $RepoRoot -PathValue $splunk.CredentialPath
    if (-not (Test-Path -LiteralPath $credPath)) {
        throw "Splunk credential file not found at '$credPath'. Switch Inventory.SourceType to 'File' or export encrypted PSCredential."
    }

    $cred = Import-Clixml -LiteralPath $credPath
    $searchEndpoint = "{0}/services/search/jobs/export" -f $splunk.BaseUrl.TrimEnd('/')
    $body = @{
        search      = $splunk.SavedSearchOrQuery
        output_mode = if ($splunk.OutputFormat) { $splunk.OutputFormat } else { 'json' }
    }

    $response = Invoke-RestMethod -Uri $searchEndpoint -Method Post -Credential $cred -Body $body -TimeoutSec 60
    $records = @()

    if ($body.output_mode -eq 'json') {
        # Splunk export returns newline-delimited JSON objects or a results wrapper
        if ($response -is [string]) {
            foreach ($line in ($response -split "`n")) {
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    $obj = $line | ConvertFrom-Json
                    if ($obj.result) { $records += $obj.result } else { $records += $obj }
                }
            }
        }
        elseif ($response.results) {
            $records = @($response.results)
        }
        else {
            $records = @($response)
        }
    }

    return ConvertTo-NormalizedServerInventory -Records $records `
        -IncludeServerTypes $includeTypes `
        -ExcludeServerTypes $excludeTypes `
        -ExcludeHostnames $excludeHosts
}
