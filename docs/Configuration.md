# Configuration Guide

## 1. `config/AgentConfig.json`
- `DryRun` (`true` by default): Logs eligible remediations without modifying files.
- `EnableRemediation` (`false` by default): Must be `true` (with `DryRun: false`) to perform live edits.
- `Inventory.SourceType`: `"File"` (default for CSV) or `"Splunk"` (future REST API).
- `WinRM.Authentication`: `"Kerberos"` (for gMSA).
- `Backup.Mode`: `"SameFolder"` with `TimestampFormat: "yyyyMMdd_HHmmss"` (e.g., `log4j.xml.20261120_212335`).

## 2. `config/LogFileRegistry.xml`
Add new TMS components without touching PowerShell code by adding a `<Component>` block using `{DRIVE}` and `<LoggerPatterns>`.

## 3. `config/ServerDriveMapping.json`
Maps hostname regex patterns (`^PR` -> `F:`, `^DL`/`^FR`/default -> `D:`).
