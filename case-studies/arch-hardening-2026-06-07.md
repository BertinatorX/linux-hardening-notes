# Arch Linux Security Hardening Session — Fresh Install Recovery
**Date:** 2026-06-07
**System:** AiStone X4SP4NAL (TongFang GX4) — AMD Ryzen AI 9 HX 370 | Arch Linux | Kernel 7.0.9 → 7.0.11
**Desktop:** Hyprland (Wayland) on JaKooLit dotfiles
**Hostname:** `Ancilla.localdomain`
**Tools Used:** lynis, rkhunter, arch-audit, auditd, ufw, augenrules, pacman, snapper, libpwquality, sysctl

---

## Context

This was a recovery hardening session after a fresh Arch install. A previous hardening session on 2026-05-30 had achieved a Lynis Hardening Index of **69/100**, but all system-level changes (in `/etc/`) were wiped during the reinstall because they were not part of the user's dotfiles. User-level configs survived; system-level configs did not. This session restored the previous baseline and pushed past it.

This case study also serves as a teaching artifact: each decision is documented with **why** as well as **what**.

---

## Starting State Audit

Before making any changes, the existing system was audited to understand what survived the fresh install:

| Layer | Previous state (2026-05-30) | Current state at session start |
|---|---|---|
| UFW | Active, deny incoming, port 2222 allowed | Installed but inactive |
| Lynis | Installed, 69/100 | Not installed |
| rkhunter | Installed | Not installed |
| arch-audit | Installed | Not installed |
| auditd | Installed + enabled | Installed, disabled |
| Kernel sysctl hardening | `/etc/sysctl.d/99-hardening.conf` (20+ knobs) | Gone — only Hyprland's `50-cursor.conf` remained |
| SSH hardening | Port 2222, hardened config | Not installed (decided to keep this way) |

**Lesson:** System-level (`/etc/`) configuration changes are NOT covered by typical user-dotfile workflows. Document them separately and restore explicitly.

---

## Scope Decision — SSH Skipped Deliberately

In the previous session, SSH was hardened on port 2222 because Lynis recommended it. On reflection during this session, the user does not actually SSH into this laptop from other machines — it's a daily-driver workstation, not a server. The most secure configuration for an unused service is **not having it installed at all**. SSH server was therefore intentionally not installed, eliminating that attack surface entirely rather than hardening a service that wasn't needed.

**Lesson:** "Most secure" depends on use case. Removing unused services beats hardening them.

---

## Actions Taken

### 1. Security Tooling Installed

```bash
sudo pacman -S --needed lynis rkhunter arch-audit audit
sudo systemctl enable --now auditd
```

Lessons learned during install:
- `rkhunter` ships with `rwx------` (mode 700) permissions on its binary, requiring `sudo` for any invocation — deliberate Arch security choice
- The `which` command lies if the user lacks execute permission on a file; use `ls -la <path>` or `pacman -Ql <pkg>` to verify installation
- zsh caches binary lookups; `hash -r` clears the cache after installing new packages

### 2. CVE-Reduction Package Cleanup

Reviewed `arch-audit` output (20 vulnerable packages). Removed CVE-affected packages that were either unused or had safer alternatives:

| CVE'd Package | Severity | Replacement | Reason |
|---|---|---|---|
| `djvulibre` | **High** | (removed with okular) | DjVu support; pulled in by okular |
| `okular` | — | `zathura` + `zathura-pdf-mupdf` | Lighter PDF viewer; MuPDF backend is more secure than poppler |
| `jre8-openjdk` | — | (removed) | Unused Java 8 runtime |
| `jre8-openjdk-headless` | **High** | (removed) | Unused Java 8 runtime |
| `moodle-sync` | — | (removed) | Pulled in Java 8 stack; not used (Moodle accessible via browser) |
| `calibre` | — | (removed) | Unused ebook manager |
| `podofo` | Medium | (removed with calibre) | PDF library; pulled in by calibre |
| `audacity` | Low | `tenacity` | Same UI; tenacity is fork without telemetry |

Final command:
```bash
sudo pacman -Rsc calibre moodle-sync jre8-openjdk okular audacity
sudo pacman -S zathura zathura-pdf-mupdf tenacity
xdg-mime default org.pwmt.zathura.desktop application/pdf
```

The `-Rsc` flag cascaded the removal — 5 explicit targets removed 64 packages total once orphan dependencies were factored in. Net disk freed: ~507 MB. **Three High/Medium CVEs eliminated**, one Low CVE eliminated.

**Lesson:** Package removal is a security tool. CVEs you can't patch upstream, you can sometimes eliminate by removing the affected package.

### 3. Kernel Hardening Restored

Created `/etc/sysctl.d/99-hardening.conf` with settings carried forward from the 2026-05-30 case study:

```
# Disable TTY discipline autoloading (kernel exploit class)
dev.tty.ldisc_autoload = 0

# Filesystem protections
fs.protected_fifos = 2
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1
fs.suid_dumpable = 0

# Kernel info exposure restrictions
kernel.core_uses_pid = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.randomize_va_space = 2
kernel.sysrq = 0

# Restrict unprivileged eBPF (major kernel exploit vector)
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# Network hardening - IPv4
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_syncookies = 1
```

Applied with `sudo sysctl --system`. Verified each setting with `sysctl <key>`.

**Lesson:** Files in `/etc/sysctl.d/` are applied in alphabetical order. The `99-` prefix ensures user overrides win against system defaults (`50-default.conf`). Same pattern as Hyprland's `configs/` vs `UserConfigs/`.

### 4. UFW Firewall — Reactivated and Persistent

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw logging low
sudo ufw enable
sudo systemctl enable ufw
sudo systemctl start ufw
```

**Important debugging finding:** `ufw enable` activates rules in the kernel but does NOT reliably enable the systemd unit on Arch. Both `systemctl enable ufw` AND `systemctl start ufw` must be run explicitly after `ufw enable`, or the firewall will not survive reboot. Verified by checking `systemctl is-enabled ufw` and `systemctl is-active ufw` both returned `enabled / active`.

**Additional finding:** `linutil`'s "recommended UFW settings" had silently added rules for SSH (port 22, LIMIT), HTTP (80, ALLOW), and HTTPS (443, ALLOW) — none of which are appropriate for a workstation with no inbound services. These were removed with `sudo ufw delete <rule>` to restore a true deny-all-inbound posture.

**Lesson:** Never trust an auto-installer's "recommended settings" without auditing what they did. Always verify the actual rules with `ufw status verbose`.

### 5. Audit Daemon (auditd) Configured with Rules

Auditd was enabled but had zero rules loaded (Lynis ACCT-9630). Wrote a ruleset to `/etc/audit/rules.d/99-hardening.rules` covering:

- **Self-protection:** changes to `/etc/audit/`, `/var/log/audit/`, `libaudit.conf`
- **Identity tampering:** `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/sudoers`, `/etc/sudoers.d/`
- **Privilege escalation:** sudo log + `/etc/pam.d/`
- **Time manipulation:** `adjtimex`, `settimeofday`, `clock_settime` syscalls + `/etc/localtime`
- **Kernel module loading:** `init_module`, `finit_module`, `delete_module` syscalls + `/etc/modprobe.d/`
- **System startup:** `/etc/systemd/`, `/etc/ssh/sshd_config`
- **Network config:** `/etc/network/`, `/etc/hosts`, `/etc/resolv.conf`
- **Mount events:** `mount`, `umount2` syscalls

23 rules loaded via `sudo augenrules --load`.

**Smoke test:**
```bash
sudo touch /etc/passwd
sudo ausearch -k identity -ts recent
```
Returned a complete forensic record: SYSCALL event with `auid=1000 uid=0 exe="/usr/bin/touch" key="identity"`, plus PATH and CWD context. Forensics pipeline verified end-to-end.

Tested `time-change` rule the same way with `sudo date -s "$(date)"` and confirmed `TIME_INJOFFSET` event was captured.

**Lesson:** Auditd is silent without rules. The daemon will run forever and capture nothing if you forget this step. Always verify with a deliberate test that generates a known event.

### 6. Authentication Hardening

#### `/etc/login.defs` policy:

| Setting | Default | Changed to | Reasoning |
|---|---|---|---|
| `UMASK` | 022 | 027 | New files not readable by "other" users |
| `PASS_MAX_DAYS` | 99999 | 365 | Annual password change |
| `PASS_MIN_DAYS` | 0 | 1 | Prevent rapid re-cycling to defeat history |
| `PASS_WARN_AGE` | 7 | 14 | Earlier warning before expiry |
| `SHA_CRYPT_MIN_ROUNDS` | (unset) | 65536 | More CPU work to crack stolen hashes |
| `SHA_CRYPT_MAX_ROUNDS` | (unset) | 65536 | Cap matches min — no weak fallback |

These apply to **future** password changes. Applied to current account immediately with:
```bash
sudo chage -M 365 -m 1 -W 14 MBias
```

#### Password strength enforcement (`pam_pwquality.so`):

Installed `libpwquality` (Lynis AUTH-9262). Wired `pam_pwquality.so` into `/etc/pam.d/system-auth` BEFORE `pam_unix.so` in the password stack. Tuned `/etc/security/pwquality.conf` with modern policy (NIST SP 800-63B aligned):

```
minlen = 12
minclass = 3
maxrepeat = 3
maxsequence = 3
dcredit = 0
ucredit = 0
ocredit = 0
lcredit = 0
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforce_for_root = 0
```

Tested by running `passwd` and providing a deliberately weak input (`aaa`). PAM rejected: *"BAD PASSWORD: The password is shorter than 12 characters"*. Aborted by sending invalid input until passwd exited (passwd ignores SIGINT/Ctrl+C by design).

**Lesson and recovery story:** First attempt to edit `/etc/pam.d/system-auth` with vim's `/search` placed the cursor in the wrong section (account, not password), corrupting the account stack. Restored from `/etc/pam.d/system-auth.bak` and re-did the edit with `sed -i` using a full-line anchor — explicit, idempotent, no cursor surprises. **For auth-critical edits, sed beats vim because the command itself documents what was changed and either matches exactly or fails loudly.**

### 7. Hostname / FQDN Configuration

Lynis NAME-4404 wanted the system's FQDN to resolve cleanly. Set static hostname:
```bash
sudo hostnamectl set-hostname Ancilla.localdomain
```

Added to `/etc/hosts`:
```
127.0.1.1   Ancilla.localdomain Ancilla
```

**Discovery:** The legacy `hostname` CLI is NOT installed by default on modern Arch — `hostnamectl` from systemd is the supported tool. `hostname --fqdn` requires the `inetutils` package; not worth installing for a personal laptop.

### 8. Legal Banner

Wrote `/etc/issue` with an "Authorized Access Only" banner. Also copied to `/etc/issue.net` for network-login contexts. (Lynis BANN-7126.)

### 9. Core Dumps Disabled

Appended to `/etc/security/limits.conf`:
```
* hard core 0
* soft core 0
```

Combined with existing `fs.suid_dumpable = 0` sysctl, core dumps are now disabled for all users. (Lynis KRNL-5820.) Core dumps can contain passwords and secrets from crashed-process memory; rarely useful on a desktop.

### 10. Compiler Restriction (Best-of-Both Approach)

Lynis HRDN-7222 wanted compilers restricted to root only. Pure restriction would break `yay` AUR builds, which invoke `gcc` as the user. Compromise:

```bash
sudo groupadd compilers
sudo chown root:compilers /usr/bin/gcc /usr/bin/g++
sudo chmod 750 /usr/bin/gcc /usr/bin/g++
sudo gpasswd -a MBias compilers
```

Result: compilers no longer world-executable (satisfies Lynis), but the user remains in the `compilers` group so `yay` still works. Group membership only activates in new login sessions; verified with `newgrp compilers` then `gcc --version`.

**Note:** `clang` was also installed but not included in this restriction. To be addressed in next session.

### 11. Unused Network Protocols Blacklisted

Lynis NETW-3200 flagged four exotic IP protocols. Created `/etc/modprobe.d/blacklist-rare-net.conf`:

```
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
```

`install <module> /bin/true` is the standard idiom for "if anything asks for this module, do nothing successfully." Modules never load → zero attack surface from those code paths.

---

## Conscious Deferrals (Decisions, Not Misses)

### KRNL-6000 — `kernel.modules_disabled = 1`

This sysctl is a trapdoor: once set to 1, the kernel refuses to load any new modules until reboot. **Anti-rootkit win**, but it breaks:
- USB drives with filesystems whose modules aren't pre-loaded (e.g., rare NTFS variants)
- VMs / libvirt / Docker that may load modules dynamically
- New hardware that needs an unloaded driver

For a personal laptop with active VM and USB use, **the productivity cost outweighs the 1-Lynis-point gain**. Documented as conscious deferral, not oversight.

### FINT-4350 — File Integrity Monitoring (`aide`)

A 45-60 minute setup on its own. Worth a dedicated session. Deferred to Phase 3 part 2.

### Other Skips (justified)

| Suggestion | Why skipped |
|---|---|
| FILE-6310 (×2) — separate `/home`, `/var` partitions | Would require disk re-layout; not worth it on single-drive laptop |
| LOGG-2154 — remote syslog | No syslog server to send to |
| TIME-3104 — NTP daemon | systemd-timesyncd is already the NTP client (false positive) |
| BOOT-5264 — systemd service hardening | Per-service tuning, low ROI before AppArmor |
| TOOL-5002 — config management | Ansible/Puppet for a single laptop = overkill |
| CRYP-7902 — certificate expiration | No custom certs to track |
| USB-1000, STRG-1846 — disable USB storage | User actively uses USB storage |

---

## Lynis Score Progression

| Run | Hardening Index | Suggestions | Warnings |
|---|---|---|---|
| Start of session (after baseline restored) | 69 / 100 | 33 | 1 (PKGS-7322) |
| After auditd + UFW + sysctl + package cleanup | 73 / 100 | 20 | 1 |
| After auth + core dumps + compilers + hostname + pwquality | **76 / 100** | ~18 | 1 |

**Net session gain: +7 points (69 → 76)**

The remaining warning is `PKGS-7322` (Vulnerable packages) — 17 upstream-blocked CVEs in core packages (grub, libxml2, pam, coreutils, openssl, systemd, perl, etc.) for which no patched build is yet published by Arch. Monitored at https://security.archlinux.org/. Same situation documented in 2026-05-30 case study.

---

## Verification Steps

Each change was verified live:

- `sysctl <key>` confirmed each kernel parameter took effect
- `sudo ufw status verbose` + `systemctl is-enabled ufw` + `systemctl is-active ufw` confirmed firewall is persistent
- `sudo auditctl -l` confirmed 23 rules loaded
- `sudo ausearch -k identity -ts recent` confirmed events captured end-to-end
- `passwd` with weak input confirmed pwquality enforces 12-char minimum
- `arch-audit` confirmed 3 High-severity CVEs eliminated
- `hostnamectl` confirmed FQDN persisted
- `grep` against `/etc/login.defs` confirmed all 6 settings landed correctly
- Snapper pre/post snapshots bracket every pacman operation (rollback available)

---

## Lessons Learned (Generalizable)

1. **Audit before action.** Restoring the previous baseline assumed nothing — we verified what survived the reinstall before making changes. Saved time and prevented duplicate work.

2. **Conscious deferrals are professional.** Skipping `kernel.modules_disabled` for a 1-point gain because it would break daily workflow is the same skill as deciding what tickets to defer at a real job. Document the reasoning.

3. **`sed -i` beats vim for surgical config edits.** Especially for auth-critical files where one wrong line breaks login. The sed command itself is documentation.

4. **Auto-installers lie.** `linutil`'s "recommended UFW settings" had silently allowed SSH/HTTP/HTTPS inbound. Always audit what convenience tools did.

5. **A warning that doesn't break behavior is logging, not a problem.** The `[WARN] We failed to find wayland buffer with id: X. This should be impossible.` messages from awww-daemon are scary-sounding noise; ignored once understood. Same with auditd's "Old style watch rules are slower" — informational, not failure.

6. **Cache layers fool the unaware.** zsh caches binary paths (`hash -r` to refresh); Lynis caches its last result file (re-run to get fresh data); `which` lies if you lack execute permission. Know your cache layers.

7. **Reboot is the real persistence test.** Many changes apply at boot via systemd, sysctl-system, or modprobe.d. Until you reboot and confirm everything still works, you haven't actually finished.

---

## What's Next (Phase 3 Part 2)

Reserved for a future session:

| Topic | Estimated effort | Lynis impact |
|---|---|---|
| AppArmor profiles | 60-90 min | +5-7 points (new layer) |
| File integrity monitoring (aide) | 45-60 min | Closes FINT-4350 |
| Process accounting (sysstat, psacct) | 20 min | Closes ACCT-9622/9626 |
| Restrict clang same as gcc | 5 min | Closes remaining HRDN-7222 gap |
| FILE-7524 investigation | 10-30 min | Closes that suggestion |
| Secure Boot with self-enrolled keys + signed kernel | 2-3 hours | Big trust-boundary win, no Lynis points |
| TPM2-backed LUKS auto-unlock | 1-2 hours | UX improvement, no Lynis points |

Target for next session: push Lynis score to **80+** and complete the trust boundary work (Secure Boot + TPM2).

---

## Repository Cross-Reference

- Notes used during this session: [linux-hardening-notes/notes/firewall-basics.md](../notes/firewall-basics.md), [post-install-checklist.md](../notes/post-install-checklist.md)
- Previous baseline: [arch-hardening-2026-05-30.md](./arch-hardening-2026-05-30.md)
- Automation: [bash-admin-scripts/scripts/security-check.sh](https://github.com/BertinatorX/bash-admin-scripts/blob/main/scripts/security-check.sh) — should be re-run weekly to detect drift

---

**Session length:** ~4 hours
**Snapper snapshots created:** ~10 (auto-bracketed each pacman operation)
**Files modified:** 8 (sysctl.d/99-hardening.conf, audit/rules.d/99-hardening.rules, ufw rules, login.defs, pam.d/system-auth, security/pwquality.conf, security/limits.conf, modprobe.d/blacklist-rare-net.conf, /etc/issue, /etc/hosts)
**Packages removed:** 64
**Packages installed:** 8 (lynis, rkhunter, arch-audit, libpwquality + deps, zathura + mupdf, tenacity)
**Result:** Lynis 69 → 76 (+7) | 3 High + 1 Medium + 1 Low CVE eliminated | full audit pipeline operational
