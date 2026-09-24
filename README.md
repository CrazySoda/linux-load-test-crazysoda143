# linux-load-test-arian

BongoDev "A Linux SysAdmin Story". This repo builds a test environment for a new service, puts it under load, secures SSH access to it, automates monitoring, and then removes every trace of it.

**Service account:** `bgdsvc_crazysoda143`

```
.
├── README.md
├── observations.md
├── scripts/
│   ├── 01_create_user.sh
│   ├── 02_setup_tmpfs.sh
│   ├── 03_stress_and_populate.sh
│   ├── 04_cleanup.sh
│   ├── bgdsvc_crazysoda143_monitor.sh
│   ├── bgdsvc_crazysoda143_cleanup_old_files.sh
│   └── run_all.sh          # runs Parts 1–8 end to end, saving output to evidence/
├── evidence/               # raw command output captured during the run
└── screenshots/            # terminal renders of evidence/, one per required screenshot
```

All scripts fall back to `bgdsvc_crazysoda143` when `$SVC_NAME` is unset, so they work in a fresh shell.

---

## Runbook

```bash
export SVC_NAME=bgdsvc_crazysoda143
echo $SVC_NAME                                  # screenshot 00_svc_name.png
cd scripts
```

### Part 1: Identity
```bash
./01_create_user.sh                             # run it twice to show it is idempotent
id "$SVC_NAME"                                  # screenshot 01_id_created.png
```

### Part 2: tmpfs scratch space (256M cap)
```bash
./02_setup_tmpfs.sh                             # screenshot 02_df_before.png
```

### Part 3: Stress
```bash
sudo apt install stress-ng -y
./03_stress_and_populate.sh --disk              # 30 x 10M files -> hits the 256M cap, "No space left on device"
df -h "/mnt/${SVC_NAME}_tmp"                    # screenshot 02_df_after.png
./03_stress_and_populate.sh --cpu
./03_stress_and_populate.sh --mem

sudo -u "$SVC_NAME" find "/mnt/${SVC_NAME}_tmp" -type f -delete   # empty tmpfs before the combined run
DURATION=60 ./03_stress_and_populate.sh --all   # prints free -h before/during/after + dmesg OOM
```
While `--all` runs, open a second terminal and run `free -h`, `top`, and `sudo dmesg | grep -i oom`.
Screenshots: `03_free_before.png`, `03_free_during.png`, `03_free_after.png`, `03_dmesg_oom.png`.

### Part 4: SSH key access
```bash
ssh-keygen -t ed25519 -f ~/.ssh/${SVC_NAME}_key
sudo mkdir -p "/home/$SVC_NAME/.ssh"
sudo cp ~/.ssh/${SVC_NAME}_key.pub "/home/$SVC_NAME/.ssh/authorized_keys"
sudo chown -R "$SVC_NAME:$SVC_NAME" "/home/$SVC_NAME/.ssh"
sudo chmod 700 "/home/$SVC_NAME/.ssh"
sudo chmod 600 "/home/$SVC_NAME/.ssh/authorized_keys"

ssh -i ~/.ssh/${SVC_NAME}_key "$SVC_NAME"@localhost
```
The account's shell is `/usr/sbin/nologin`, so a successful login authenticates with the key and then prints
*"This account is currently not available."* and disconnects. That message means the key worked. To see a
clean success, run a single command instead: `ssh -v -i ~/.ssh/${SVC_NAME}_key "$SVC_NAME"@localhost true`.
In the `-v` output, look for `Authenticated to localhost ... using "publickey"`.

### Part 5: SSH hardening
This uses a drop-in file instead of editing `/etc/ssh/sshd_config` directly. Ubuntu's `sshd_config`
`Include`s `sshd_config.d/*.conf` at the top. For each option sshd uses the **first** value it reads, so a file named `00-…`
takes effect before anything else. `04_cleanup.sh` can also undo it by deleting a single file.

```bash
sudo tee /etc/ssh/sshd_config.d/00-bgdsvc_crazysoda143.conf <<'EOF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
AllowUsers bgdsvc_crazysoda143
EOF
sudo sshd -t                                    # validate config, must print nothing

# This machine uses socket activation (ssh.socket), so the port is taken from the
# config at daemon-reload. Restart the socket as well as the service:
sudo systemctl daemon-reload
sudo systemctl restart ssh.socket ssh
ss -tlnp | grep 2222

ssh -v -i ~/.ssh/${SVC_NAME}_key -p 2222 "$SVC_NAME"@localhost true   # screenshot 04_ssh_success.png
ssh -p 22 "$SVC_NAME"@localhost                 # should be refused: port 22 is closed now
```
If `ufw` is active, run `sudo ufw allow 2222/tcp` **before** restarting sshd.

### Part 6: Cron monitoring + nightly cleanup
Do Part 7's first two commands (create `/var/log/$SVC_NAME`) first, because the monitor script writes there.
```bash
sudo mkdir -p "/var/log/$SVC_NAME"
sudo chown "$SVC_NAME:$SVC_NAME" "/var/log/$SVC_NAME"

sudo install -m 755 bgdsvc_crazysoda143_monitor.sh           /usr/local/bin/
sudo install -m 755 bgdsvc_crazysoda143_cleanup_old_files.sh /usr/local/bin/

sudo crontab -u "$SVC_NAME" - <<'EOF'
*/5 * * * * /usr/local/bin/bgdsvc_crazysoda143_monitor.sh
0 2 * * * /usr/local/bin/bgdsvc_crazysoda143_cleanup_old_files.sh
EOF
sudo crontab -l -u "$SVC_NAME"                  # screenshot 05_crontab_l.png

# Run each script once by hand to confirm it works:
sudo -u "$SVC_NAME" /usr/local/bin/bgdsvc_crazysoda143_monitor.sh
sudo tail "/var/log/$SVC_NAME/monitor.log"
```

### Part 7: Logrotate
```bash
sudo tee /etc/logrotate.d/bgdsvc_crazysoda143 <<'EOF'
/var/log/bgdsvc_crazysoda143/*.log {
    daily
    rotate 5
    compress
    missingok
    notifempty
    size 10M
    create 0640 bgdsvc_crazysoda143 bgdsvc_crazysoda143
    su bgdsvc_crazysoda143 bgdsvc_crazysoda143
}
EOF
sudo logrotate -d "/etc/logrotate.d/$SVC_NAME"  # dry run
sudo logrotate -f "/etc/logrotate.d/$SVC_NAME"
sudo ls -lh "/var/log/$SVC_NAME/"               # monitor.log.1.gz (or .1) + fresh monitor.log
```
The `su` line is needed because the log directory is owned by a non-root user. Without it, logrotate
refuses to rotate and reports *"insecure permissions"*.

### Part 8: Leave no trace
```bash
./04_cleanup.sh                                 # screenshot 06_cleanup_verify.png
./04_cleanup.sh                                 # run it again to show it is idempotent
```
Cleanup runs in reverse build order: kill processes → remove cron, logrotate, helper scripts and the SSH drop-in →
unmount tmpfs → remove logs → delete the user. Afterwards it runs `id`, `mount | grep` and `ps -u`, and all three should come back empty.
The SSH drop-in is removed too. Otherwise `AllowUsers` would name a user that no longer exists, and nobody could log in over SSH.
