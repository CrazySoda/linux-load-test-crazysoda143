#!/bin/bash
# Part 3 — Stress the system: disk (tmpfs fill), CPU, memory, or all at once.
# Usage: ./03_stress_and_populate.sh --cpu | --mem | --disk | --all
set -uo pipefail

SVC_NAME="${SVC_NAME:-bgdsvc_crazysoda143}"
MNT="/mnt/${SVC_NAME}_tmp"
DURATION="${DURATION:-30}"
FILES="${FILES:-30}"   # 30 x 10M > 256M, so the cap is actually hit (20 x 10M = 200M would not)

# Run as the service account from a directory it can read (avoids cwd warnings).
as_svc() { (cd /tmp && sudo -u "$SVC_NAME" "$@"); }

have_stress_ng() { command -v stress-ng >/dev/null 2>&1; }

stress_disk() {
  if ! mountpoint -q "$MNT"; then
    echo "$MNT is not mounted — run 02_setup_tmpfs.sh first." >&2
    return 1
  fi
  echo "=== Disk: writing $FILES x 10M files into a 256M tmpfs ==="
  df -h "$MNT"
  for i in $(seq 1 "$FILES"); do
    if ! as_svc dd if=/dev/urandom of="$MNT/file_$i.dat" bs=1M count=10 status=none; then
      echo ">>> Write of file_$i.dat FAILED — tmpfs is full (size cap reached)."
      df -h "$MNT"
      break
    fi
    echo "file_$i.dat written"
    df -h "$MNT" | tail -n 1
  done
}

stress_cpu() {
  echo "=== CPU: 2 workers for ${DURATION}s ==="
  if have_stress_ng; then
    as_svc stress-ng --cpu 2 --timeout "${DURATION}s" --metrics-brief
  else
    echo "stress-ng not found — falling back to 'yes > /dev/null'"
    as_svc timeout "$DURATION" yes >/dev/null &
    as_svc timeout "$DURATION" yes >/dev/null &
    wait
  fi
}

stress_mem() {
  echo "=== Memory: 1 VM worker, 200M for ${DURATION}s ==="
  if have_stress_ng; then
    as_svc stress-ng --vm 1 --vm-bytes 200M --timeout "${DURATION}s" --metrics-brief
  else
    echo "stress-ng not found — falling back to a python 200M allocation"
    as_svc timeout "$DURATION" python3 -c 'import time; b=bytearray(200*1024*1024); time.sleep(10**6)'
  fi
}

snapshot() {
  echo "----- free -h ($1) -----"
  free -h
}

stress_all() {
  snapshot "before"
  stress_cpu &
  local cpu_pid=$!
  stress_mem &
  local mem_pid=$!
  stress_disk &
  local disk_pid=$!

  sleep 5
  snapshot "during"
  echo "Tip: in a second terminal run: free -h ; top ; sudo dmesg | grep -i oom"

  wait "$cpu_pid" "$mem_pid" "$disk_pid"
  snapshot "after"
  echo "----- dmesg | grep -i oom -----"
  sudo dmesg | grep -i oom || echo "(no OOM events — the OOM killer did not fire)"
}

case "${1:-}" in
  --disk) stress_disk ;;
  --cpu)  stress_cpu ;;
  --mem)  stress_mem ;;
  --all)  stress_all ;;
  *)
    echo "Usage: $0 --cpu | --mem | --disk | --all"
    exit 1
    ;;
esac
