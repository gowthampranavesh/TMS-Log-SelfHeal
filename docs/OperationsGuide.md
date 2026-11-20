# Operations Guide

## Phased Rollout
1. **Detection-Only**: Keep `DryRun: true` and `EnableRemediation: false`. Review `logs\DetectionReport_*.csv` daily.
2. **48-Hour Verification**: Confirm `data\debug-tracking.json` accurately tracks `DEBUG` duration across 3 consecutive daily runs.
3. **Controlled Remediation**: Set `DryRun: false` and `EnableRemediation: true` for non-production first, verify same-folder backups (`*.yyyyMMdd_HHmmss`) and `logs\RemediationAudit_*.csv`, then promote to production.

## Log & Backup Retention
- Agent logs and CSV reports are pruned automatically after `RetentionDays.Logs` (default 30 days).
- Same-folder configuration backups are preserved on target TMS servers for manual audit/rollback.
