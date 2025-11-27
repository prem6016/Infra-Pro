#!/usr/bin/env bash

# install_dev_tools_wsl.sh
# Installs: Ansible, Terraform, Jenkins (war if no systemd), AWS CLI v2
# Intended for WSL2 (Ubuntu). Run as a normal user with sudo privileges.

# Note: We do NOT use 'set -e' here because we need to handle Jenkins APT failures
# and fall back to WAR installation. We'll use explicit error checking instead.

# ---- configuration ----
JENKINS_WAR_URL="https://get.jenkins.io/war-stable/latest/jenkins.war"
JENKINS_INSTALL_DIR="/opt/jenkins"
JENKINS_USER="jenkins"
AWS_CLI_ZIP="awscliv2.zip"

# ---- helper funcs ----
info() { echo -e "\n\033[1;34m[INFO]\033[0m $*\n"; }
err()  { echo -e "\n\033[1;31m[ERROR]\033[0m $*\n" >&2; }
run_or_exit() {
  echo "+ $*"
  "$@" || { err "Command failed: $*"; exit 1; }
}
run_safe() {
  # Run command but don't exit on failure - useful for optional operations
  echo "+ $*"
  "$@" || true
}

# Ensure script run with sudo when needed
if [ "$EUID" -eq 0 ]; then
  SUDO=""
else
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    err "This script requires sudo. Install sudo or run as root."
    exit 1
  fi
fi

# ---- begin script ----
info "Updating apt and installing common prerequisites..."
$SUDO apt update -y
$SUDO apt upgrade -y
$SUDO apt install -y curl wget unzip gnupg lsb-release ca-certificates software-properties-common apt-transport-https

# ---- Ansible ----
info "Installing Ansible (from official PPA)..."
if command -v ansible >/dev/null 2>&1; then
  info "Ansible already installed: $(ansible --version | head -n1)"
else
  # Add PPA and install
  run_or_exit $SUDO add-apt-repository --yes --update ppa:ansible/ansible
  run_or_exit $SUDO apt update
  run_or_exit $SUDO apt install -y ansible
  info "Ansible installed: $(ansible --version | head -n1)"
fi

# ---- Terraform ----
info "Installing Terraform (HashiCorp apt repo)..."
if command -v terraform >/dev/null 2>&1; then
  info "Terraform already installed: $(terraform -version | head -n1)"
else
  # add HashiCorp GPG key and repo
  run_or_exit curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
  run_or_exit $SUDO apt update
  run_or_exit $SUDO apt install -y terraform
  info "Terraform installed: $(terraform -version | head -n1)"
fi

# ---- Java (required for Jenkins) ----
info "Installing OpenJDK 17 (required by Jenkins)..."
if java -version >/dev/null 2>&1; then
  info "Java present: $(java -version 2>&1 | head -n1)"
else
  run_or_exit $SUDO apt update
  run_or_exit $SUDO apt install -y openjdk-17-jdk
  info "Java installed: $(java -version 2>&1 | head -n1)"
fi

# ---- Jenkins ----
# Detect systemd availability
info "Detecting systemd availability..."
SYSTEMD_AVAILABLE=false
if command -v systemctl >/dev/null 2>&1; then
  # check if systemd is PID 1 or systemctl is functional
  if [ "$(ps -p 1 -o comm=)" = "systemd" ]; then
    SYSTEMD_AVAILABLE=true
  else
    # some environments expose systemctl but not systemd; try a harmless call
    if systemctl --version >/dev/null 2>&1; then
      # but ensure it's usable
      if systemctl list-unit-files >/dev/null 2>&1; then
        SYSTEMD_AVAILABLE=true
      fi
    fi
  fi
fi

JENKINS_INSTALLED=false

if $SYSTEMD_AVAILABLE && ! dpkg -l 2>/dev/null | grep -q "^ii.*jenkins"; then
  info "systemd detected — attempting Jenkins installation from official APT repository."
  
  # Try to add Jenkins repository and install
  info "Adding Jenkins repository..."
  run_safe curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key -o /tmp/jenkins.key
  
  if [ -f /tmp/jenkins.key ]; then
    run_safe $SUDO gpg --dearmor -o /usr/share/keyrings/jenkins-keyring.gpg < /tmp/jenkins.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.gpg] https://pkg.jenkins.io/debian-stable binary/" | $SUDO tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    
    # Try apt update - but suppress the exit on error
    if $SUDO apt update 2>&1 | tee /tmp/apt_update.log | grep -q "NO_PUBKEY\|not signed"; then
      info "Jenkins APT repository has GPG issues, skipping APT installation."
      run_safe $SUDO rm -f /etc/apt/sources.list.d/jenkins.list /usr/share/keyrings/jenkins-keyring.gpg
    elif run_safe $SUDO apt install -y jenkins; then
      run_safe $SUDO systemctl enable --now jenkins
      if systemctl is-active --quiet jenkins; then
        JENKINS_INSTALLED=true
        info "Jenkins service enabled and started. Check status: sudo systemctl status jenkins --no-pager"
      else
        info "Jenkins APT installation completed but service didn't start properly."
      fi
    fi
    rm -f /tmp/jenkins.key /tmp/apt_update.log
  fi
fi

# If systemd installation didn't work, or no systemd, use WAR
if ! $JENKINS_INSTALLED; then
  info "Installing Jenkins as standalone WAR in $JENKINS_INSTALL_DIR..."
  
  # Function to download and verify Jenkins WAR with retries
  download_jenkins_war() {
    local max_attempts=3
    local attempt=1
    local tmpfile="/tmp/jenkins_$$.war"
    
    while [ $attempt -le $max_attempts ]; do
      info "Download attempt $attempt of $max_attempts..."
      
      # Clean up any previous failed attempt
      rm -f "$tmpfile"
      
      # Download with timeout and progress
      if curl -L --max-time 300 --retry 2 "$JENKINS_WAR_URL" -o "$tmpfile"; then
        # Verify it's a valid JAR/WAR file
        if file "$tmpfile" | grep -q "Java"; then
          info "WAR file downloaded and verified successfully"
          run_or_exit $SUDO mkdir -p "$JENKINS_INSTALL_DIR"
          run_or_exit $SUDO chown "$(whoami):$(whoami)" "$JENKINS_INSTALL_DIR"
          run_or_exit mv "$tmpfile" "$JENKINS_INSTALL_DIR/jenkins.war"
          return 0
        else
          # Check file size - Jenkins WAR should be at least 50MB
          local size=$(stat -f%z "$tmpfile" 2>/dev/null || stat -c%s "$tmpfile" 2>/dev/null || echo 0)
          if [ "$size" -lt 52428800 ]; then
            err "Downloaded file too small ($size bytes), likely corrupted. Retrying..."
          else
            err "File exists but doesn't appear to be a valid JAR. Retrying..."
          fi
        fi
      else
        err "Download failed. Retrying..."
      fi
      
      attempt=$((attempt + 1))
      if [ $attempt -le $max_attempts ]; then
        info "Waiting before retry..."
        sleep 5
      fi
    done
    
    rm -f "$tmpfile"
    err "Failed to download Jenkins WAR after $max_attempts attempts"
    return 1
  }
  
  if [ -f "$JENKINS_INSTALL_DIR/jenkins.war" ]; then
    # Verify existing file is valid
    if file "$JENKINS_INSTALL_DIR/jenkins.war" | grep -q "Java"; then
      info "jenkins.war already present and valid in $JENKINS_INSTALL_DIR"
    else
      err "Existing jenkins.war is corrupted, removing and re-downloading..."
      $SUDO rm -f "$JENKINS_INSTALL_DIR/jenkins.war"
      download_jenkins_war || exit 1
    fi
  else
    download_jenkins_war || exit 1
  fi

  # create a simple launcher script
  cat > "$HOME/start-jenkins.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
JENKINS_HOME="${JENKINS_HOME:-$HOME/.jenkins}"
JENKINS_WAR="/opt/jenkins/jenkins.war"
JAVA_OPTS="${JAVA_OPTS:-}"
mkdir -p "$JENKINS_HOME"
echo "[INFO] Starting Jenkins..."
exec java $JAVA_OPTS -jar "$JENKINS_WAR" --httpPort=8080
EOF
  chmod +x "$HOME/start-jenkins.sh"
  info "Created launcher: $HOME/start-jenkins.sh"
  info "To start Jenkins in WSL run: ./start-jenkins.sh  (it will run in foreground)."
  info "If you want to run in background, use: nohup ./start-jenkins.sh &> ~/jenkins.log &"
  JENKINS_INSTALLED=true
fi


# ---- AWS CLI v2 ----
info "Installing AWS CLI v2..."
if command -v aws >/dev/null 2>&1; then
  info "AWS CLI already installed: $(aws --version 2>&1)"
else
  TMPDIR="$(mktemp -d)"
  pushd "$TMPDIR" >/dev/null
  run_or_exit curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$AWS_CLI_ZIP"
  run_or_exit unzip -q "$AWS_CLI_ZIP"
  # installer will copy to /usr/local/bin by default
  run_or_exit $SUDO ./aws/install --update
  popd >/dev/null
  rm -rf "$TMPDIR"
  info "AWS CLI installed: $(aws --version 2>&1)"
fi

# ---- Final checks & summary ----
info "Running verification commands..."
echo "----------------------------------------"
echo "Ansible:    $(ansible --version 2>&1 | head -n1 || echo 'not found')"
echo "Terraform:  $(terraform -version 2>&1 | head -n1 || echo 'not found')"
echo "AWS CLI:    $(aws --version 2>&1 || echo 'not found')"
echo "Java:       $(java -version 2>&1 | head -n1 || echo 'not found')"
if dpkg -l 2>/dev/null | grep -q "^ii.*jenkins"; then
  echo "Jenkins:    systemd service (check: sudo systemctl status jenkins)"
elif [ -f "$JENKINS_INSTALL_DIR/jenkins.war" ]; then
  echo "Jenkins:    standalone war at $JENKINS_INSTALL_DIR/jenkins.war"
  echo "Launcher:   $HOME/start-jenkins.sh"
  echo "To start:   ./start-jenkins.sh   or nohup ./start-jenkins.sh &> ~/jenkins.log &"
else
  echo "Jenkins:    not installed"
fi
echo "----------------------------------------"

info "Installation complete!"
if [ -f "$HOME/start-jenkins.sh" ]; then
  info "Remember to start Jenkins WAR with: ./start-jenkins.sh"
fi
