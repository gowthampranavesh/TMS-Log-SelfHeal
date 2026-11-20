<#
.SYNOPSIS
    Integration test for WinRM gMSA Kerberos connectivity against non-production TMS servers.
    Run manually on the central management server before enabling production remediation.
#>

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $here)

. "$repoRoot\src\Common\Utilities.ps1"
. "$repoRoot\src\Common\RemoteSession.ps1"
. "$repoRoot\src\Discovery\Import-ServerInventory.ps1"

Describe 'WinRM & gMSA Integration Tests' {
    $cfg = Import-AgentConfig -ConfigPath "$repoRoot\config\AgentConfig.json"
    $invPath = Resolve-RepoPath -RepoRoot $repoRoot -PathValue $cfg.Inventory.FilePath
    $servers = @(Import-ServerInventory -FilePath $invPath)

    It 'Establishes WinRM PSSession to at least one test server using gMSA/Kerberos' {
        $servers.Count | Should BeGreaterThan 0
        $first = $servers[0]
        $session = Connect-TmsServerSession -Hostname $first.Hostname -WinRmConfig $cfg.WinRM
        try {
            $session.State | Should Be 'Opened'
            $remoteHost = Invoke-TmsRemoteScript -Session $session -ScriptBlock { $env:COMPUTERNAME }
            $remoteHost | Should Not BeNullOrEmpty
        }
        finally {
            Disconnect-TmsServerSession -Session $session
        }
    }
}
