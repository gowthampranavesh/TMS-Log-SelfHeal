# Architecture — Blue Yonder TMS DEBUG Log Detection & Self-Healing Agent

## 1. System Overview

`TMS-Log-SelfHeal` is a centralized Windows PowerShell 5.1 automation agent executed on a management/jump server via Windows Task Scheduler (every 24 hours). It connects to remote Blue Yonder TMS Windows servers over WinRM, discovers logging configuration files defined in a centralized XML registry, detects `DEBUG` logger configurations, tracks their duration persistently, and optionally remediates loggers that remain in `DEBUG` for 48 hours or more.

## 2. End-to-End Execution Pipeline

1. **Initialization & Concurrency Guard (`src/Main.ps1`, `src/Common/`)**
   - Acquires a single-instance named Mutex / lockfile to prevent overlapping scheduled runs.
   - Loads `config/AgentConfig.json` and initializes structured logging (`logs/`).
2. **Inventory & Configuration Load (`src/Discovery/`, `src/Configuration/`)**
   - Queries Splunk REST API (or imports CSV/XML/JSON export) and normalizes server records (`Customer`, `Hostname`, `ServerType`, `Environment`, `Status`).
   - Deduplicates hostnames, drops invalid entries, and applies include/exclude filters.
   - Loads `config/LogFileRegistry.xml` (enabled components only) and `config/ServerDriveMapping.json`.
3. **Drive Resolution & Remote Discovery (`src/Configuration/`, `src/Scanner/`)**
   - Resolves `{DRIVE}` per server using regex rules in `ServerDriveMapping.json` (`PR*` -> `F:`, `DL*`/`FR*`/default -> `D:`).
   - Opens throttled WinRM sessions (`MaxConcurrentServers`) to reachable servers; logs `SERVER_UNAVAILABLE` and continues if a host is offline.
   - Expands wildcard paths from the registry on the remote server and collects matching file metadata.
4. **Parsing & DEBUG Detection (`src/Scanner/Parsers/`)**
   - Routes `.xml` files to `Read-Log4jXml.ps1` and `.properties` files to `Read-PropertiesFile.ps1`.
   - Evaluates logger names against the component's configured `<LoggerPatterns>`.
   - Flags unknown/unparseable structures as `MANUAL_REVIEW_REQUIRED` without modifying them.
5. **Persistent 48-Hour Tracking (`src/Tracking/`)**
   - Loads `data/debug-tracking.json`.
   - Keyed by `(Hostname, FilePath, LoggerName)`:
     - New `DEBUG` -> creates record with `FirstDetectedUtc`, status `DEBUG_DETECTED`.
     - Existing `DEBUG` (< 48h) -> updates `LastDetectedUtc`, preserves `FirstDetectedUtc`, status `TRACKING`.
     - Existing `DEBUG` (>= 48h) -> marks `ELIGIBLE`.
     - Changed to `INFO` (or non-DEBUG) -> closes active record.
     - File/logger missing -> marks `INACTIVE` (preserves history).
     - Server unreachable -> preserves existing `FirstDetectedUtc` untouched.
   - **Timing Limitation**: Because the agent runs once every 24 hours, the 48-hour clock starts at *first detection* rather than the exact moment an engineer enabled `DEBUG`.
6. **Safe Remediation & Rollback (`src/Remediation/`)**
   - Runs only if `DryRun -eq $false` and `EnableRemediation -eq $true`.
   - Pre-flight checks: server reachable, file exists, re-read confirms logger is still `DEBUG` and file hash/content matches expectations, duration >= 48h.
   - Steps: timestamped backup (`backups/`) -> targeted `DEBUG` to `INFO` edit -> syntax validation -> on validation failure, automatic restore from backup (`ROLLBACK_COMPLETED`).
   - Never restarts TMS services and never touches runtime `.log` files.
7. **Reporting & Audit (`src/Reporting/`)**
   - Writes consolidated Detection Report CSV, Remediation Report CSV, and structured audit logs (`logs/`).

## 3. Persistent Storage Design Evaluation

| Option | Pros | Cons | Recommendation |
|---|---|---|---|
| **Structured JSON (`data/debug-tracking.json`)** | Zero third-party dependencies; native to PS 5.1 (`ConvertTo-Json`/`ConvertFrom-Json`); human-inspectable; easy atomic write + `.bak` rotation | Single-writer only (mitigated by Mutex lock in `Main.ps1`) | **Recommended Default** for centralized single-scheduler execution |
| **CSV** | Easy to open in Excel | Poor support for nested metadata, schema evolution, and multi-line fields | Not recommended for primary state |
| **SQLite** | ACID transactions | Requires third-party binaries/modules (`PSSQLite` / `System.Data.SQLite.dll`), violating zero-dependency goal | Optional future upgrade |
| **SQL Server** | Multi-writer enterprise scale | Requires external DB provisioning and network/firewall setup | Optional future upgrade via built-in `System.Data.SqlClient` |

## 4. Open Questions / Missing Information

Before finalizing format-specific parser rules and Splunk/WinRM integration, confirm:
1. **Splunk Connectivity**: Exact Splunk REST API endpoint, authentication method (Bearer Token vs. username/password), and SPL query/field names.
2. **WinRM Configuration**: Whether target servers use HTTP (`5985`) or HTTPS (`5986`), Kerberos/NTLM/CredSSP, and whether a gMSA or service account is used.
3. **Actual Log4j & Properties Schemas**: Sample production/non-prod `log4j.xml` (Log4j 1.x `<category>`/`<priority>` vs. Log4j 2.x `<Logger level="DEBUG">`) and `TM/Properties/*.properties` files to ensure 100% parser coverage.
4. **Logger Scope**: Whether `<Pattern>*</Pattern>` should be narrowed for specific components (e.g., excluding root loggers or specific third-party packages).
5. **Central vs. Remote Backups**: Whether timestamped backups should be stored centrally on the agent server (`backups/<Hostname>/...`), on the target server, or both.
