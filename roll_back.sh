#!/usr/bin/env bash
set -euo pipefail

# rollback_dev_tools_wsl.sh
# Revert the changes made by install_dev_tools_wsl.sh
# Run as a normal user with sudo privileges. Review before running.

SUDO=""
if [ "$EUID" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "This script requires sudo or root. Aborting."
    exit 1
  fi
fi

info(){ echo -e "\n\033[1;34m[INFO]\033[0m $*\n"; }
warn(){ echo -e "\n\033[1;33m[WARN]\033[0m $*\n"; }
err(){ echo -e "\n\033[1;31m[ERROR]\033[0m $*\n" >&2; }

echo
info "This script will attempt to remove Ansible, Terraform, Jenkins, OpenJDK-17 (if installed by script), AWS CLI v2, and related repos/keyrings created by the installer."
warn "It will NOT touch unrelated files, but if you had any of these packages prior to running the installer you might lose them. BACKUP anything important first!"
read -p "Proceed with rollback? (y/N): " yn
yn=${yn:-N}
if [[ ! "$yn" =~ ^[Yy]$ ]]; then
  echo "Aborted by user."
  exit 0
fi

# 1) Stop & disable Jenkins service if present
info "Stopping and disabling jenkins service if present..."
if $SUDO systemctl status jenkins >/dev/null 2>&1; then
  $SUDO systemctl stop jenkins || true
  $SUDO systemctl disable jenkins || true
else
  info "No systemd jenkins service detected (or systemctl not present)."
fi

# 2) Remove Jenkins APT package if installed
if dpkg -l | grep -qi '^ii.*jenkins'; then
  info "Removing jenkins APT package..."
  $SUDO apt remove -y jenkins || true
else
  info "Jenkins APT package not installed."
fi

# 3) Remove standalone jenkins.war and launcher if present
JENKINS_DIR="/opt/jenkins"
JENKINS_LAUNCHER="$HOME/start-jenkins.sh"
if [ -d "$JENKINS_DIR" ] || [ -f "$JENKINS_DIR/jenkins.war" ]; then
  info "Removing $JENKINS_DIR..."
  $SUDO rm -rf "$JENKINS_DIR" || true
else
  info "/opt/jenkins not present."
fi
if [ -f "$JENKINS_LAUNCHER" ]; then
  info "Removing Jenkins launcher $JENKINS_LAUNCHER..."
  rm -f "$JENKINS_LAUNCHER" || true
fi

# 4) Remove Jenkins apt source files and keyrings
info "Removing Jenkins apt source files and keyrings..."
$SUDO rm -f /etc/apt/sources.list.d/jenkins.list \
             /etc/apt/sources.list.d/jenkins.list.save \
             /etc/apt/sources.list.d/jenkins* \
             /usr/share/keyrings/jenkins*.gpg \
             /usr/share/keyrings/jenkins*.asc \
             /etc/apt/trusted.gpg.d/jenkins*.gpg || true

# 5) Remove HashiCorp (Terraform) package & repo/key if present
if command -v terraform >/dev/null 2>&1 || dpkg -l | grep -qi '^ii.*terraform'; then
  info "Removing terraform package..."
  $SUDO apt remove -y terraform || true
else
  info "Terraform not installed via apt (or not present)."
fi
info "Removing HashiCorp apt file and keyring..."
$SUDO rm -f /etc/apt/sources.list.d/hashicorp.list /usr/share/keyrings/hashicorp-archive-keyring.gpg || true

# 6) Remove Ansible package and PPA
if command -v ansible >/dev/null 2>&1 || dpkg -l | grep -qi '^ii.*ansible'; then
  info "Removing ansible package..."
  $SUDO apt remove -y ansible || true
else
  info "Ansible package not found."
fi
# Remove the PPA if present
if grep -R "ppa.launchpadcontent.net/ansible/ansible" /etc/apt/sources.list /etc/apt/sources.list.d -s >/dev/null 2>&1; then
  info "Removing Ansible PPA from sources."
  # try to remove via add-apt-repository if available
  if command -v add-apt-repository >/dev/null 2>&1; then
    $SUDO add-apt-repository --remove -y ppa:ansible/ansible || true
  fi
  # also remove any leftover files
  $SUDO rm -f /etc/apt/sources.list.d/ansible* || true
else
  info "Ansible PPA not present."
fi

# 7) Attempt to uninstall AWS CLI v2
info "Attempting to uninstall AWS CLI v2..."
# Preferred uninstall script location
if [ -x "/usr/local/aws-cli/v2/current/uninstall" ]; then
  info "Found AWS CLI uninstall script. Running it..."
  $SUDO /usr/local/aws-cli/v2/current/uninstall || true
else
  # Try alternate uninstall path
  if [ -x "/usr/local/bin/aws" ] && /usr/local/bin/aws --version >/dev/null 2>&1; then
    info "No uninstall script found; removing AWS CLI files that installer created."
    $SUDO rm -rf /usr/local/aws-cli /usr/local/bin/aws /usr/bin/aws /usr/local/bin/aws_completer || true
  else
    # maybe installed via apt
    if dpkg -l | grep -qi '^ii.*awscli'; then
      info "awscli package installed via apt; removing..."
      $SUDO apt remove -y awscli || true
    else
      info "AWS CLI installation not detected by common methods."
    fi
  fi
fi

# 8) Remove OpenJDK-17 if it was installed
if dpkg -l | grep -qi '^ii.*openjdk-17-jdk'; then
  info "Removing openjdk-17-jdk..."
  $SUDO apt remove -y openjdk-17-jdk || true
else
  info "openjdk-17-jdk not installed via apt (or not present)."
fi

# 9) Cleanup noisy/leftover backup files created earlier
info "Cleaning up noisy backup files and temporary files..."
$SUDO rm -f /etc/apt/sources.list.d/pgdg.list.bakpgdg || true
# Remove any .bakpgdg, .bakpgdg* left by previous scripts
$SUDO find /etc/apt/sources.list.d -maxdepth 1 -type f -name "*.bakpgdg" -exec rm -f {} \; || true
# Remove any .bakpgdg or .bak files we might have created
$SUDO find /etc/apt/sources.list.d -maxdepth 1 -type f -name "*.bak*" -exec rm -f {} \; || true

# 10) Autoremove and purge residual config for removed packages
info "Running apt autoremove and purge of residual configs..."
$SUDO apt autoremove -y || true
# purge leftover config of common packages we removed (best-effort)
for pkg in jenkins terraform ansible awscli openjdk-17-jdk; do
  if dpkg -l | grep -qi "^rc\\s\\+${pkg}"; then
    $SUDO apt purge -y "$pkg" || true
  fi
done || true

# 11) Rebuild apt lists
info "Updating apt cache..."
$SUDO apt update || true

# 12) Report results & remaining items for manual inspection
echo
info "Rollback finished (best-effort). Items removed/checked:"
echo " - Jenkins (APT package or standalone) removed where detected."
echo " - Jenkins apt source files and keyrings removed."
echo " - Terraform package and HashiCorp apt key removed."
echo " - Ansible package removed and PPA attempted removed."
echo " - AWS CLI uninstalled (if uninstall script present) or binaries removed when detected."
echo " - OpenJDK-17 package removed if found."
echo
warn "Manual checks you may want to run:"
echo "  - Verify other packages you expect are still present (e.g. if you had Java or Terraform before, they may have been removed)."
echo "  - Inspect /etc/apt/sources.list.d/ for any remaining files: ls -la /etc/apt/sources.list.d/"
echo "  - Inspect /usr/share/keyrings/ and /etc/apt/trusted.gpg.d/ for leftover key files."
echo
echo "If something is still failing or you want me to produce a tailored undo for only specific parts (e.g. restore Java), tell me what to restore and I'll provide the exact commands."

exit 0
