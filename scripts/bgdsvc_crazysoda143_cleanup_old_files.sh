#!/bin/bash
SVC_NAME="bgdsvc_crazysoda143"          # same name exported in Part 1
TMPDIR="/mnt/${SVC_NAME}_tmp"
LOGFILE="/var/log/${SVC_NAME}/monitor.log"

# Remove test files older than 1 day so scratch space doesn't fill with stale runs
find "$TMPDIR" -type f -mtime +1 -delete
echo "$(date): cleanup run — removed files older than 1 day from $TMPDIR" >> "$LOGFILE"
