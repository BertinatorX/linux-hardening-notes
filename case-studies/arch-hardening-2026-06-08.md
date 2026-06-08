# Arch Linux Phase 3 Part 2 — Defense-in-Depth Hardening

**Date:** 2026-06-08
**System:** AiStone X4SP4NAL (TongFang GX4) — AMD Ryzen AI 9 HX 370 | Arch Linux | Kernel 7.0.11-arch1-1
**Hostname:** `Ancilla.localdomain`
**Author:** Alberto R. (BertinatorX)
**Predecessor session:** [arch-hardening-2026-06-07.md](./arch-hardening-2026-06-07.md) (Phase 3 Part 1, ended at Lynis 76/100)

---

## Context and Goal

After Phase 3 Part 1 restored the baseline hardening posture and reached Lynis 76/100, this session aimed to add **layered defenses** beyond the minimum: mandatory access control, a sandbox for BYOD work software, a real antivirus deployment, and additional accounting infrastructure. The Lynis score was a measurement target, but the real objective was to make the system materially harder to compromise — even at the cost of effort that lynis does not directly reward.

This session also produced a [forensic case study on the Insightful (Workpuls) workforce-analytics agent](./insightful-agent-forensic-review-2026-06-08.md) which is referenced below where relevant.

---

## What Was Accomplished

### 1. Insightful BYOD Sandbox (firejail)

Mercor gig work requires running the Insightful agent. Rather than grant it unconstrained access to the laptop, it was sandboxed under firejail before being re-installed.

**Profile location:** `~/.config/firejail/insightful.profile`

Key directives:
- `whitelist ${HOME}/Documents/Work` — the only personal-side path the agent can reach
- `whitelist ${HOME}/.config/workpuls-agent`, `~/.cache/workpuls-agent`, `~/.local/share/AppImage/Workpuls.AppImage` — agent-owned paths only
- `include whitelist-common.inc` — fonts, locale, theme dirs so GUI renders
- `caps.drop all`, `noroot`, `nonewprivs`, `disable-mnt`
- `netfilter`, `seccomp`, `protocol unix,inet,inet6`
- `ignore nodbus` + `dbus-user filter` with `talk` permission for `org.freedesktop.{Notifications, portal.Desktop, portal.Documents, portal.OpenURI, secrets}` — Electron needs DBus to render

**Wrapper script** at `~/.local/bin/insightful` combines firejail + profile + AppImage + the Electron `--no-sandbox` flag (required because Chromium's setuid-sandbox is incompatible with firejail's confinement).

**Desktop launcher** at `~/.local/share/applications/insightful.desktop` makes the menu entry always invoke the sandbox; the bare AppImage path is never reached from menus.

**Verification** (read from inside the running sandbox via `firejail --join=NAME`):

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

From Insightful's perspective, the user's SSH keys, hardening-notes repo, browser cookies, and Projects directory **do not exist on the filesystem**. The Mercor sign-in still works because outbound traffic to `app.insightful.io` is allowed.

**Honest scope:** firejail cannot prevent Insightful from capturing what it was contracted to capture (active app focus, time, optionally screenshots). It contains the **supply-chain blast radius** if Insightful's binary or servers are compromised. That's the realistic BYOD posture.

---

### 2. AppArmor Activation (Mandatory Access Control)

Phase 3 Part 1 had the AppArmor kernel module loaded but the AppArmor securityfs was not mounted and zero policies were active. This session resolved that by adding the kernel cmdline parameters.

**The boot-loader gotcha:** On this install, the ESP is mounted at `/boot/efi`, not `/boot`. systemd-boot reads loader entries from the ESP (`/boot/efi/loader/entries/arch.conf`), not from `/boot/loader/entries/arch.conf`. An earlier edit to the latter path had no effect because that file is not read by the bootloader. After confirming with `sudo bootctl status` which path is the active source, the correct file was edited.

Final kernel cmdline:

```
root=/dev/nvme0n1p2 rootfstype=btrfs rw \
  lsm=landlock,lockdown,yama,integrity,apparmor,bpf \
  audit=1 \
  apparmor=1
```

After reboot, `aa-status` reported:

```
apparmor module is loaded.
178 profiles are loaded.
95 profiles are in enforce mode.
```

Notable enforced profiles: `firejail-default`, `brave`, `chrome`, `firefox`, `msedge`, `torbrowser_firefox`, `docker-default`, `cursor_sandbox`, plus the Dovecot, Apache, libvirt, and avahi-daemon profiles. The Arch `apparmor` package ships with the community profile library and many auto-activate on packages it knows about.

**Honest scope:** Lynis's MACF-6208 (AppArmor presence test) credits this with the maximum 3 points; a partial credit was already in place yesterday because the module was loaded. The score gain from the full activation is therefore smaller in lynis-points than in real security. Many user-space processes (Hyprland, kitty, swww-daemon, Spotify, etc.) remain unconfined because no profile matches their binaries; writing custom profiles for these is a future session's work.

---

### 3. ClamAV Proper Activation

ClamAV (`clamscan`/`clamdscan`/`freshclam`) was installed but completely inert: the `clamav-freshclam` and `clamav-daemon` services were both disabled, no signatures had been refreshed in this session, and no scheduled scan existed.

**Refreshed signatures** with `sudo freshclam` — daily database advanced from version 28024 to 28025, totals: 3,287,027 main signatures + 355,457 daily + 80 bytecode.

**Enabled both daemons:**

```
sudo systemctl enable --now clamav-freshclam.service
sudo systemctl enable --now clamav-daemon.service
```

The clamd daemon loads ~3.6M signatures into RAM (peak ~1.9 GB during initial load, settled around 1 GB resident).

**End-to-end verification** with the EICAR standard test signature, after discovering that umask 027 (set in Phase 3 Part 1) prevents the `clamav` user from opening user-owned files:

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

The `--fdpass` flag passes an open file descriptor through the Unix socket instead of relying on path-based access. **All scheduled scans must use this flag** because clamd runs as the `clamav` user and umask 027 leaves files unreadable to "other."

**Exclusions** added to `/etc/clamav/clamd.conf` to make scheduled scans tractable:

| Pattern | Reason |
|---|---|
| `^/proc/`, `^/sys/`, `^/dev/`, `^/run/` | Virtual filesystems |
| `^/var/lib/clamav/` | ClamAV's own signature database |
| `^/\.snapshots/` | Btrfs/snapper snapshots — scan live filesystem, not history |
| `^/var/cache/`, `^/var/log/` | Generated/log data |
| `^/var/lib/docker/`, `^/var/lib/containerd/`, `^/var/lib/libvirt/` | Container/VM data; scanned from inside if needed |
| `/\.cache/` | Browser/Electron caches |
| `/\.local/share/Trash/` | Trash |
| `/\.local/share/AppImage/` | AppImages are squashfs containers; firejail wraps them at execution time |
| `/\.config/workpuls-agent/` | Sandbox data, firejail's domain |
| `\.iso$`, `\.qcow2$`, `\.img$`, `\.vmdk$`, `\.ova$` | VM/installer images |
| `\.gz$`, `\.xz$`, `\.zst$` | Compressed archives (scanned at write-time elsewhere) |
| `\.cvd$`, `\.cld$` | ClamAV signature files |

Reloaded clamd: `sudo systemctl reload clamav-daemon` — `ExecReload` sends SIGUSR2 to PID, daemon re-reads config without unloading signatures.

**Scheduled scan** via systemd timer at `/etc/systemd/system/clamav-scheduled-scan.timer`:

```
[Timer]
OnCalendar=Sun *-*-* 03:00:00
Persistent=true
RandomizedDelaySec=30min
```

Backing service at `/etc/systemd/system/clamav-scheduled-scan.service` runs `/usr/local/bin/clamav-scheduled-scan.sh` which scans `/home /etc /usr/local/bin /tmp /opt` with `--fdpass --multiscan --infected`, logs to `/var/log/clamav/scheduled-scan-YYYY-MM-DD.log`, and uses `notify-send` to alert the desktop session if anything is found. `Nice=10` + `IOSchedulingClass=idle` keep the scan from impacting interactive work.

**Honest scope:** ClamAV's primary value on a personal Linux laptop is checking files received from Windows sources and satisfying compliance/audit requirements. Linux malware coverage is thinner than commercial AV vendors, and signature-based detection misses modern threats that rely on behavioral analysis. It is a real tool but not the main defensive layer — that role is held by AppArmor + firejail + sysctl hardening + UFW.

---

### 4. Process Accounting via auditd execve Rule

The GNU `acct` AUR package failed to build on the current gcc toolchain (incompatible-pointer-types error in `sa.c` — old C code passing `int (*)()` where `qsort` expects `__compar_fn_t`; modern gcc treats this as an error rather than a warning). Rather than patch unmaintained upstream code, the same data was obtained by adding an audit rule to the existing auditd configuration:

Appended to `/etc/audit/rules.d/99-hardening.rules`:

```
## ---- Command execution logging (replaces GNU acct) ----
-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k exec
```

After `sudo auditctl -D && sudo augenrules --load`, every command execution by users with UID ≥ 1000 is logged. Verified with a deliberate test:

```
$ ls /tmp >/dev/null
$ sudo ausearch -k exec -ts recent | tail -20
type=EXECVE msg=audit(...): argc=2 a0="tail" a1="-20"
type=SYSCALL ... syscall=59 success=yes ... auid=1000 uid=1000 ... comm="tail" exe="/usr/bin/tail" subj=unconfined key="exec"
```

This gives equivalent information to `acct`'s `lastcomm` tool, queryable through `ausearch -k exec`. Tradeoff: auditd's output is more verbose; lastcomm's is more compact for casual review. For forensic use, more detail is better.

**The GNU acct compilation lesson:** AUR packages that haven't been updated for current toolchains will fail in non-obvious ways. Before committing to an unmaintained package, check the build status on the AUR page or test build first. Equivalent infrastructure (auditd in this case) is often a better answer than fighting unmaintained code.

---

### 5. sysstat (Historical System Activity)

Three sysstat systemd timers were activated:

```
sudo systemctl enable --now sysstat-collect.timer sysstat-rotate.timer sysstat-summary.timer
```

Arch's sysstat package uses three separate timers rather than the single `sysstat.timer` unit some distros provide:

| Timer | Cadence | Purpose |
|---|---|---|
| `sysstat-collect.timer` | every 10 min | Calls `sa1` to write activity samples to `/var/log/sa/` |
| `sysstat-rotate.timer` | daily | Compresses/rotates the daily files |
| `sysstat-summary.timer` | daily | Generates the human-readable daily summary report |

Now reachable via `sar -u 1 5` (CPU last 5 samples), `sar -r` (memory history), and so on. Closes Lynis ACCT-9626.

---

### 6. Compiler Restriction Extended to clang

Phase 3 Part 1 restricted gcc/g++ to a `compilers` group (mode 750, owner `root:compilers`, MBias added to the group). This session extended the same treatment to the clang toolchain:

```
sudo chown root:compilers /usr/bin/clang-22 /usr/bin/clang++ /usr/bin/clang-cl /usr/bin/clang-cpp
sudo chmod 750 /usr/bin/clang-22 /usr/bin/clang++ /usr/bin/clang-cl /usr/bin/clang-cpp
```

Auxiliary clang tools (`clang-format`, `clang-tidy`, `clangd`, `clang-refactor`, etc.) were intentionally left alone — they are developer ergonomic tools, not compilers, and a compromised account already exfiltrating data does not gain meaningfully more by using `clang-format`.

---

### 7. FQDN as Static Hostname (NAME-4404)

Per Lynis NAME-4404, `hostname --fqdn` was returning just `Ancilla` instead of `Ancilla.localdomain` because the static hostname did not include a domain component. Resolved with:

```
sudo hostnamectl set-hostname Ancilla.localdomain
```

`/etc/hosts` already had the alias entry from yesterday: `127.0.1.1   Ancilla.localdomain Ancilla`. Closes the suggestion. **Discovery:** The legacy `hostname` CLI is not installed on Arch by default; the `inetutils` package supplies it, and modern usage prefers `hostnamectl`.

---

## Lynis Score Progression

| Run | Hardening Index | Tests | Suggestions | Warnings | Notes |
|---|---|---|---|---|---|
| 2026-05-30 (previous baseline) | 69 | ~245 | ~33 | 1 | Original pre-reinstall hardening |
| 2026-06-07 start (after restore) | 69 | 249 | 33 | 1 | Phase 3 Part 1 start |
| 2026-06-07 mid | 73 | 250 | 20 | 1 | After sysctl + UFW + auditd + CVE pruning |
| 2026-06-07 end | 76 | 250 | ~18 | 1 | After password policy + compilers + core dumps + pwquality |
| 2026-06-08 mid | 76 | 251 | ~18 | 1 | After AppArmor full activation + boot cmdline edit |
| **2026-06-08 end** | **77** | **252** | ~17 | 1 | After ClamAV proper + sysstat + execve audit + FQDN |

**Net session gain: +1 lynis point. Net two-day gain from session 1 start: +8 points (69 → 77).**

The score gain underrepresents the actual security improvement, for several reasons:

- AppArmor was already at maximum credit for the MACF-6208 test yesterday (partial credit was given even when no profiles were enforced). Today's 95-enforced-profiles state earned the same lynis points but represents a vastly different kernel-level security posture.
- firejail-based BYOD isolation has no lynis test that captures it.
- Process accounting via auditd's execve rule is not detected by lynis's ACCT-9622 test (which looks specifically for `accton`/`psacct`).
- ClamAV moved from "installed but inert" to "fully autonomous with scheduled scans" — same `[V]` mark in lynis.

A score-focused approach would have spent this session installing `aide` (closes Intrusion software `[X]`, +2-3 lynis points). The decision was made to prioritize real defensive layers over score optimization. AIDE is reserved for Phase 3 Part 3.

---

## What's Still Open

### Listed in Lynis output

| ID | Item | Plan |
|---|---|---|
| FINT-4350 | File integrity tool (aide) | Phase 3 Part 3, dedicated session |
| HRDN-7222 | Some compilers still accessible (clang-format etc., though they're not real compilers) | Investigate whether lynis can be told to accept this |
| KRNL-6000 | `kernel.modules_disabled` not set to 1 | Conscious deferral — breaks USB/VM/libvirt workflows |
| BOOT-5264 | Per-service systemd hardening | Big effort, low ROI before AppArmor profile authoring |
| FILE-7524 | Specific file permissions | Investigate which files are flagged |
| FILE-6310 | Separate /home, /var partitions | Won't repartition existing single drive |
| LOGG-2154 | Remote syslog | No syslog server to send to |
| TOOL-5002 | Config management | Single laptop, not worth Ansible |

### Beyond lynis

- **Browser AppArmor profile binding** — Brave, Chrome, Firefox, Edge profiles are loaded but the running browser binaries show as `unconfined` in `aa-status`. The profile attachment paths likely don't match where the actual binaries live on this Arch install. Investigating per-browser is ~10 min each.
- **Custom AppArmor profiles for unconfined long-running processes** — Hyprland, kitty, swww-daemon, Spotify, etc. all run unconfined. Writing minimal profiles for the most-exposed processes would be a real gain.
- **Secure Boot with self-enrolled keys + signed kernel/initrd** — boot integrity guarantee. Touches the bootloader stack we worked on today; do this when comfortable with the edit-test-recover loop.
- **TPM2-backed LUKS auto-unlock** — requires re-encrypting the disk first (current install is not encrypted; the fresh install in early June was non-encrypted Btrfs). Backup/wipe/reinstall project for a quiet weekend.

---

## Lessons Learned (Generalizable)

1. **ESP mount point matters.** When the EFI System Partition is mounted at `/boot/efi` rather than `/boot`, files in `/boot/loader/entries/` are NOT read by systemd-boot. Always confirm with `sudo bootctl status` which file is the *actual* source before editing.

2. **`/etc` lives on the root filesystem, not the dotfiles.** A fresh install wipes every system-level config you ever wrote unless you have an explicit backup or a config-management tool. User dotfiles do not include `/etc/sysctl.d/`, `/etc/audit/rules.d/`, PAM configs, or boot loader entries. Plan for this in advance.

3. **AUR packages can be unmaintained.** GNU `acct` failed to compile on current gcc because the upstream source hasn't been updated for modern C-pointer-type-strictness. Don't fight unmaintained packages — find equivalent functionality in tools you already have (in this case, auditd's execve rule).

4. **umask 027 has consequences for daemon-based services.** Daemons running under their own UIDs (clamav, etc.) can't read your files when the user uses umask 027. Tools must either run as root, use file-descriptor passing (`--fdpass`), or rely on standard system paths.

5. **Lynis is a measurement, not a goal.** The score does not capture firejail isolation, custom audit rules, AppArmor profile coverage beyond presence, or the value of properly-configured-vs-installed-but-inert software. Building the actual defensive stack matters; the score is a useful but imperfect proxy.

6. **Electron + sandboxes is a learning curve.** Chromium's built-in setuid-sandbox is incompatible with firejail's mount-namespace approach; the fix is `--no-sandbox` on the Electron command line, which sounds bad but is correct when an outer sandbox is providing better isolation than Electron's inner one would.

7. **Defense in depth means accepting that no single layer is sufficient.** ClamAV signature-scans, AppArmor profile-enforces, auditd logs, firejail isolates, UFW filters, sysctl restricts. None alone is enough. Together they make compromise harder, slower, and noisier.

---

## Files Changed This Session

System-level:
- `/boot/efi/loader/entries/arch.conf` — appended `lsm=...`, `audit=1`, `apparmor=1`
- `/etc/audit/rules.d/99-hardening.rules` — appended execve logging rule
- `/etc/clamav/clamd.conf` — appended 25 `ExcludePath` directives
- `/usr/local/bin/clamav-scheduled-scan.sh` — new (weekly scan script)
- `/etc/systemd/system/clamav-scheduled-scan.service` — new
- `/etc/systemd/system/clamav-scheduled-scan.timer` — new
- `/usr/bin/clang-22`, `clang++`, `clang-cl`, `clang-cpp` — chown root:compilers, chmod 750

User-level:
- `~/.config/firejail/insightful.profile` — new
- `~/.local/bin/insightful` — new (sandbox wrapper)
- `~/.local/share/applications/insightful.desktop` — new
- `~/.local/share/AppImage/Workpuls.AppImage` — re-installed
- `~/Documents/Work/` — new directory (Insightful's only writable home subpath)

Services enabled+started this session:
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
- Tooling: [bash-admin-scripts/scripts/security-check.sh](https://github.com/BertinatorX/bash-admin-scripts/blob/main/scripts/security-check.sh) — re-run weekly for drift detection

**Session length:** ~5 hours (across morning + early afternoon)
**Result:** Lynis 76 → 77 (+1). AppArmor 0 → 95 profiles enforced. ClamAV inert → autonomous. Insightful unsandboxed → fully isolated. Eight new defensive layers added across 11 system files + 4 user files. Two new processes (clamd, clamav-freshclam) now memory-resident, total ~1 GB resident RAM for security tooling.
