# Installation Guide

## 1. Prerequisites
- **Management Server**: Windows Server 2016/2019/2022 with Windows PowerShell 5.1.
- **gMSA Account**: Group Managed Service Account (e.g., `DOMAIN\gMSA_TmsLogAgent$`) installed on the management server (`Install-ADServiceAccount`) and granted local Administrator (or WinRM + file read/write) rights on target TMS servers.
- **WinRM**: Enabled on all target TMS servers (`Enable-PSRemoting -Force`) with Kerberos authentication.

## 2. Repository Deployment
1. Extract `TMS-Log-SelfHeal` to `C:\Automation\TMS-Log-SelfHeal`.
2. Place your server inventory CSV at `config\ServerInventory.csv` and update `Inventory.FilePath` in `config\AgentConfig.json`.

## 3. Windows Task Scheduler Setup (gMSA)
Create a daily scheduled task running under the gMSA:
- **Principal**: `DOMAIN\gMSA_TmsLogAgent$` (Run whether user is logged on or not; no password required).
- **Trigger**: Daily at 02:00 AM.
- **Action**: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Automation\TMS-Log-SelfHeal\src\Main.ps1"`
- **Multiple Instances**: Set to "Do not start a new instance" (reinforced by `data\agent.lock`).
