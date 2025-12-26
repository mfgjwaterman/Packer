#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Ensure script is run as root
# -----------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root. Use: sudo $0"
  exit 1
fi

# -----------------------------------------------------------------------------
# Logging: run commands silently but log all output
# -----------------------------------------------------------------------------
LOGFILE="/var/log/template-cleanup.log"

# Ensure logfile exists with safe permissions
touch "$LOGFILE"
chmod 600 "$LOGFILE"

DEBUG=false

# Parse command-line flags
for arg in "$@"; do
  case "$arg" in
    --debug)
      DEBUG=true
      ;;
  esac
done

# Execute a command, keep terminal clean, log everything to LOGFILE, preserve exit code
run_silent() {
    if [ "$DEBUG" = true ]; then
        # DEBUG MODE = log + realtime output
        {
            echo ">>> COMMAND: $*"
            "$@"
            EXIT=$?
            echo ">>> EXIT CODE: $EXIT"
            echo
        } 2>&1 | tee -a "$LOGFILE"
        return $EXIT
    else
        # NORMAL MODE = log, no console output
        {
            echo ">>> COMMAND: $*"
            "$@"
            EXIT=$?
            echo ">>> EXIT CODE: $EXIT"
            echo
        } >> "$LOGFILE" 2>&1
        return $EXIT
    fi
}
echo "[template-cleanup] Starting cleanup..."
echo "[template-cleanup] Logfile: $LOGFILE"

# -----------------------------------------------------------------------------
# 1) Clean cloud-init state (if present)
# -----------------------------------------------------------------------------
echo "[template-cleanup] Cleaning cloud-init state (if installed)..."
if command -v cloud-init >/dev/null 2>&1; then
  if ! run_silent cloud-init clean --logs; then
    echo "[template-cleanup] cloud-init clean failed (ignored)."
  fi
else
  echo "[template-cleanup] cloud-init not installed, skipping clean."
fi

# -----------------------------------------------------------------------------
# 2) Reset machine-id
# -----------------------------------------------------------------------------
echo "[template-cleanup] Resetting machine-id..."
run_silent truncate -s0 /etc/machine-id || true
run_silent rm -f /var/lib/dbus/machine-id || true
run_silent ln -s /etc/machine-id /var/lib/dbus/machine-id || true

# -----------------------------------------------------------------------------
# 3) Reset hostname to something neutral
#     Proxmox/cloud-init can set a proper hostname on first boot of a clone.
# -----------------------------------------------------------------------------
echo "[template-cleanup] Resetting hostname to 'localhost'..."
run_silent bash -c 'echo "localhost" > /etc/hostname'
run_silent hostnamectl set-hostname localhost || true

# -----------------------------------------------------------------------------
# 4) Harden root SSH access (no direct password login over SSH)
# -----------------------------------------------------------------------------
echo "[template-cleanup] Hardening root SSH access..."
if [ -f /etc/ssh/sshd_config ]; then
  # 4a) Set PermitRootLogin to 'prohibit-password' (keys allowed, no password)
  if grep -qE '^#?PermitRootLogin' /etc/ssh/sshd_config; then
    run_silent sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  else
    run_silent bash -c 'echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config'
  fi

  # 4b) Disable SSH password authentication entirely
  echo "[template-cleanup] Disabling SSH password authentication..."
  if grep -qE '^#?PasswordAuthentication' /etc/ssh/sshd_config; then
    run_silent sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
  else
    run_silent bash -c 'echo "PasswordAuthentication no" >> /etc/ssh/sshd_config'
  fi

  # Restart SSH daemon (ssh or sshd, depending on distro)
  if ! run_silent systemctl restart ssh; then
    run_silent systemctl restart sshd || true
  fi
else
  echo "[template-cleanup] /etc/ssh/sshd_config not found, skipping SSH hardening."
fi

# -----------------------------------------------------------------------------
# 5) Neutralize the packer user (do not delete, just disable login)
# -----------------------------------------------------------------------------
PACKER_USER="superuser"

if id "$PACKER_USER" &>/dev/null; then
  echo "[template-cleanup] Locking user '$PACKER_USER' and removing SSH keys..."
  # Lock password-based login
  run_silent passwd -l "$PACKER_USER" || true

  # Remove SSH keys if present
  if [ -d "/home/$PACKER_USER/.ssh" ]; then
    run_silent rm -f "/home/$PACKER_USER/.ssh/authorized_keys" || true
  fi
else
  echo "[template-cleanup] User '$PACKER_USER' not found, skipping."
fi

# -----------------------------------------------------------------------------
# 6) Clear shell history (root + packer user if present)
# -----------------------------------------------------------------------------
echo "[template-cleanup] Clearing shell history..."
run_silent truncate -s0 /root/.bash_history || true

if id "$PACKER_USER" &>/dev/null; then
  if [ -f "/home/$PACKER_USER/.bash_history" ]; then
    run_silent truncate -s0 "/home/$PACKER_USER/.bash_history" || true
  fi
fi

# -----------------------------------------------------------------------------
# 7) Remove custom sudoers file for packer (cleanup 90-packer)
# -----------------------------------------------------------------------------
echo "[template-cleanup] Removing sudoers override for 'packer' if present..."
if [ -f /etc/sudoers.d/90-packer ]; then
  run_silent rm -f /etc/sudoers.d/90-packer || true
fi

# -----------------------------------------------------------------------------
# 8) Cloud-init override: sudo must ask for a password
# -----------------------------------------------------------------------------
echo "[template-cleanup] Enforcing sudo to require password via cloud-init override..."
run_silent mkdir -p /etc/cloud/cloud.cfg.d

run_silent bash -c "cat << 'EOF' > /etc/cloud/cloud.cfg.d/99-sudo-password.cfg
# Override default sudo behaviour from cloud-init:
# require a password for sudo instead of NOPASSWD.
system_info:
  default_user:
    sudo: \"ALL=(ALL) ALL\"
EOF"

# -----------------------------------------------------------------------------
# 9) Final system cleanup: apt + temp files
# -----------------------------------------------------------------------------
echo "[cleanup] Performing final system cleanup..."

# Apt cleanup
if ! run_silent apt autoremove -y; then
  echo "[cleanup] autoremove failed (ignored)."
fi

if ! run_silent apt clean; then
  echo "[cleanup] apt clean failed (ignored)."
fi

# Remove leftover files (safe fail)
echo "[cleanup] Removing temp files..."
run_silent rm -f /tmp/*.deb 2>/dev/null || true

# -----------------------------------------------------------------------------
# 10) Completion
# -----------------------------------------------------------------------------
echo "[template-cleanup] Cleanup complete."
echo "[template-cleanup] Logfile available at: $LOGFILE"
