#!/bin/bash
SVC_NAME="bgdsvc_crazysoda143"          # same name exported in Part 1
LOGFILE="/var/log/${SVC_NAME}/monitor.log"
echo "---- $(date) ----" >> "$LOGFILE"
free -h >> "$LOGFILE"
df -h "/mnt/${SVC_NAME}_tmp" >> "$LOGFILE" 2>&1
ps -u "$SVC_NAME" >> "$LOGFILE" 2>&1
