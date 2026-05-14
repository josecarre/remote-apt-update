# remote-apt-update

A lightweight Bash script to **check** and **upgrade** APT packages on remote Debian/Ubuntu hosts over SSH. Zero dependencies on the remote side — just `bash`, `apt`, and `ssh`.

## ✨ Features

- **Check mode** — list upgradable packages without touching the system
- **Upgrade mode** — non-interactive `apt-get upgrade --with-new-pkgs` with before/after diff showing exactly what changed (package name, old version → new version, and newly installed dependencies)
- **Auto sudo** — uses `sudo` only when not already root; works seamlessly with `SSH_USER=root`
- **SSH flexibility** — auto-discovers SSH keys (`id_ed25519` → `id_ecdsa` → `id_rsa`), works with SSH agent, `~/.ssh/config`, or an explicit key via `SSH_KEY=`
- **Secure by default** — uses `StrictHostKeyChecking=accept-new` (auto-accepts new hosts, rejects changed keys for MITM protection)
- **APT warnings separated** — repo errors (`E:`) and warnings (`W:`) are displayed clearly without polluting the package list or inflating counts
- **Upgrade failure diagnostics** — if `apt-get upgrade` fails, the actual APT error output is captured and displayed instead of being silently swallowed
- **Reboot detection** — flags when a kernel or firmware update requires a reboot
- **Audit log** — every run is appended to `~/logs/apt-upgrades.log` with timestamps, node name, and package-level detail
- **Portable** — no tools to install on remote hosts; works on any Debian, Ubuntu, Raspbian, or Proxmox system

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
remote-apt-update 1.2.0 — remote APT check & upgrade over SSH

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
[2026-05-14 07:39:21] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
📦 Packages available for upgrade on 192.168.1.50:

  linux-headers-rpi-2712/stable                 1:6.18.29-1+rpt1
  linux-headers-rpi-v8/stable                   1:6.18.29-1+rpt1
  linux-image-rpi-2712/stable                   1:6.18.29-1+rpt1
  linux-image-rpi-v8/stable                     1:6.18.29-1+rpt1

  → 4 package(s) can be upgraded.

[2026-05-14 07:39:26] Done.
```

### Check — system up to date

```
=== APT CHECK: 192.168.1.50 ===
[2026-05-14 12:00:01] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
✅ Nothing to upgrade on 192.168.1.50.

[2026-05-14 12:00:02] Done.
```

### Upgrade — with new dependencies and reboot notice

```
=== APT UPGRADE: 192.168.1.50 ===
[2026-05-14 07:45:10] Connecting as pi@192.168.1.50...

--- Output from 192.168.1.50 ---
🎉 Upgrade completed on 192.168.1.50:

  cpp-14-for-host: (new) → 14.2.0-19
  gcc-14-for-host: (new) → 14.2.0-19
  linux-headers-rpi-2712: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1
  linux-headers-rpi-v8: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1
  linux-image-rpi-2712: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1
  linux-image-rpi-v8: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1

  → 6 package(s) upgraded.

🔄 Reboot required on 192.168.1.50! (kernel/firmware update pending)

[2026-05-14 07:46:35] Done.
```

### Upgrade — failure with diagnostics

```
=== APT UPGRADE: 192.168.1.102 ===
[2026-05-14 08:39:34] Connecting as root@192.168.1.102...

--- Output from 192.168.1.102 ---
❌ Upgrade failed on 192.168.1.102. APT output:

  E: Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)
  E: Unable to acquire the dpkg frontend lock, is another process using it?

[2026-05-14 08:39:35] Done.
```

### APT warnings — displayed separately

```
=== APT CHECK: 192.168.1.50 ===
[2026-05-14 10:52:33] Connecting as pi@192.168.1.50...

⚠️  APT warnings on 192.168.1.50:
  W: Problem unlinking the file /var/cache/apt/pkgcache.bin - RemoveCaches (13: Permission denied)

--- Output from 192.168.1.50 ---
📦 Packages available for upgrade on 192.168.1.50:
  ...
```

## 🔍 How It Works

### `apt-get upgrade --with-new-pkgs` vs `apt-get dist-upgrade`

The script uses `apt-get upgrade --with-new-pkgs`, which matches the behaviour of interactive `apt upgrade`:

| Command | Installs new deps | Removes packages | Use case |
|---------|:-:|:-:|------|
| `apt-get upgrade` | ❌ | ❌ | Too conservative — skips kernel updates |
| **`apt-get upgrade --with-new-pkgs`** | ✅ | ❌ | **Safe default** — handles kernel + firmware |
| `apt-get dist-upgrade` | ✅ | ✅ | Major distro upgrades — best done manually |

> **Note:** `apt` (the CLI) and `apt-get` are not the same. `apt upgrade` silently adds `--with-new-pkgs`, while `apt-get upgrade` does not. This script uses `apt-get` (stable, script-safe interface) with the flag explicitly set.

### Upgrade diff

The script takes a snapshot of all installed package versions **before** and **after** the upgrade using `dpkg-query`, then uses `comm` to diff the sorted lists. This shows:

- **Upgraded packages** — `package: old_version → new_version`
- **Newly installed dependencies** — `package: (new) → version`

### SSH stdin safety

All `apt-get` commands use `</dev/null` to prevent `apt`/`dpkg` from consuming bytes from the SSH channel's stdin, which could interfere with remote script execution — a common pitfall in SSH-based automation scripts.

## 📝 Audit Log

Every run is appended to `~/logs/apt-upgrades.log` (configurable via `LOGDIR`):

```
[2026-05-14 07:39:26] [192.168.1.50] CHECK — 4 package(s) available for upgrade
[2026-05-14 07:46:35] [192.168.1.50] UPGRADE — 6 package(s) upgraded:
[2026-05-14 07:46:35] [192.168.1.50]   linux-headers-rpi-2712: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1
[2026-05-14 07:46:35] [192.168.1.50]   linux-image-rpi-2712: 1:6.12.25-1+rpt1 → 1:6.18.29-1+rpt1
[2026-05-14 07:46:35] [192.168.1.50] REBOOT REQUIRED
[2026-05-14 08:39:35] [192.168.1.102] UPGRADE FAILED — see console output
[2026-05-14 09:00:01] [node2] CHECK — nothing to upgrade
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
      → Telegram notification (📦 "4 packages on rpi4")
      → Execute Command node: remote-apt-update.sh rpi4 upgrade
      → Telegram confirmation (🎉 "6 upgraded, reboot needed")
```

### SSH tips

If you manage many hosts, create entries in `~/.ssh/config` to simplify access:

```ssh-config
Host rpi4
  HostName 192.168.1.50
  User pi

Host proxmox
  HostName 192.168.1.102
  User root
  IdentityFile ~/.ssh/deploy_key
```

Then simply:

```bash
./remote-apt-update.sh rpi4 upgrade
./remote-apt-update.sh proxmox upgrade
```

## 🛡️ Security Notes

- **`StrictHostKeyChecking=accept-new`** — automatically accepts host keys on first connection but rejects changed keys (protects against MITM attacks). If you need stricter control, pre-populate `~/.ssh/known_hosts` and set `StrictHostKeyChecking=yes` via your `~/.ssh/config`.
- **`BatchMode=yes`** — disables all interactive prompts (password, passphrase, host key confirmation). Authentication must work non-interactively via SSH keys.
- **`--force-confold` / `--force-confdef`** — during upgrades, existing config files are preserved (never overwritten by package defaults). This prevents silent config changes on production systems.
- **`</dev/null` on apt commands** — prevents `apt-get`/`dpkg` from reading SSH stdin, avoiding potential script corruption during remote execution.
- **No secrets in the script** — all credentials are handled via SSH keys and environment variables.

## 🤝 Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## 📄 License

[MIT](LICENSE)
