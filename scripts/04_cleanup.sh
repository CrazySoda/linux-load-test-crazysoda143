#!/bin/bash
# Part 8 — Tear everything down in reverse build order. Idempotent: every step
# tolerates the thing already being gone, so it is safe after a partial failure.
set -uo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_crazysoda143}"
MNT="/mnt/${SVC_NAME}_tmp"
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-${SVC_NAME}.conf"

step() { echo; echo "== $* =="; }

# 1. Kill anything still running
step "1. Kill processes owned by $SVC_NAME"
if id "$SVC_NAME" >/dev/null 2>&1; then
  sudo pkill -u "$SVC_NAME" || true
  sleep 1
  sudo pkill -9 -u "$SVC_NAME" || true
fi

# 2. Remove the automation (+ SSH hardening, since AllowUsers would name a deleted user)
step "2. Remove crontab, logrotate rule, helper scripts, SSH drop-in"
if id "$SVC_NAME" >/dev/null 2>&1; then
  sudo crontab -r -u "$SVC_NAME" 2>/dev/null || true
fi
sudo rm -f "/etc/logrotate.d/$SVC_NAME"
sudo rm -f "/usr/local/bin/${SVC_NAME}_monitor.sh"
sudo rm -f "/usr/local/bin/${SVC_NAME}_cleanup_old_files.sh"
if [ -f "$SSHD_DROPIN" ]; then
  sudo rm -f "$SSHD_DROPIN"
  sudo systemctl daemon-reload
  sudo systemctl restart ssh.socket 2>/dev/null || true
  sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
fi

# 3. Unmount storage
step "3. Unmount $MNT"
if mountpoint -q "$MNT"; then
  sudo umount "$MNT" || sudo umount -l "$MNT"
fi
[ -d "$MNT" ] && sudo rmdir "$MNT"

# 4. Remove logs
step "4. Remove /var/log/$SVC_NAME"
sudo rm -rf "/var/log/$SVC_NAME"

# 5. Finally, remove the identity itself
step "5. Delete user $SVC_NAME"
if id "$SVC_NAME" >/dev/null 2>&1; then
  sudo userdel -r "$SVC_NAME" 2>/dev/null || sudo userdel "$SVC_NAME"
fi
sudo rm -rf "/home/$SVC_NAME"

# Verify the crime scene is clean
step "Verification"
echo "\$ id $SVC_NAME"
id "$SVC_NAME" 2>&1 || true
echo "\$ mount | grep $SVC_NAME"
mount | grep "$SVC_NAME" || echo "(nothing mounted)"
echo "\$ ps -u $SVC_NAME"
ps -u "$SVC_NAME" 2>&1 || true
