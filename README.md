# remote-apt-update

A lightweight Bash script to **check** and **upgrade** APT packages on remote Debian/Ubuntu hosts over SSH. Zero dependencies on the remote side — just `bash`, `apt`, and `ssh`.

## ✨ Features

- **Check mode** — list upgradable packages without touching the system
- **Upgrade mode** — non-interactive `apt upgrade` with before/after diff showing exactly what changed (package name, old version → new version)
- **Auto sudo** — uses `sudo` only when not already root; works seamlessly with `SSH_USER=root`
- **SSH flexibility** — auto-discovers SSH keys (`id_ed25519` → `id_ecdsa` → `id_rsa`), works with SSH agent, `~/.ssh/config`, or an explicit key via `SSH_KEY=`
- **Secure by default** — uses `StrictHostKeyChecking=accept-new` (auto-accepts new hosts, rejects changed keys for MITM protection)
- **APT warnings separated** — repo errors (`E:`) and warnings (`W:`) are displayed clearly without polluting the package list or inflating counts
- **Reboot detection** — flags when a kernel or firmware update requires a reboot
- **Audit log** — every run is appended to `~/logs/apt-upgrades.log` with timestamps, node name, and package-level detail
- **Portable** — no tools to install on remote hosts; works on any Debian, Ubuntu, or Raspbian system

## 📦 Requirements

| Where | What |
|-------|------|
| **Local** (where you run the script) | Bash 4+, OpenSSH client (`ssh`) |
| **Remote** (target host) | `bash`, `apt`, `dpkg`, `sudo` (if not connecting as root) |

> **Note:** The remote user must have passwordless `sudo` privileges (standard on Raspberry Pi OS, Ubuntu cloud images, etc.) or you must connect as `root` directly.

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/<you>/remote-apt-update.git
cd remote-apt-update

# Make executable
chmod +x remote-apt-update.sh

# Check upgradable packages on a host
./remote-apt-update.sh 192.168.1.50

# Upgrade packages on a host
./remote-apt-update.sh 192.168.1.50 upgrade
```

## 📖 Usage

```
remote-apt-update 1.0.0 — remote APT check & upgrade over SSH

Usage: remote-apt-update.sh <hostname|ip> [check|upgrade]

Commands:
  check    (default)  Run apt update and list upgradable packages
  upgrade              Run apt update + apt upgrade and show summary
```

### Environment Variables

All configuration is done via environment variables — no config files needed:

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_USER` | `$USER` (current user) | Remote SSH username |
| `SSH_KEY` | *(auto-discover)* | Path to SSH private key. If unset, the script scans `~/.ssh/` for `id_ed25519`, `id_ecdsa`, or `id_rsa` (in that order) |
| `LOGDIR` | `~/logs` | Directory for the audit log file (`apt-upgrades.log`) |

### Examples

```bash
# Simplest — current user, auto-discovered key
./remote-apt-update.sh myserver

# Check only (explicit, same as default)
./remote-apt-update.sh myserver check

# Upgrade packages
./remote-apt-update.sh myserver upgrade

# Specify remote user
SSH_USER=admin ./remote-apt-update.sh myserver upgrade

# Specify user + key explicitly
SSH_USER=deploy SSH_KEY=~/.ssh/deploy_ed25519 ./remote-apt-update.sh node3 upgrade

# Root login (sudo is auto-skipped on the remote side)
SSH_USER=root ./remote-apt-update.sh node4 upgrade

# Custom log directory
LOGDIR=/var/log/apt-remote ./remote-apt-update.sh myserver

# Multiple nodes in a loop
for node in node1 node2 node3; do
  ./remote-apt-update.sh "$node" check
done
```

## 📋 Output Examples

### Check — packages available

```
=== APT CHECK: 192.168.1.50 ===
[2026-05-13 10:52:33] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
📦 Packages available for upgrade on 192.168.1.50:

  libcamera-ipa/stable                          0.7.1+rpt20260429-1
  libcamera0.7/stable                           0.7.1+rpt20260429-1
  libpisp-common/stable,stable                  1.5.0-1
  libpisp1/stable                               1.5.0-1
  librpicam-app1/stable                         1.12.0-1
  rpi-eeprom/stable,stable                      28.17-1
  rpicam-apps-core/stable                       1.12.0-1

  → 7 package(s) can be upgraded.

[2026-05-13 10:52:34] Done.
```

### Check — system up to date

```
=== APT CHECK: 192.168.1.50 ===
[2026-05-13 12:00:01] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
✅ Nothing to upgrade on 192.168.1.50.

[2026-05-13 12:00:02] Done.
```

### Upgrade — with version diff and reboot notice

```
=== APT UPGRADE: 192.168.1.50 ===
[2026-05-13 11:05:10] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
🎉 Upgrade completed on 192.168.1.50:

  libcamera-ipa: 0.7.0 → 0.7.1+rpt20260429-1
  libcamera0.7: 0.7.0 → 0.7.1+rpt20260429-1
  rpi-eeprom: 28.16-1 → 28.17-1

  → 3 package(s) upgraded.

🔄 Reboot required on 192.168.1.50! (kernel/firmware update pending)

[2026-05-13 11:05:42] Done.
```

### APT warnings — displayed separately

When the remote host has repo issues, warnings are shown clearly without affecting the package list:

```
=== APT CHECK: 192.168.1.50 ===
[2026-05-13 10:52:33] Connecting as pi@192.168.1.50...

⚠️  APT warnings on 192.168.1.50:
  E: Could not open lock file /var/lib/apt/lists/lock - open (13: Permission denied)
  W: Problem unlinking the file /var/cache/apt/pkgcache.bin - RemoveCaches (13: Permission denied)

--- Output from 192.168.1.50 ---
📦 Packages available for upgrade on 192.168.1.50:
  ...
```

## 📝 Audit Log

Every run is appended to `~/logs/apt-upgrades.log` (configurable via `LOGDIR`):

```
[2026-05-13 10:52:34] [192.168.1.50] CHECK — 7 package(s) available for upgrade
[2026-05-13 11:05:42] [192.168.1.50] UPGRADE — 3 package(s) upgraded:
[2026-05-13 11:05:42] [192.168.1.50]   libcamera-ipa: 0.7.0 → 0.7.1+rpt20260429-1
[2026-05-13 11:05:42] [192.168.1.50]   libcamera0.7: 0.7.0 → 0.7.1+rpt20260429-1
[2026-05-13 11:05:42] [192.168.1.50]   rpi-eeprom: 28.16-1 → 28.17-1
[2026-05-13 11:05:42] [192.168.1.50] REBOOT REQUIRED
[2026-05-13 11:22:09] [node2] SSH FAILED
[2026-05-14 09:00:01] [node3] CHECK — nothing to upgrade
```

## 🔧 Integration Ideas

### Cron — daily check across all nodes

```bash
#!/bin/bash
NODES="node1 node2 node3 192.168.1.50"
for node in $NODES; do
  /home/user/remote-apt-update.sh "$node" check
done
```

```cron
0 8 * * * /home/user/scripts/check-all-nodes.sh >> /home/user/logs/cron-apt.log 2>&1
```

### n8n + Prometheus + Grafana + Telegram

Use this script as part of an event-driven upgrade pipeline:

```
Prometheus (scrape: apt_upgrades_pending metric)
  → Grafana (alert rule: pending > 0)
    → n8n webhook (orchestration)
      → Telegram notification (📦 "7 packages on node1")
      → Execute Command node: remote-apt-update.sh node1 upgrade
      → Telegram confirmation (🎉 "3 upgraded, reboot needed")
```

### SSH tips

If you manage many hosts, create entries in `~/.ssh/config` to simplify access:

```ssh-config
Host node1
  HostName 192.168.1.50
  User pi

Host node2
  HostName 192.168.1.51
  User admin
  IdentityFile ~/.ssh/deploy_key
```

Then simply:

```bash
./remote-apt-update.sh node1 upgrade
```

## 🛡️ Security Notes

- **`StrictHostKeyChecking=accept-new`** — automatically accepts host keys on first connection but rejects changed keys (protects against MITM attacks). If you need stricter control, pre-populate `~/.ssh/known_hosts` and set `StrictHostKeyChecking=yes` via your `~/.ssh/config`.
- **`BatchMode=yes`** — disables all interactive prompts (password, passphrase, host key confirmation). Authentication must work non-interactively via SSH keys.
- **`--force-confold` / `--force-confdef`** — during upgrades, existing config files are preserved (never overwritten by package defaults). This prevents silent config changes on production systems.
- **No secrets in the script** — all credentials are handled via SSH keys and environment variables.

## 🤝 Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## 📄 License

[MIT](LICENSE)
