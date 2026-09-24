#!/bin/bash
# Runs Parts 1–8 end to end and saves every required output to ../evidence/<name>.txt
# (one file per required screenshot). Run as your normal user, NOT with sudo:
#   ./run_all.sh
set -uo pipefail

export SVC_NAME="bgdsvc_crazysoda143"
cd "$(dirname "$0")"
EVID="$(cd .. && pwd)/evidence"
mkdir -p "$EVID"
KEY="$HOME/.ssh/${SVC_NAME}_key"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o IdentitiesOnly=yes -i "$KEY")

# show <evidence-name> <command...> : print "$ cmd" + output to terminal and evidence file
show() {
  local name="$1"; shift
  { echo "\$ $*"; eval "$@" 2>&1; echo; } | tee -a "$EVID/$name.txt"
}
banner() { printf '\n\033[1;36m######## %s ########\033[0m\n' "$*"; }

sudo -v || exit 1
rm -f "$EVID"/*.txt
# keep sudo alive for the whole run
while true; do sudo -n true; sleep 50; done 2>/dev/null &
KEEPALIVE=$!
trap 'kill $KEEPALIVE 2>/dev/null' EXIT

banner "Part 0 — identity"
show 00_svc_name 'echo $SVC_NAME'

banner "Part 1 — create user"
show 01_id_created ./01_create_user.sh
show 01_id_created ./01_create_user.sh          # second run proves idempotency
show 01_id_created 'id "$SVC_NAME"'

banner "Part 2 — tmpfs"
show 02_df_before ./02_setup_tmpfs.sh

banner "Part 3 — stress"
command -v stress-ng >/dev/null || sudo apt-get install -y stress-ng
show 02_df_after ./03_stress_and_populate.sh --disk
show 02_df_after 'df -h "/mnt/${SVC_NAME}_tmp"'
show 03_stress_cpu_mem ./03_stress_and_populate.sh --cpu
show 03_stress_cpu_mem ./03_stress_and_populate.sh --mem

# Combined run: empty the scratch space, then CPU + memory + disk together
sudo -u "$SVC_NAME" find "/mnt/${SVC_NAME}_tmp" -type f -delete
show 03_free_before 'free -h'
DURATION=40 ./03_stress_and_populate.sh --all > "$EVID/03_stress_all_run.txt" 2>&1 &
ALL_PID=$!
sleep 12
show 03_free_during 'free -h'
show 03_free_during 'top -b -n 1 | head -n 20'
wait "$ALL_PID"
show 03_free_after 'free -h'
show 03_dmesg_oom 'sudo dmesg | grep -i oom || echo "(no output — the OOM killer never fired)"'

banner "Part 4 — SSH key access"
[ -f "$KEY" ] || ssh-keygen -t ed25519 -N "" -C "$SVC_NAME" -f "$KEY"
sudo mkdir -p "/home/$SVC_NAME/.ssh"
sudo cp "$KEY.pub" "/home/$SVC_NAME/.ssh/authorized_keys"
sudo chown -R "$SVC_NAME:$SVC_NAME" "/home/$SVC_NAME/.ssh"
sudo chmod 700 "/home/$SVC_NAME/.ssh"
sudo chmod 600 "/home/$SVC_NAME/.ssh/authorized_keys"
show 04_ssh_port22 'ssh "${SSH_OPTS[@]}" -v "$SVC_NAME"@localhost true 2>&1 | grep -E "Authenticated|Connecting to|not available|denied"'

banner "Part 5 — SSH hardening"
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 2222/tcp        # open the new port BEFORE moving sshd
fi
sudo tee "/etc/ssh/sshd_config.d/00-${SVC_NAME}.conf" >/dev/null <<EOF
Port 2222
PermitRootLogin no
PasswordAuthentication no
AllowUsers ${SVC_NAME}
EOF
if ! sudo sshd -t; then
  echo "sshd config invalid — removing drop-in"; sudo rm -f "/etc/ssh/sshd_config.d/00-${SVC_NAME}.conf"; exit 1
fi
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket 2>/dev/null || true
sudo systemctl restart ssh
sleep 2
show 04_ssh_success 'cat /etc/ssh/sshd_config.d/00-${SVC_NAME}.conf'
show 04_ssh_success 'sudo sshd -T | grep -E "^(port|permitrootlogin|passwordauthentication|allowusers) "'
show 04_ssh_success 'ss -tln | grep -E ":(22|2222) "'
show 04_ssh_success 'ssh "${SSH_OPTS[@]}" -v -p 2222 "$SVC_NAME"@localhost true 2>&1 | grep -E "Connecting to|Authenticated|not available"'
show 04_ssh_success 'ssh "${SSH_OPTS[@]}" -p 22 "$SVC_NAME"@localhost true 2>&1 | tail -n 1   # old port should be refused'

banner "Part 7 (log dir first) + Part 6 — cron"
sudo mkdir -p "/var/log/$SVC_NAME"
sudo chown "$SVC_NAME:$SVC_NAME" "/var/log/$SVC_NAME"
sudo install -m 755 "${SVC_NAME}_monitor.sh" "${SVC_NAME}_cleanup_old_files.sh" /usr/local/bin/
sudo crontab -u "$SVC_NAME" - <<EOF
*/5 * * * * /usr/local/bin/${SVC_NAME}_monitor.sh
0 2 * * * /usr/local/bin/${SVC_NAME}_cleanup_old_files.sh
EOF
show 05_crontab_l 'sudo crontab -l -u "$SVC_NAME"'
(cd /tmp && sudo -u "$SVC_NAME" "/usr/local/bin/${SVC_NAME}_monitor.sh")
(cd /tmp && sudo -u "$SVC_NAME" "/usr/local/bin/${SVC_NAME}_cleanup_old_files.sh")
show 05_crontab_l 'sudo tail -n 25 "/var/log/$SVC_NAME/monitor.log"'

banner "Part 7 — logrotate"
sudo tee "/etc/logrotate.d/$SVC_NAME" >/dev/null <<EOF
/var/log/${SVC_NAME}/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
    create 0640 ${SVC_NAME} ${SVC_NAME}
    su ${SVC_NAME} ${SVC_NAME}
}
EOF
show 05_logrotate 'cat "/etc/logrotate.d/$SVC_NAME"'
show 05_logrotate 'sudo logrotate -f -v "/etc/logrotate.d/$SVC_NAME" 2>&1 | tail -n 15'
show 05_logrotate 'sudo ls -lh "/var/log/$SVC_NAME/"'

echo
echo "Parts 1–7 done. Environment is live (sshd is on port 2222 only, cron is running)."
echo "Take any live screenshots you want now (e.g. cat ../evidence/*.txt)."
if ! read -rp "Press Enter to run Part 8 cleanup (Ctrl+C to stop here and run ./04_cleanup.sh later)... "; then
  echo; echo "No terminal input — stopping before cleanup. Run ./04_cleanup.sh when ready."
  exit 0
fi

banner "Part 8 — cleanup"
show 06_cleanup_verify ./04_cleanup.sh
show 06_cleanup_verify ./04_cleanup.sh          # second run proves idempotency

banner "Done"
echo "All outputs saved in $EVID"
ls -1 "$EVID"
