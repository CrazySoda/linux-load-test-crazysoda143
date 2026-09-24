#!/bin/bash
# Part 1 — Create the service account (idempotent: safe to run twice)
set -euo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_crazysoda143}"

if id "$SVC_NAME" >/dev/null 2>&1; then
  echo "User $SVC_NAME already exists — nothing to do."
else
  sudo useradd -r -m -s /usr/sbin/nologin "$SVC_NAME"
  echo "User $SVC_NAME created successfully."
fi

id "$SVC_NAME"
getent passwd "$SVC_NAME"
