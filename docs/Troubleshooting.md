# Troubleshooting Guide

- **`SERVER_UNAVAILABLE`**: Verify WinRM service (`winrm quickconfig`), firewall port 5985/5986, and gMSA permissions on the target host. Tracking timestamps are preserved automatically while offline.
- **`MANUAL_REVIEW_REQUIRED`**: Either the XML/properties file is malformed, uses an unrecognized schema, or was modified between scan and remediation. Inspect the file manually and update parser rules if needed.
- **`Another instance is already running`**: Check `data\agent.lock`. If a previous run crashed, delete `agent.lock` after confirming no `powershell.exe` process with that PID is active.
