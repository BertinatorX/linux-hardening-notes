# Arch Linux Phase 3 Part 2: Defense-in-Depth Hardening

**Date:** 2026-06-08
**System:** AiStone X4SP4NAL (TongFang GX4), AMD Ryzen AI 9 HX 370 | Arch Linux | Kernel 7.0.11-arch1-1
**Hostname:** `Ancilla.localdomain`
**Author:** Alberto R. (BertinatorX)
**Predecessor session:** [arch-hardening-2026-06-07.md](./arch-hardening-2026-06-07.md) (Phase 3 Part 1, ended at Lynis 76/100)

---

## Goal

Part 1 got the baseline hardening back in place and ended at Lynis 76/100. This session was about adding layers on top of that minimum: mandatory access control, a sandbox for the BYOD work software, a real antivirus deployment instead of an installed-and-idle one, and some more accounting infrastructure. I kept the Lynis score as a measurement, but the actual objective was making the machine harder to compromise, even where that meant effort Lynis doesn't reward at all.

The same day also produced a [forensic case study on the Insightful (Workpuls) workforce-analytics agent](./insightful-agent-forensic-review-2026-06-08.md), which I link again at the bottom.

---

## What Got Done

### 1. Insightful sandbox (firejail)

Mercor gig work requires running the Insightful agent. I wasn't going to give it free run of the laptop, so I sandboxed it under firejail before reinstalling it.

The profile lives at `~/.config/firejail/insightful.profile`. The directives that matter:

- `whitelist ${HOME}/Documents/Work`, the only personal-side path the agent can reach
- `whitelist ${HOME}/.config/workpuls-agent`, `~/.cache/workpuls-agent`, `~/.local/share/AppImage/Workpuls.AppImage`, the agent's own paths and nothing else
- `include whitelist-common.inc`, fonts, locale and theme dirs so the GUI renders
- `caps.drop all`, `noroot`, `nonewprivs`, `disable-mnt`
- `netfilter`, `seccomp`, `protocol unix,inet,inet6`
- `ignore nodbus` plus `dbus-user filter` with `talk` permission for `org.freedesktop.{Notifications, portal.Desktop, portal.Documents, portal.OpenURI, secrets}`, because Electron needs DBus to render

The wrapper script at `~/.local/bin/insightful` combines firejail, the profile, the AppImage and the Electron `--no-sandbox` flag. The flag is required because Chromium's setuid-sandbox doesn't work inside firejail's confinement.

The desktop launcher at `~/.local/share/applications/insightful.desktop` makes the menu entry go through the sandbox every time, the bare AppImage path is never reached from a menu.

To verify, I read from inside the running sandbox with `firejail --join=NAME`:

```
$ firejail --join=NAME ls /home/MBias
Documents

$ firejail --join=NAME ls /home/MBias/.ssh
ls: cannot access '/home/MBias/.ssh': No such file or directory

$ firejail --join=NAME ls /home/MBias/Projects
ls: cannot access '/home/MBias/Projects': No such file or directory

$ firejail --join=NAME ls /home/MBias/.config/Brave-Browser
ls: cannot access '/home/MBias/.config/Brave-Browser': No such file or directory

$ firejail --join=NAME cat /home/MBias/Projects/linux-hardening-notes/README.md
cat: /home/MBias/Projects/linux-hardening-notes/README.md: No such file or directory
```

From Insightful's side, my SSH keys, this hardening-notes repo, the browser cookies and the whole Projects directory don't exist on the filesystem. The Mercor sign-in still works because outbound traffic to `app.insightful.io` is allowed.

To be clear about what this buys: firejail can't stop Insightful from capturing what it was contracted to capture (active app focus, time, optionally screenshots). What it does is contain the supply-chain blast radius if Insightful's binary or servers get compromised. I think that's the realistic BYOD posture.

---

### 2. AppArmor activation

Part 1 left the AppArmor kernel module loaded, but the AppArmor securityfs wasn't mounted and zero policies were active. Fixing that came down to the kernel cmdline parameters.

The boot-loader gotcha cost me time. On this install the ESP is mounted at `/boot/efi`, not `/boot`, so systemd-boot reads its loader entries from `/boot/efi/loader/entries/arch.conf` and not from `/boot/loader/entries/arch.conf`. I had edited the second path earlier and nothing changed, because the bootloader never reads that file. `sudo bootctl status` tells you which path is the active source, and once I confirmed that, I edited the right file.

Final kernel cmdline:

```
root=/dev/nvme0n1p2 rootfstype=btrfs rw \
  lsm=landlock,lockdown,yama,integrity,apparmor,bpf \
  audit=1 \
  apparmor=1
```

After the reboot, `aa-status` reported:

```
apparmor module is loaded.
178 profiles are loaded.
95 profiles are in enforce mode.
```

Some of the enforced profiles: `firejail-default`, `brave`, `chrome`, `firefox`, `msedge`, `torbrowser_firefox`, `docker-default`, `cursor_sandbox`, plus the Dovecot, Apache, libvirt and avahi-daemon profiles. The Arch `apparmor` package ships with the community profile library and a lot of it auto-activates on packages it knows about.

The honest caveat: Lynis's MACF-6208 (the AppArmor presence test) gives this the maximum 3 points, and partial credit was already there yesterday just from the module being loaded. So the gain from full activation is smaller in Lynis points than in real security. Plenty of user-space processes (Hyprland, kitty, swww-daemon, Spotify, etc.) still run unconfined because no profile matches their binaries. Writing custom profiles for those is a future session's work.

---

### 3. ClamAV turned on properly

ClamAV (`clamscan`/`clamdscan`/`freshclam`) was installed but completely inert: the `clamav-freshclam` and `clamav-daemon` services were both disabled, no signatures had been refreshed this session, and no scheduled scan existed.

I refreshed signatures with `sudo freshclam`. The daily database went from version 28024 to 28025, totals: 3,287,027 main signatures + 355,457 daily + 80 bytecode.

Then I enabled both daemons:

```
sudo systemctl enable --now clamav-freshclam.service
sudo systemctl enable --now clamav-daemon.service
```

The clamd daemon loads ~3.6M signatures into RAM (peak ~1.9 GB during the initial load, settled around 1 GB resident).

For an end-to-end check I used the EICAR standard test signature, and that's where I found out that umask 027 (set in Phase 3 Part 1) stops the `clamav` user from opening user-owned files:

```
$ clamdscan /tmp/clamav-test/eicar.txt
/tmp/clamav-test/eicar.txt: File path check failure: Permission denied. ERROR
Infected files: 0
Total errors: 2

$ clamdscan --fdpass /tmp/clamav-test/eicar.txt
/tmp/clamav-test/eicar.txt: Eicar-Signature FOUND
Infected files: 1
Time: 0.005 sec
```

The `--fdpass` flag passes an open file descriptor through the Unix socket instead of relying on path-based access. Every scheduled scan has to use this flag, because clamd runs as the `clamav` user and umask 027 leaves files unreadable to "other."

To keep the scheduled scans manageable I added exclusions to `/etc/clamav/clamd.conf`:

| Pattern | Reason |
|---|---|
| `^/proc/`, `^/sys/`, `^/dev/`, `^/run/` | Virtual filesystems |
| `^/var/lib/clamav/` | ClamAV's own signature database |
| `^/\.snapshots/` | Btrfs/snapper snapshots; scan the live filesystem, not history |
| `^/var/cache/`, `^/var/log/` | Generated/log data |
| `^/var/lib/docker/`, `^/var/lib/containerd/`, `^/var/lib/libvirt/` | Container/VM data; scanned from inside if needed |
| `/\.cache/` | Browser/Electron caches |
| `/\.local/share/Trash/` | Trash |
| `/\.local/share/AppImage/` | AppImages are squashfs containers; firejail wraps them at execution time |
| `/\.config/workpuls-agent/` | Sandbox data, firejail's domain |
| `\.iso$`, `\.qcow2$`, `\.img$`, `\.vmdk$`, `\.ova$` | VM/installer images |
| `\.gz$`, `\.xz$`, `\.zst$` | Compressed archives (scanned at write-time elsewhere) |
| `\.cvd$`, `\.cld$` | ClamAV signature files |

Then I reloaded clamd with `sudo systemctl reload clamav-daemon`; `ExecReload` sends SIGUSR2 to the PID and the daemon re-reads its config without unloading signatures.

The scheduled scan is a systemd timer at `/etc/systemd/system/clamav-scheduled-scan.timer`:

```
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
RandomizedDelaySec=30min
```

The backing service at `/etc/systemd/system/clamav-scheduled-scan.service` runs `/usr/local/bin/clamav-scheduled-scan.sh`, which scans `/home /etc /usr/local/bin /tmp /opt` with `--fdpass --multiscan --infected`, logs to `/var/log/clamav/scheduled-scan-YYYY-MM-DD.log`, and uses `notify-send` to alert the desktop session if anything turns up. `Nice=10` + `IOSchedulingClass=idle` keep the scan from getting in the way of interactive work.

Honest scope here: on a personal Linux laptop, ClamAV is mostly good for checking files that came from Windows sources and for satisfying compliance/audit requirements. Its Linux malware coverage is thinner than the commercial AV vendors, and signature-based detection misses modern threats that need behavioral analysis to catch. It's a real tool but not the main defensive layer; that job belongs to AppArmor + firejail + sysctl hardening + UFW.

---

### 4. Process accounting via auditd

The GNU `acct` AUR package wouldn't build on the current gcc toolchain (incompatible-pointer-types error in `sa.c`, old C code passing `int (*)()` where `qsort` expects `__compar_fn_t`, and modern gcc treats that as an error instead of a warning). I didn't want to patch unmaintained upstream code, so I got the same data by adding an audit rule to the auditd configuration that was already in place.

Appended to `/etc/audit/rules.d/99-hardening.rules`:

```
## ---- Command execution logging (replaces GNU acct) ----
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k exec
```

After `sudo auditctl -D && sudo augenrules --load`, every command run by a user with UID ≥ 1000 gets logged. Verified with a deliberate test:

```
$ ls /tmp >/dev/null
$ sudo ausearch -k exec -ts recent | tail -20
type=EXECVE msg=audit(...): argc=2 a0="tail" a1="-20"
type=SYSCALL ... syscall=59 success=yes ... auid=1000 uid=1000 ... comm="tail" exe="/usr/bin/tail" subj=unconfined key="exec"
```

That's the same information `acct`'s `lastcomm` tool gives, queried through `ausearch -k exec` instead. The tradeoff is that auditd's output is more verbose, lastcomm's is more compact for a casual look. For forensic use, more detail is better.

The lesson from the acct build failure: AUR packages that haven't kept up with current toolchains fail in ways that aren't obvious. Before committing to an unmaintained package, check the build status on the AUR page or do a test build first. Equivalent infrastructure you already have (auditd in this case) is usually a better answer than fighting old code.

---

### 5. sysstat history

I turned on three sysstat systemd timers:

```
sudo systemctl enable --now sysstat-collect.timer sysstat-rotate.timer sysstat-summary.timer
```

Arch's sysstat package uses three separate timers instead of the single `sysstat.timer` unit some distros ship:

| Timer | Cadence | Purpose |
|---|---|---|
| `sysstat-collect.timer` | every 10 min | Calls `sa1` to write activity samples to `/var/log/sa/` |
| `sysstat-rotate.timer` | daily | Compresses/rotates the daily files |
| `sysstat-summary.timer` | daily | Generates the human-readable daily summary report |

The history is now reachable with `sar -u 1 5` (CPU, last 5 samples), `sar -r` (memory history), and so on. This closes Lynis ACCT-9626.

---

### 6. clang restricted too

Phase 3 Part 1 restricted gcc/g++ to a `compilers` group (mode 750, owner `root:compilers`, MBias added to the group). This time the clang toolchain got the same treatment:

```
sudo chown root:compilers /usr/bin/clang-22 /usr/bin/clang++ /usr/bin/clang-cl /usr/bin/clang-cpp
sudo chmod 750 /usr/bin/clang-22 /usr/bin/clang++ /usr/bin/clang-cl /usr/bin/clang-cpp
```

I left the other clang tools alone on purpose (`clang-format`, `clang-tidy`, `clangd`, `clang-refactor`, etc.). They're developer convenience tools, not compilers, and an account that's already compromised and exfiltrating data doesn't gain much more from having `clang-format`.

---

### 7. FQDN hostname (NAME-4404)

Lynis NAME-4404 flagged that `hostname --fqdn` returned just `Ancilla` instead of `Ancilla.localdomain`, because the static hostname had no domain component. Fixed with:

```
sudo hostnamectl set-hostname Ancilla.localdomain
```

`/etc/hosts` already had the alias entry from yesterday: `127.0.1.1   Ancilla.localdomain Ancilla`. That closes the suggestion. One thing I found along the way: the legacy `hostname` CLI isn't installed on Arch by default, the `inetutils` package supplies it, and `hostnamectl` is the modern way anyway.

---

## Lynis Scores

| Run | Hardening Index | Tests | Suggestions | Warnings | Notes |
|---|---|---|---|---|---|
| 2026-05-30 (previous baseline) | 69 | ~245 | ~33 | 1 | Original pre-reinstall hardening |
| 2026-06-07 start (after restore) | 69 | 249 | 33 | 1 | Phase 3 Part 1 start |
| 2026-06-07 mid | 73 | 250 | 20 | 1 | After sysctl + UFW + auditd + CVE pruning |
| 2026-06-07 end | 76 | 250 | ~18 | 1 | After password policy + compilers + core dumps + pwquality |
| 2026-06-08 mid | 76 | 251 | ~18 | 1 | After AppArmor full activation + boot cmdline edit |
| 2026-06-08 end | 77 | 252 | ~17 | 1 | After ClamAV proper + sysstat + execve audit + FQDN |

Net session gain: +1 Lynis point. Net two-day gain from the start of session 1: +8 points (69 → 77).

The score undersells the actual security improvement, for a few reasons:

- AppArmor already had maximum credit on MACF-6208 yesterday (partial credit is given even when no profiles are enforced). Today's 95-enforced-profiles state earned the same Lynis points but is a very different kernel-level security posture.
- Nothing in Lynis tests for firejail-based BYOD isolation.
- Process accounting through auditd's execve rule isn't detected by Lynis's ACCT-9622 test, which looks specifically for `accton`/`psacct`.
- ClamAV went from "installed but inert" to "fully autonomous with scheduled scans" and gets the same `[V]` mark in Lynis either way.

If I were chasing the score, this session would have gone to installing `aide` (closes the Intrusion software `[X]`, +2-3 Lynis points). I decided real defensive layers came first. AIDE is reserved for Phase 3 Part 3.

---

## Still Open

### In the Lynis output

| ID | Item | Plan |
|---|---|---|
| FINT-4350 | File integrity tool (aide) | Phase 3 Part 3, dedicated session |
| HRDN-7222 | Some compilers still accessible (clang-format etc., though they're not real compilers) | Investigate whether lynis can be told to accept this |
| KRNL-6000 | `kernel.modules_disabled` not set to 1 | Deferred on purpose, it breaks USB/VM/libvirt workflows |
| BOOT-5264 | Per-service systemd hardening | Big effort, low ROI before AppArmor profile authoring |
| FILE-7524 | Specific file permissions | Investigate which files are flagged |
| FILE-6310 | Separate /home, /var partitions | Won't repartition existing single drive |
| LOGG-2154 | Remote syslog | No syslog server to send to |
| TOOL-5002 | Config management | Single laptop, not worth Ansible |

### Beyond Lynis

- Browser AppArmor profile binding. The Brave, Chrome, Firefox and Edge profiles are loaded, but the running browser binaries show as `unconfined` in `aa-status`. The profile attachment paths likely don't match where the binaries actually live on this Arch install. Probably ~10 min per browser to investigate.
- Custom AppArmor profiles for the unconfined long-running processes. Hyprland, kitty, swww-daemon, Spotify, etc. all run unconfined. Minimal profiles for the most exposed of them would be a real gain.
- Secure Boot with self-enrolled keys plus a signed kernel/initrd, for a boot integrity guarantee. This touches the bootloader stack I worked on today, so I'll do it when I'm comfortable with the edit-test-recover loop.
- TPM2-backed LUKS auto-unlock. This needs the disk re-encrypted first (the current install is not encrypted; the fresh install in early June was non-encrypted Btrfs). Backup/wipe/reinstall project for a quiet weekend.

---

## Lessons

1. The ESP mount point matters. When the EFI System Partition is mounted at `/boot/efi` instead of `/boot`, systemd-boot does not read the files in `/boot/loader/entries/`. Confirm with `sudo bootctl status` which file is the actual source before editing anything.

2. `/etc` lives on the root filesystem, not in the dotfiles. A fresh install wipes every system-level config you ever wrote unless you have an explicit backup or a config-management tool. User dotfiles don't cover `/etc/sysctl.d/`, `/etc/audit/rules.d/`, PAM configs, or boot loader entries. Plan for it ahead of time.

3. AUR packages can be unmaintained. GNU `acct` wouldn't compile on current gcc because upstream never caught up with modern C pointer-type strictness. Don't fight unmaintained packages, find the same functionality in tools you already have (here, auditd's execve rule).

4. umask 027 has consequences for daemons. Anything running under its own UID (clamav, etc.) can't read your files once you're on umask 027. The tool has to run as root, use file-descriptor passing (`--fdpass`), or stick to standard system paths.

5. Lynis is a measurement, not a goal. The score doesn't see firejail isolation, custom audit rules, AppArmor coverage beyond presence, or the difference between properly configured and installed-but-inert software. Building the actual defensive stack is what matters, the score is a useful but imperfect proxy.

6. Electron plus sandboxes is a learning curve. Chromium's built-in setuid-sandbox doesn't work with firejail's mount-namespace approach, and the fix is `--no-sandbox` on the Electron command line. That sounds bad but it's correct when the outer sandbox gives better isolation than Electron's inner one would.

7. Defense in depth means accepting that no single layer is enough. ClamAV scans signatures, AppArmor enforces profiles, auditd logs, firejail isolates, UFW filters, sysctl restricts. None of them alone is enough. Together they make a compromise harder and slower to pull off, and noisier while it's happening.

---

## Files Changed

System-level:
- `/boot/efi/loader/entries/arch.conf`: appended `lsm=...`, `audit=1`, `apparmor=1`
- `/etc/audit/rules.d/99-hardening.rules`: appended the execve logging rule
- `/etc/clamav/clamd.conf`: appended 25 `ExcludePath` directives
- `/usr/local/bin/clamav-scheduled-scan.sh`: new (weekly scan script)
- `/etc/systemd/system/clamav-scheduled-scan.service`: new
- `/etc/systemd/system/clamav-scheduled-scan.timer`: new
- `/usr/bin/clang-22`, `clang++`, `clang-cl`, `clang-cpp`: chown root:compilers, chmod 750

User-level:
- `~/.config/firejail/insightful.profile`: new
- `~/.local/bin/insightful`: new (sandbox wrapper)
- `~/.local/share/applications/insightful.desktop`: new
- `~/.local/share/AppImage/Workpuls.AppImage`: re-installed
- `~/Documents/Work/`: new directory (Insightful's only writable home subpath)

Services enabled and started this session:
- `apparmor.service`
- `clamav-freshclam.service`
- `clamav-daemon.service`
- `clamav-scheduled-scan.timer`
- `sysstat-collect.timer`, `sysstat-rotate.timer`, `sysstat-summary.timer`

---

## Cross-References

- Previous session: [arch-hardening-2026-06-07.md](./arch-hardening-2026-06-07.md)
- Forensic case study on Insightful: [insightful-agent-forensic-review-2026-06-08.md](./insightful-agent-forensic-review-2026-06-08.md)
- Related notes: [firewall-basics.md](../notes/firewall-basics.md), [post-install-checklist.md](../notes/post-install-checklist.md)
- Tooling: [bash-admin-scripts/scripts/security-check.sh](https://github.com/BertinatorX/bash-admin-scripts/blob/main/scripts/security-check.sh), re-run weekly for drift detection

Session length: ~5 hours (across morning + early afternoon)

Result: Lynis 76 → 77 (+1). AppArmor 0 → 95 profiles enforced. ClamAV inert → autonomous. Insightful unsandboxed → fully isolated. Eight new defensive layers added across 11 system files + 4 user files. Two new processes (clamd, clamav-freshclam) now memory-resident, total ~1 GB resident RAM for security tooling.
