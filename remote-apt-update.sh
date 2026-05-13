#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  remote-apt-update.sh — Check & upgrade APT packages on
#                         remote Debian/Ubuntu hosts over SSH
#
#  https://github.com/<you>/remote-apt-update
#  License: MIT
# ─────────────────────────────────────────────────────────────
set -euo pipefail

readonly VERSION="1.0.0"

# ── Helpers ────────────────────────────────────────────────
log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

die() { log "❌ $*" >&2; exit 1; }

LOGDIR="${LOGDIR:-$HOME/logs}"
readonly LOGFILE="$LOGDIR/apt-upgrades.log"

audit() { printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$NODE" "$*" >> "$LOGFILE"; }

usage() {
  cat <<EOF
remote-apt-update ${VERSION} — remote APT check & upgrade over SSH

Usage: $(basename "$0") <hostname|ip> [check|upgrade]

Commands:
  check    (default)  Run apt update and list upgradable packages
  upgrade              Run apt update + apt upgrade and show summary

Environment variables:
  SSH_USER   Remote user       (default: \$USER → ${USER:-$(whoami)})
  SSH_KEY    Private key path  (default: auto-discover ~/.ssh/id_*)
  LOGDIR     Log directory     (default: ~/logs)

Examples:
  $(basename "$0") 192.168.1.50
  $(basename "$0") myserver upgrade
  SSH_USER=admin $(basename "$0") node3 upgrade
  SSH_USER=root SSH_KEY=~/.ssh/deploy_key $(basename "$0") node4
EOF
  exit 0
}

# ── Pre-flight checks ─────────────────────────────────────
if (( BASH_VERSINFO[0] < 4 )); then
  die "Bash 4+ is required (found ${BASH_VERSION}). Please upgrade your shell."
fi

command -v ssh >/dev/null 2>&1 || die "ssh not found in PATH."

# ── Arguments ──────────────────────────────────────────────
[[ "${1:-}" =~ ^(-h|--help)$ ]] && usage
(( $# >= 1 )) || { usage >&2; exit 1; }

readonly NODE="$1"
readonly SUBCOMMAND="${2:-check}"
[[ "$SUBCOMMAND" =~ ^(check|upgrade)$ ]] || { usage >&2; exit 1; }

# ── SSH config ─────────────────────────────────────────────
readonly SSH_USER="${SSH_USER:-$USER}"

# accept-new: auto-accept first-time host keys, reject changed keys (MITM safe)
SSH_OPTS=(-o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)

if [[ -n "${SSH_KEY:-}" ]]; then
  [[ -f "$SSH_KEY" ]] || die "SSH_KEY not found: $SSH_KEY"
  SSH_OPTS+=(-i "$SSH_KEY")
else
  # Auto-discover default keys (same order as OpenSSH)
  for keytype in id_ed25519 id_ecdsa id_rsa; do
    keypath="$HOME/.ssh/$keytype"
    if [[ -f "$keypath" ]]; then
      SSH_OPTS+=(-i "$keypath")
      break
    fi
  done
fi
readonly -a SSH_OPTS

# Ensure log directory exists
mkdir -p "$LOGDIR"

run_remote() { ssh "${SSH_OPTS[@]}" "${SSH_USER}@${NODE}" bash 2>&1; }

# ── Remote script: CHECK ──────────────────────────────────
read -r -d '' REMOTE_CHECK <<'SCRIPT' || true
set -euo pipefail

# Use sudo only when not already root
SUDO=""; (( $(id -u) != 0 )) && SUDO="sudo" || true

# Refresh repos — stderr captured separately to keep stdout clean
APT_LOG=$($SUDO apt-get update -qq 2>&1 >/dev/null) || true
if [[ -n "$APT_LOG" ]]; then
  printf 'APT_WARNINGS_BEGIN\n%s\nAPT_WARNINGS_END\n' "$APT_LOG"
fi

UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v '^Listing' || true)

if [[ -z "$UPGRADABLE" ]]; then
  echo "STATUS:NOTHING_TO_UPGRADE"
else
  echo "STATUS:PACKAGES_AVAILABLE"
  echo "$UPGRADABLE"
fi

# Flag pending kernel / firmware reboots
if [[ -f /var/run/reboot-required ]]; then
  echo "STATUS:REBOOT_REQUIRED"
fi

exit 0
SCRIPT

# ── Remote script: UPGRADE ────────────────────────────────
read -r -d '' REMOTE_UPGRADE <<'SCRIPT' || true
set -euo pipefail

SUDO=""; (( $(id -u) != 0 )) && SUDO="sudo" || true

APT_LOG=$($SUDO apt-get update -qq 2>&1 >/dev/null) || true
if [[ -n "$APT_LOG" ]]; then
  printf 'APT_WARNINGS_BEGIN\n%s\nAPT_WARNINGS_END\n' "$APT_LOG"
fi

# Snapshot installed versions (associative array for O(1) lookups)
declare -A BEFORE_MAP=()
BEFORE_SORTED=$(dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort)
while IFS=$'\t' read -r pkg ver; do
  [[ -n "$pkg" ]] && BEFORE_MAP["$pkg"]="$ver"
done <<< "$BEFORE_SORTED"

# Non-interactive upgrade
$SUDO DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confold" \
  -o Dpkg::Options::="--force-confdef" \
  >/dev/null 2>&1 || true

# Snapshot after
AFTER_SORTED=$(dpkg-query -W -f='${Package}\t${Version}\n' 2>/dev/null | sort)

# Diff: lines only in AFTER → version changed or newly installed
CHANGED=""
while IFS=$'\t' read -r pkg ver_after; do
  [[ -z "$pkg" ]] && continue
  ver_before="${BEFORE_MAP[$pkg]:-}"
  if [[ -z "$ver_before" ]]; then
    CHANGED+="${pkg}: (new) → ${ver_after}"$'\n'
  else
    CHANGED+="${pkg}: ${ver_before} → ${ver_after}"$'\n'
  fi
done < <(comm -13 <(echo "$BEFORE_SORTED") <(echo "$AFTER_SORTED"))

if [[ -z "$CHANGED" ]]; then
  echo "STATUS:NOTHING_UPGRADED"
else
  echo "STATUS:UPGRADED"
  printf '%s' "$CHANGED"
fi

if [[ -f /var/run/reboot-required ]]; then
  echo "STATUS:REBOOT_REQUIRED"
fi

exit 0
SCRIPT

# ── Execute ────────────────────────────────────────────────
echo "=== APT ${SUBCOMMAND^^}: ${NODE} ==="
log "Connecting as ${SSH_USER}@${NODE}..."

if [[ "$SUBCOMMAND" == "check" ]]; then
  REMOTE_OUTPUT=$(run_remote <<< "$REMOTE_CHECK") \
    || { log "❌ SSH to ${NODE} failed."; audit "SSH FAILED"; exit 1; }
else
  REMOTE_OUTPUT=$(run_remote <<< "$REMOTE_UPGRADE") \
    || { log "❌ SSH to ${NODE} failed."; audit "SSH FAILED"; exit 1; }
fi

# ── Extract APT warnings (if any) ─────────────────────────
APT_WARNINGS=""
if grep -q '^APT_WARNINGS_BEGIN$' <<< "$REMOTE_OUTPUT" 2>/dev/null; then
  APT_WARNINGS=$(sed -n '/^APT_WARNINGS_BEGIN$/,/^APT_WARNINGS_END$/{ //d; p; }' <<< "$REMOTE_OUTPUT")
  REMOTE_OUTPUT=$(sed '/^APT_WARNINGS_BEGIN$/,/^APT_WARNINGS_END$/d' <<< "$REMOTE_OUTPUT")
fi

[[ -n "$APT_WARNINGS" ]] && {
  echo ""
  echo "⚠️  APT warnings on ${NODE}:"
  sed 's/^/  /' <<< "$APT_WARNINGS"
}

# ── Extract reboot flag ───────────────────────────────────
REBOOT_NEEDED=false
if grep -q '^STATUS:REBOOT_REQUIRED$' <<< "$REMOTE_OUTPUT" 2>/dev/null; then
  REBOOT_NEEDED=true
  REMOTE_OUTPUT=$(grep -v '^STATUS:REBOOT_REQUIRED$' <<< "$REMOTE_OUTPUT")
fi

# ── Display results ───────────────────────────────────────
echo ""
echo "--- Output from ${NODE} ---"

has_status() { grep -q "^STATUS:${1}$" <<< "$REMOTE_OUTPUT"; }

if has_status NOTHING_TO_UPGRADE; then
  echo "✅ Nothing to upgrade on ${NODE}."
  audit "CHECK — nothing to upgrade"

elif has_status PACKAGES_AVAILABLE; then
  PACKAGES=$(grep -v '^STATUS:' <<< "$REMOTE_OUTPUT" | grep -v '^$' || true)
  COUNT=$(grep -c '/' <<< "$PACKAGES" 2>/dev/null || echo 0)
  echo "📦 Packages available for upgrade on ${NODE}:"
  echo ""
  awk '{printf "  %-45s %s\n", $1, $2}' <<< "$PACKAGES"
  echo ""
  echo "  → ${COUNT} package(s) can be upgraded."
  audit "CHECK — ${COUNT} package(s) available for upgrade"

elif has_status NOTHING_UPGRADED; then
  echo "✅ System already up to date on ${NODE}."
  audit "UPGRADE — system already up to date"

elif has_status UPGRADED; then
  PACKAGES=$(grep -v '^STATUS:' <<< "$REMOTE_OUTPUT" | grep -v '^$' || true)
  COUNT=$(grep -c '→' <<< "$PACKAGES" 2>/dev/null || echo 0)
  echo "🎉 Upgrade completed on ${NODE}:"
  echo ""
  sed 's/^/  /' <<< "$PACKAGES"
  echo ""
  echo "  → ${COUNT} package(s) upgraded."
  audit "UPGRADE — ${COUNT} package(s) upgraded:"
  while IFS= read -r line; do
    [[ -n "$line" ]] && audit "  $line"
  done <<< "$PACKAGES"

else
  echo "⚠️  Unexpected output:"
  echo "$REMOTE_OUTPUT"
  audit "UNEXPECTED OUTPUT — see console"
fi

# ── Reboot notice ─────────────────────────────────────────
if [[ "$REBOOT_NEEDED" == true ]]; then
  echo ""
  echo "🔄 Reboot required on ${NODE}! (kernel/firmware update pending)"
  audit "REBOOT REQUIRED"
fi

echo ""
log "Done."
