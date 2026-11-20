# TMS-Log-SelfHeal

Centralized, modular Windows PowerShell 5.1 agent for detecting `DEBUG` logging configurations across multi-customer **Blue Yonder TMS** environments and safely self-healing stale `DEBUG` loggers (`>= 48` hours) back to `INFO`.

## Key Capabilities

- **Dynamic Server Inventory**: Retrieves TMS server lists from Splunk (REST API or CSV/XML/JSON exports) with deduplication, filtering, and graceful offline handling.
- **Dynamic Drive Resolution**: Maps server prefixes (`PR` -> `F:`, `DL`/`FR`/default -> `D:`) via `config/ServerDriveMapping.json`.
- **Centralized Registry (`config/LogFileRegistry.xml`)**: Single source of truth for component paths (`{DRIVE}` placeholder + wildcard expansion), file types, and target logger patterns.
- **Format-Aware Parsers**: Safe XML (`log4j.xml`) and Java `.properties` parsers that preserve formatting, comments, and unrelated settings.
- **Persistent 48-Hour Tracking**: Atomic JSON state store tracking first-detection timestamps across daily runs.
- **Production-Safe Remediation**: `DryRun = true` and `EnableRemediation = false` by default; mandatory timestamped backup, syntax validation, automatic rollback on failure, and zero automatic service restarts.

## Repository Layout

- `config/` — Agent settings, XML file registry, drive mappings, and sample inventories.
- `src/` — Modular PowerShell source code (`Discovery`, `Configuration`, `Scanner`, `Tracking`, `Remediation`, `Reporting`, `Common`).
- `tests/` — Pester unit tests, integration tests, and sample `log4j.xml` / `.properties` fixtures.
- `docs/` — Architecture, installation, configuration, troubleshooting, and operations guides.
- `logs/`, `backups/`, `data/` — Runtime outputs (excluded from Git).

## Quick Start

See `docs/Architecture.md` for the system design and `docs/Installation.md` (forthcoming) for setup and Task Scheduler deployment.
