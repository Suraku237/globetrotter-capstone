#!/usr/bin/env bash
# One-time bootstrap for the VPS that hosts the frontend-deploy Jenkins job.
#
# Run once as a user with sudo (NOT as jenkins). After this script
# completes successfully, the frontend Jenkins pipeline
# (frontend/fast_travel/Jenkinsfile) can build and deploy the Flutter
# web app end-to-end without any further manual intervention.
#
#   sudo bash frontend/fast_travel/scripts/bootstrap-vps.sh
#
# What it does:
#   1. Installs the OS packages Flutter's bootstrap needs (unzip, xz-utils, rsync).
#   2. Grants the jenkins user passwordless sudo *only* for apt-get, so
#      future package installs can happen from inside the pipeline.
#   3. Cleans up any root-owned .dart_tool / build directories that a
#      previous manual run may have left in the Jenkins workspace.
#   4. Creates and permissions the nginx doc root that rsync writes into.
#
# The script is idempotent - re-running it is safe.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root (use sudo)." >&2
    exit 1
fi

JENKINS_USER="${JENKINS_USER:-jenkins}"
JENKINS_HOME="${JENKINS_HOME:-/var/lib/jenkins}"
WORKSPACE_DIR="${WORKSPACE_DIR:-$JENKINS_HOME/workspace/frontend-deploy}"
WEB_DIR="${WEB_DIR:-/var/www/fasttravel-web}"

echo "==> [1/4] Installing OS packages required by Flutter (unzip, xz-utils, rsync)"
apt-get update -y
apt-get install -y unzip xz-utils rsync

echo "==> [2/4] Granting $JENKINS_USER passwordless sudo for apt-get only"
SUDOERS_FILE="/etc/sudoers.d/jenkins-apt"
echo "$JENKINS_USER ALL=(root) NOPASSWD: /usr/bin/apt-get" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"
if ! visudo -c -f "$SUDOERS_FILE" >/dev/null; then
    rm -f "$SUDOERS_FILE"
    echo "Failed to install $SUDOERS_FILE (visudo rejected it). Aborting." >&2
    exit 1
fi

echo "==> [3/4] Cleaning up stale root-owned Flutter caches in the workspace"
if [ -d "$WORKSPACE_DIR/frontend/fast_travel" ]; then
    rm -rf \
        "$WORKSPACE_DIR/frontend/fast_travel/.dart_tool" \
        "$WORKSPACE_DIR/frontend/fast_travel/build" \
        "$WORKSPACE_DIR/frontend/fast_travel/.flutter-plugins" \
        "$WORKSPACE_DIR/frontend/fast_travel/.flutter-plugins-dependencies"
    chown -R "$JENKINS_USER":"$JENKINS_USER" "$WORKSPACE_DIR"
    echo "Cleaned $WORKSPACE_DIR/frontend/fast_travel/{.dart_tool,build,...}"
else
    echo "Workspace $WORKSPACE_DIR not present yet - Jenkins will create it on first checkout. Nothing to clean."
fi

echo "==> [4/4] Preparing nginx doc root $WEB_DIR"
mkdir -p "$WEB_DIR"
# jenkins owns it (so rsync from the pipeline can write), www-data is
# the group (so nginx can read). g+s makes new files inherit the group.
chown -R "$JENKINS_USER":www-data "$WEB_DIR"
chmod -R g+rX "$WEB_DIR"
chmod g+s "$WEB_DIR"

echo ""
echo "Bootstrap complete. The frontend-deploy pipeline should now run end-to-end."
