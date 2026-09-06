#!/bin/bash
# Strict mode: exit on error (-e), unset variables (-u), and pipeline failures (-o)
set -euo pipefail

# Enterprise Defaults (Overridden dynamically by Jenkins environment injection)
JAVA_VERSION="${JAVA_VERSION:-25}"
APP_USER="${APP_USER:-$(whoami)}"
APP_DIR="${APP_DIR:-/home/${APP_USER}/app}"

echo "========================================="
echo "=== Running Pre-requisites (pre.sh) ==="
echo "=== OS Target: Standard Linux (dnf)   ==="
echo "=== Java Version: ${JAVA_VERSION}       ==="
echo "=== Target User:  ${APP_USER}       ==="
echo "========================================="

# 1. Linux Package Repository Updates & Utility Install (Using DNF)
echo "[INFO] Syncing DNF package repository..."
sudo dnf update -y
echo "[INFO] Ingesting core utilities (lsof, tar)..."
sudo dnf install lsof tar -y

# 2. Establish Dedicated System Application User
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    echo "[INFO] Creating unprivileged application owner: $APP_USER..."
    sudo useradd -r -s /sbin/nologin "$APP_USER"
else
    echo "[INFO] App user $APP_USER is already registered."
fi

# 3. Dynamic OpenJDK Installation & Path Linking
if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q "${JAVA_VERSION}"; then
    echo "[INFO] Java version matches desired release ($JAVA_VERSION). Skipping install."
else
    echo "[INFO] Fetching Linux OpenJDK ${JAVA_VERSION} binaries..."
    cd /opt
    sudo curl -L "https://download.oracle.com/java/${JAVA_VERSION}/latest/jdk-${JAVA_VERSION}_linux-x64_bin.tar.gz" -o "jdk-${JAVA_VERSION}.tar.gz"
    sudo tar -zxvf "jdk-${JAVA_VERSION}.tar.gz"
    
    # Establish system symlinks
    JDK_DIR=$(ls -d jdk-${JAVA_VERSION}*)
    sudo ln -sfn "/opt/$JDK_DIR" "/opt/jdk-${JAVA_VERSION}"
    sudo ln -sf "/opt/jdk-${JAVA_VERSION}/bin/java" /usr/bin/java
    sudo ln -sf "/opt/jdk-${JAVA_VERSION}/bin/javac" /usr/bin/javac
    
    sudo rm -f "jdk-${JAVA_VERSION}.tar.gz"
    echo "[INFO] Successfully established OpenJDK $JAVA_VERSION!"
    java -version
fi

# 4. Workspace Verification & Permissions Lock Down
echo "[INFO] Verifying App Directory permissions..."
sudo mkdir -p "${APP_DIR}"
sudo chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
sudo chmod -R 755 "${APP_DIR}"

echo "=== Environment Pre-requisite Validation Complete! ==="
