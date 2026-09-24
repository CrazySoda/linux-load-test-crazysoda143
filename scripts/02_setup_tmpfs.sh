#!/bin/bash
# Part 2 — Mount a size-capped tmpfs scratch area owned by the service account
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_crazysoda143}"
MNT="/mnt/${SVC_NAME}_tmp"
SIZE="256M"   # never mount tmpfs without a size cap

if ! id "$SVC_NAME" >/dev/null 2>&1; then
  echo "User $SVC_NAME does not exist — run 01_create_user.sh first." >&2
  exit 1
fi

sudo mkdir -p "$MNT"

if mountpoint -q "$MNT"; then
  echo "$MNT is already mounted — skipping mount."
else
  sudo mount -t tmpfs -o size="$SIZE" tmpfs "$MNT"
  echo "Mounted tmpfs ($SIZE) at $MNT."
fi

sudo chown "$SVC_NAME:$SVC_NAME" "$MNT"
df -h "$MNT"
