# Observations

Test machine: 16 CPUs, 23 GiB RAM, 8 GiB swap. Service account `bgdsvc_crazysoda143`, run on 2026-09-24.

**What did I observe when the system was under load?**
The disk test failed cleanly, not in an ugly way. Files 1–25 filled the 256M tmpfs to 250M (98%). `dd` then wrote only part of
`file_26.dat` before stopping with *"No space left on device"*, leaving `df -h` at 256M / 0 available / 100%. Only that
one write failed. The rest of the machine was unaffected, because the `size=256M` cap kept the damage inside the service's scratch space.
During the combined `--all` run, `top` showed three `stress-ng` processes owned by the service account, each at 100% of a core.
The load average climbed from 0.68 to 2.39. Overall CPU was only about 18% busy, because 3 busy cores out of 16 is only about 19%.
`free -h` showed *used* going from 6.5Gi to 6.8Gi and *free* dropping from 984Mi to 654Mi. *Shared* jumped from 43Mi to 331Mi,
which is the tmpfs: files in tmpfs are stored in RAM and counted as shared memory. *Available* stayed at 16Gi. The
most telling number came after the test. Once the stress processes exited, *used* dropped back to 6.6Gi, but *shared* stayed at 298Mi. The CPU
and VM load is released when the processes exit, but tmpfs keeps its RAM until the files are deleted. A full tmpfs is therefore a permanent
memory leak until someone cleans it up, which is exactly why the nightly cleanup cron job matters. `dmesg | grep -i oom` found no
OOM kills. The only matches were a boot-time `systemd-oomd` line and two false positives from the word "z**oom**". The kernel
never had to kill anything, because 200M of stress plus 256M of tmpfs is small next to 16Gi available.

**What would I do differently on a real production server?**
First, I would put hard limits on the service instead of trusting it to behave. I would run it as a systemd unit with `MemoryMax=` and `CPUQuota=`, so the kernel
caps it and the OOM killer targets the service rather than sshd or a database. I would also size tmpfs from real
free memory, since it quietly holds on to its RAM. Second, I would replace the 5-minute `free`/`df` cron job with real monitoring and alerting
(node_exporter + Prometheus/Alertmanager on disk %, memory, load and OOM events), so someone gets paged at 80%, not 100%.
Third, I would search for OOM kills more precisely (`dmesg | grep -iE 'out of memory|oom-kill'` or `journalctl -k`), since `grep -i oom`
also matched "zoom". Fourth, for SSH I would open port 2222 in the firewall/security group first, test it from a second session, and only then
close 22, keeping console access as a fallback. The run confirmed that port 22 was refused straight after the switch. I would also add
fail2ban. Finally, the monitor log showed that the `nologin` account still got a full `systemd --user` session (pipewire,
dbus). On a server I would stop that from happening, and I would run load tests on a staging clone with realistic traffic (k6/wrk) instead of on a production box.
