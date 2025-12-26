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
# 1. Disable LTS release upgrade prompts
# -----------------------------------------------------------------------------
echo "Stop LTS upgrades..."
run_silent sed -i 's/^Prompt=.*/Prompt=never/' /etc/update-manager/release-upgrades

# -----------------------------------------------------------------------------
# 2. Update and upgrade base system
# -----------------------------------------------------------------------------
echo "Updating and upgrading system packages..."
run_silent apt update
run_silent apt full-upgrade -y

# -----------------------------------------------------------------------------
# 3. Install multimedia & codec support
# -----------------------------------------------------------------------------
echo "Installing ubuntu-restricted-extras..."
run_silent sudo DEBIAN_FRONTEND=noninteractive apt-get install ubuntu-restricted-extras -y

# -----------------------------------------------------------------------------
# 4. Install Flatpak and GNOME Flatpak plugin
# -----------------------------------------------------------------------------
echo "Installing Flatpak and GNOME Flatpak plugin..."
run_silent apt install flatpak -y
run_silent apt install gnome-software-plugin-flatpak -y
run_silent flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# -----------------------------------------------------------------------------
# 5. Remove Snap-based Firefox and stub, then clean Mozilla PPA
# -----------------------------------------------------------------------------
echo "Removing Snap version of Firefox (if installed)..."
if ! run_silent snap remove firefox; then
    echo "Snap Firefox already removed or not present."
fi

echo "Removing stub version of Firefox..."
run_silent apt remove firefox --purge -y

echo "Removing Mozillateam PPA (if present)..."
# Ignore errors if PPA is missing
run_silent add-apt-repository --remove -y ppa:mozillateam/ppa || true
run_silent rm -f /etc/apt/preferences.d/mozilla-firefox
run_silent rm -f /etc/apt/sources.list.d/mozillateam-ubuntu-ppa*

# -----------------------------------------------------------------------------
# 6. Add Mozilla’s official APT repository and pin Firefox to it
# -----------------------------------------------------------------------------
echo "Adding Mozilla's official APT repository..."
run_silent install -d -m 0755 /etc/apt/keyrings

# Download and register Mozilla APT signing key
run_silent bash -c "wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- > /etc/apt/keyrings/packages.mozilla.org.asc"

# Add Mozilla APT repo
run_silent bash -c "echo 'deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main' > /etc/apt/sources.list.d/mozilla.list"

echo "Creating APT pinning preferences for Firefox..."
run_silent bash -c "cat <<EOF > /etc/apt/preferences.d/mozilla
Package: firefox
Pin: origin packages.mozilla.org
Pin-Priority: 1001

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF"

echo "Updating package lists..."
run_silent apt update

echo "Installing Firefox from Mozilla if not present..."
if ! run_silent dpkg -s firefox; then
    run_silent apt install -y --allow-downgrades firefox
else
    echo "Firefox is already installed."
fi

# -----------------------------------------------------------------------------
# 7. Pin Firefox to the GNOME dock (user-level, optional)
# -----------------------------------------------------------------------------
echo "Pinning Firefox to the dock..."
run_silent gsettings set org.gnome.shell favorite-apps "$(gsettings get org.gnome.shell favorite-apps | sed -e "s/'firefox.desktop',*//" -e "s/\[\(.*\)\]/['firefox.desktop', \1]/")"

# -----------------------------------------------------------------------------
# 8. Configure UFW as a secure 'home' firewall profile
# -----------------------------------------------------------------------------
echo "Configuring UFW as a secure 'home' firewall profile..."
run_silent ufw default deny incoming
run_silent ufw default allow outgoing
run_silent ufw allow ssh
run_silent ufw --force enable

# -----------------------------------------------------------------------------
# 9. Install language and spelling support (Dutch & English variants)
# -----------------------------------------------------------------------------
echo "Installing language and spelling support (Dutch & English variants)..."
run_silent apt install -y \
  hunspell-nl \
  hunspell-en-za \
  hunspell-en-ca \
  hunspell-en-au \
  hunspell-en-gb \
  gnome-user-docs-nl \
  wdutch \
  language-pack-gnome-nl \
  language-pack-nl

# -----------------------------------------------------------------------------
# 10. Install Flatpak applications (HandBrake, VLC, Flatseal)
# -----------------------------------------------------------------------------
echo "Installing HandBrake (Flatpak)..."
run_silent flatpak install -y --system flathub fr.handbrake.ghb

echo "Installing VLC (Flatpak)..."
run_silent flatpak install -y --system flathub org.videolan.VLC

echo "Installing Flatseal (Flatpak permissions manager)..."
run_silent flatpak install -y --system flathub com.github.tchx84.Flatseal

# -----------------------------------------------------------------------------
# 11. Handle Snap seeding and refresh
# -----------------------------------------------------------------------------
echo "Checking if snapd is still seeding..."
if snap changes 2>/dev/null | grep -qi "Doing.*Seed"; then
    echo "Snap seeding still in progress, waiting..."
    run_silent snap wait system seed.loaded
fi

echo "Refreshing snaps..."
run_silent snap refresh

echo "Removing and cleaning up the Snap Store..."
run_silent snap remove snap-store
run_silent rm -f /home/*/.local/share/applications/snap-store_*.desktop 2>/dev/null || true

# -----------------------------------------------------------------------------
# 12. Configure system-wide GNOME defaults (dark mode + favorites)
# -----------------------------------------------------------------------------
echo "Configuring system-wide GNOME defaults (dark mode + favorites)..."

run_silent mkdir -p /etc/dconf/db/local.d

run_silent bash -c "cat << 'EOF' > /etc/dconf/db/local.d/00-gnome-settings
[org/gnome/desktop/interface]
color-scheme='prefer-dark'
enable-animations=false

[org/gnome/shell]
favorite-apps=['firefox.desktop', 'org.gnome.Nautilus.desktop', 'org.gnome.Terminal.desktop', 'org.gnome.Software.desktop']
EOF"

run_silent mkdir -p /etc/dconf/profile

run_silent bash -c "cat << 'EOF' > /etc/dconf/profile/user
user-db:user
system-db:local
EOF"

if ! run_silent dconf update; then
  echo "WARNING: dconf update failed (ignored)."
fi

echo "GNOME defaults configured (dark mode + Firefox pinned)."

# -----------------------------------------------------------------------------
# 13. Configure system-wide default applications (MIME: VLC + xarchiver)
# -----------------------------------------------------------------------------
echo "Configuring system-wide default applications (VLC + xarchiver)..."

run_silent mkdir -p /etc/xdg

run_silent bash -c "cat << 'EOF' > /etc/xdg/mimeapps.list
[Default Applications]
# Archives → xarchiver
application/zip=xarchiver.desktop;
application/x-7z-compressed=xarchiver.desktop;
application/vnd.rar=xarchiver.desktop;
application/x-rar=xarchiver.desktop;
application/x-compressed-tar=xarchiver.desktop;
application/x-bzip-compressed-tar=xarchiver.desktop;
application/x-xz-compressed-tar=xarchiver.desktop;

# Video → VLC
video/mp4=org.videolan.VLC.desktop;
video/x-msvideo=org.videolan.VLC.desktop;
video/x-matroska=org.videolan.VLC.desktop;
video/webm=org.videolan.VLC.desktop;
video/quicktime=org.videolan.VLC.desktop;
video/mpeg=org.videolan.VLC.desktop;
video/x-flv=org.videolan.VLC.desktop;
video/x-ms-wmv=org.videolan.VLC.desktop;
video/ogg=org.videolan.VLC.desktop;
EOF"

echo "System-wide default applications configured (VLC + xarchiver)."

# -----------------------------------------------------------------------------
# 14. Download and extract IPVanish configuration files
# -----------------------------------------------------------------------------
echo "Downloading IPVanish configuration files..."
DOWNLOAD_URL="https://configs.ipvanish.com/openvpn/v2.6.0-0/configs.zip"
TARGET="/tmp/configs.zip"

for i in {1..5}; do
    if run_silent wget -q "$DOWNLOAD_URL" -O "$TARGET"; then
        break
    fi
    echo "Download failed (attempt $i). Retrying in 3 seconds..."
    sleep 3
done

if [ ! -f "$TARGET" ]; then
    echo "ERROR: Download failed after 5 attempts. Skipping IPVanish config."
else
    echo "Extracting configs.zip to /opt/config..."
    run_silent mkdir -p /opt/config
    if ! run_silent unzip -q "$TARGET" -d /opt/config; then
        echo "unzip failed (ignored)."
    fi

    echo "Cleaning up zip file..."
    run_silent rm -f "$TARGET"
fi

# -----------------------------------------------------------------------------
# 15. First-boot cleanup: GNOME Initial Setup, telemetry, crash reporting, Ubuntu Pro
# -----------------------------------------------------------------------------
echo "Removing GNOME Initial Setup..."
if run_silent apt purge -y gnome-initial-setup; then
    echo "GNOME Initial Setup removed."
else
    echo "GNOME Initial Setup removal failed (ignored)."
fi

echo "Disabling telemetry and reporting pop-ups..."
if [ -f /etc/default/ubuntu-report ]; then
    if run_silent sed -i 's/enabled=1/enabled=0/' /etc/default/ubuntu-report; then
        echo "Ubuntu report telemetry disabled."
    else
        echo "Failed to modify ubuntu-report (ignored)."
    fi
else
    echo "ubuntu-report config not found (ignored)."
fi

if run_silent systemctl disable --now whoopsie.service; then
    echo "whoopsie crash reporting disabled."
else
    echo "whoopsie service not available (ignored)."
fi

echo "Disabling Ubuntu Pro prompts..."
run_silent mkdir -p /etc/ubuntu-advantage

run_silent bash -c "cat <<EOF > /etc/ubuntu-advantage/uaclient.conf
enable_auto_attached: false
EOF"

run_silent ua disable esm-infra || true

# -----------------------------------------------------------------------------
# 16. Final Flatpak update (system-wide)
# -----------------------------------------------------------------------------
echo "Updating system-wide Flatpaks..."
if ! run_silent flatpak update --system -y; then
    echo "Update failed (ignored)."
fi

# -----------------------------------------------------------------------------
# 17. Update the GRUB setting safely (issue: display is not active)
# -----------------------------------------------------------------------------
echo "Removing 'splash' from GRUB_CMDLINE_LINUX_DEFAULT..."
run_silent sed -i \
    's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\) splash\([^"]*"\)/\1\2/' \
    /etc/default/grub

echo "Updating GRUB..."
run_silent update-grub

echo "GRUB configuration updated (no splash)."

# -----------------------------------------------------------------------------
# 18. Completion message
# -----------------------------------------------------------------------------
echo "Configure complete."
echo "Logfile: $LOGFILE (view with: sudo tail -f $LOGFILE)"
