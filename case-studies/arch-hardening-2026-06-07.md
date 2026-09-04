# Arch Linux Security Hardening Session: Fresh Install Recovery
Date: 2026-06-07
System: AiStone X4SP4NAL (TongFang GX4), AMD Ryzen AI 9 HX 370 | Arch Linux | Kernel 7.0.9 → 7.0.11
Desktop: Hyprland (Wayland) on JaKooLit dotfiles
Hostname: `Ancilla.localdomain`
Tools Used: lynis, rkhunter, arch-audit, auditd, ufw, augenrules, pacman, snapper, libpwquality, sysctl

---

## Context

This session got the laptop from a Lynis Hardening Index of 69/100, where I'd left it on 2026-05-30, up to 76/100, and part of the work was just getting back to where I already was. A fresh Arch reinstall had wiped every system-level change I'd made, everything in `/etc/`, because none of it lived in my dotfiles. User-level configs survived, system-level configs did not, which I should have seen coming. So the job was to get back to the previous baseline and then push past it.

This is also meant to teach, so each decision has the why written down next to the what.

---

## Starting State Audit

Before changing anything I checked what actually survived the reinstall:

| Layer | Previous state (2026-05-30) | Current state at session start |
|---|---|---|
| UFW | Active, deny incoming, port 2222 allowed | Installed but inactive |
| Lynis | Installed, 69/100 | Not installed |
| rkhunter | Installed | Not installed |
| arch-audit | Installed | Not installed |
| auditd | Installed + enabled | Installed, disabled |
| Kernel sysctl hardening | `/etc/sysctl.d/99-hardening.conf` (20+ knobs) | Gone; only Hyprland's `50-cursor.conf` remained |
| SSH hardening | Port 2222, hardened config | Not installed (decided to keep this way) |

**Lesson:** System-level (`/etc/`) configuration changes are NOT covered by a typical user-dotfile workflow. Document them separately and restore them on purpose.

---

## Scope Decision: SSH Skipped Deliberately

Last session I hardened SSH on port 2222 because Lynis recommended it, without asking whether I needed SSH at all. Thinking about it again, I don't SSH into this laptop from other machines, it's a daily-driver workstation, not a server. The most secure configuration for a service I don't use is not having it installed, so I left the SSH server off on purpose. That removes the attack surface entirely instead of hardening something I didn't need.

**Lesson:** "Most secure" depends on the use case. Removing an unused service beats hardening it, I think I got too focused on chasing Lynis suggestions last time.

---

## Actions Taken

### 1. Security Tooling Installed

```bash
sudo pacman -S --needed lynis rkhunter arch-audit audit
sudo systemctl enable --now auditd
```

Things that tripped me up during install:
- `rkhunter` ships with `rwx------` (mode 700) permissions on its binary, so every invocation needs `sudo`; that's a deliberate Arch security choice
- The `which` command lies if you lack execute permission on a file; use `ls -la <path>` or `pacman -Ql <pkg>` to verify installation
- zsh caches binary lookups; `hash -r` clears the cache after installing new packages

### 2. CVE-Reduction Package Cleanup

`arch-audit` reported 20 vulnerable packages, more than I expected on a fresh install. I went through the list and removed the CVE-affected ones that were either unused or had safer alternatives:

| CVE'd Package | Severity | Replacement | Reason |
|---|---|---|---|
| `djvulibre` | High | (removed with okular) | DjVu support; pulled in by okular |
| `okular` | n/a | `zathura` + `zathura-pdf-mupdf` | Lighter PDF viewer; MuPDF backend is more secure than poppler |
| `jre8-openjdk` | n/a | (removed) | Unused Java 8 runtime |
| `jre8-openjdk-headless` | High | (removed) | Unused Java 8 runtime |
| `moodle-sync` | n/a | (removed) | Pulled in Java 8 stack; not used (Moodle accessible via browser) |
| `calibre` | n/a | (removed) | Unused ebook manager |
| `podofo` | Medium | (removed with calibre) | PDF library; pulled in by calibre |
| `audacity` | Low | `tenacity` | Same UI; tenacity is fork without telemetry |

Final command:
```bash
sudo pacman -Rsc calibre moodle-sync jre8-openjdk okular audacity
sudo pacman -S zathura zathura-pdf-mupdf tenacity
xdg-mime default org.pwmt.zathura.desktop application/pdf
```

The `-Rsc` flag cascaded the removal, so 5 explicit targets removed 64 packages total once orphan dependencies were factored in. Net disk freed: ~507 MB. Three High/Medium CVEs gone, plus one Low CVE.

**Lesson:** Package removal is a security tool, I hadn't thought of it that way before. CVEs you can't patch upstream, you can sometimes eliminate by removing the affected package.

### 3. Kernel Hardening Restored

I created `/etc/sysctl.d/99-hardening.conf` with the settings carried forward from the 2026-05-30 case study:

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

I applied it with `sudo sysctl --system` and verified each setting with `sysctl <key>`.

**Lesson:** Files in `/etc/sysctl.d/` are applied in alphabetical order. The `99-` prefix makes sure my overrides win against the system defaults (`50-default.conf`). Same pattern as Hyprland's `configs/` vs `UserConfigs/`, which is what made it click for me.

### 4. UFW Firewall: Reactivated and Persistent

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw default deny routed
sudo ufw logging low
sudo ufw enable
sudo systemctl enable ufw
sudo systemctl start ufw
```

The big debugging finding: `ufw enable` activates the rules in the kernel but does NOT reliably enable the systemd unit on Arch. Both `systemctl enable ufw` AND `systemctl start ufw` have to be run explicitly after `ufw enable`, or the firewall won't survive a reboot. I'm still not sure why ufw doesn't handle that itself, but it doesn't. I verified by checking that `systemctl is-enabled ufw` and `systemctl is-active ufw` both returned `enabled / active`.

The other thing I found: `linutil`'s "recommended UFW settings" had silently added rules for SSH (port 22, LIMIT), HTTP (80, ALLOW), and HTTPS (443, ALLOW). None of that belongs on a workstation with no inbound services. I removed them with `sudo ufw delete <rule>` to get back to a true deny-all-inbound posture.

**Lesson:** Never trust an auto-installer's "recommended settings" without auditing what they did. Always verify the actual rules with `ufw status verbose`.

### 5. Audit Daemon (auditd) Configured with Rules

Auditd was enabled but had zero rules loaded (Lynis ACCT-9630), so it was running and watching nothing. I wrote a ruleset to `/etc/audit/rules.d/99-hardening.rules` covering:

- Self-protection: changes to `/etc/audit/`, `/var/log/audit/`, `libaudit.conf`
- Identity tampering: `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/sudoers`, `/etc/sudoers.d/`
- Privilege escalation: sudo log + `/etc/pam.d/`
- Time manipulation: `adjtimex`, `settimeofday`, `clock_settime` syscalls + `/etc/localtime`
- Kernel module loading: `init_module`, `finit_module`, `delete_module` syscalls + `/etc/modprobe.d/`
- System startup: `/etc/systemd/`, `/etc/ssh/sshd_config`
- Network config: `/etc/network/`, `/etc/hosts`, `/etc/resolv.conf`
- Mount events: `mount`, `umount2` syscalls

That came out to 23 rules, loaded via `sudo augenrules --load`.

Smoke test, since a rule count alone proves nothing:
```bash
sudo touch /etc/passwd
sudo ausearch -k identity -ts recent
```
That returned a complete forensic record: a SYSCALL event with `auid=1000 uid=0 exe="/usr/bin/touch" key="identity"`, plus PATH and CWD context. So the whole chain works end to end, from the touch to a searchable event.

I tested the `time-change` rule the same way with `sudo date -s "$(date)"` and confirmed a `TIME_INJOFFSET` event was captured.

**Lesson:** Auditd is silent without rules. The daemon will run forever and capture nothing if you forget this step, which is the state I found it in. Always verify with a deliberate test that generates a known event.

### 6. Authentication Hardening

#### `/etc/login.defs` policy:

| Setting | Default | Changed to | Reasoning |
|---|---|---|---|
| `UMASK` | 022 | 027 | New files not readable by "other" users |
| `PASS_MAX_DAYS` | 99999 | 365 | Annual password change |
| `PASS_MIN_DAYS` | 0 | 1 | Prevent rapid re-cycling to defeat history |
| `PASS_WARN_AGE` | 7 | 14 | Earlier warning before expiry |
| `SHA_CRYPT_MIN_ROUNDS` | (unset) | 65536 | More CPU work to crack stolen hashes |
| `SHA_CRYPT_MAX_ROUNDS` | (unset) | 65536 | Cap matches min; no weak fallback |

These only apply to future password changes, so I applied them to my current account right away with:
```bash
sudo chage -M 365 -m 1 -W 14 MBias
```

#### Password strength enforcement (`pam_pwquality.so`):

I installed `libpwquality` (Lynis AUTH-9262) and wired `pam_pwquality.so` into `/etc/pam.d/system-auth` BEFORE `pam_unix.so` in the password stack. Then I tuned `/etc/security/pwquality.conf` with a modern policy (NIST SP 800-63B aligned):

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

I tested it by running `passwd` and giving it a deliberately weak input (`aaa`). PAM rejected it: "BAD PASSWORD: The password is shorter than 12 characters". Getting back out was more annoying than the test itself, I had to keep feeding it invalid input until it exited, since passwd ignores SIGINT/Ctrl+C by design.

**Lesson and recovery story:** My first attempt to edit `/etc/pam.d/system-auth` with vim's `/search` put the cursor in the wrong section (account, not password), which corrupted the account stack, the kind of mistake that can lock you out, so I'm glad I had a backup. I restored from `/etc/pam.d/system-auth.bak` and redid the edit with `sed -i` using a full-line anchor, so the change was explicit and safe to run twice, no cursor surprises. For auth-critical edits I now think sed beats vim, the command itself documents what changed and either matches exactly or fails loudly.

### 7. Hostname / FQDN Configuration

Lynis NAME-4404 wanted the system's FQDN to resolve cleanly. I set the static hostname:
```bash
sudo hostnamectl set-hostname Ancilla.localdomain
```

And added this to `/etc/hosts`:
```
127.0.1.1   Ancilla.localdomain Ancilla
```

Something I learned: the legacy `hostname` CLI is NOT installed by default on modern Arch, `hostnamectl` from systemd is the supported tool. `hostname --fqdn` requires the `inetutils` package, not worth installing on a personal laptop for one check.

### 8. Legal Banner

I wrote `/etc/issue` with an "Authorized Access Only" banner and copied it to `/etc/issue.net` for network-login contexts. (Lynis BANN-7126.) I don't think it does much on a laptop only I log into, but it costs nothing.

### 9. Core Dumps Disabled

I appended this to `/etc/security/limits.conf`:
```
* hard core 0
* soft core 0
```

Combined with the existing `fs.suid_dumpable = 0` sysctl, core dumps are now disabled for all users. (Lynis KRNL-5820.) Core dumps can contain passwords and secrets from crashed-process memory, and they're rarely useful on a desktop anyway.

### 10. Compiler Restriction (a compromise)

Lynis HRDN-7222 wanted compilers restricted to root only. A pure restriction would break `yay` AUR builds, which invoke `gcc` as the user, and I'm not giving up AUR builds for one check. The compromise:

```bash
sudo groupadd compilers
sudo chown root:compilers /usr/bin/gcc /usr/bin/g++
sudo chmod 750 /usr/bin/gcc /usr/bin/g++
sudo gpasswd -a MBias compilers
```

Result: compilers are no longer world-executable (satisfies Lynis), but I'm still in the `compilers` group so `yay` still works. Group membership only activates in new login sessions, which is easy to forget; I verified with `newgrp compilers` then `gcc --version`.

One thing I didn't finish: `clang` is also installed and isn't covered by this yet. Next session.

### 11. Unused Network Protocols Blacklisted

Lynis NETW-3200 flagged four exotic IP protocols I've never used and likely never will. I created `/etc/modprobe.d/blacklist-rare-net.conf`:

```
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
```

`install <module> /bin/true` is the standard idiom for "if anything asks for this module, do nothing successfully." The modules never load → zero attack surface from those code paths. Cheap fix, no downside I can think of.

---

## Things I Skipped on Purpose

### KRNL-6000: `kernel.modules_disabled = 1`

This sysctl is a trapdoor: once set to 1, the kernel refuses to load any new modules until reboot. Real anti-rootkit win, but it breaks:
- USB drives with filesystems whose modules aren't pre-loaded (e.g., rare NTFS variants)
- VMs / libvirt / Docker that may load modules dynamically
- New hardware that needs an unloaded driver

For a personal laptop where I actively use VMs and USB drives, the productivity cost outweighs the 1-Lynis-point gain. I'm writing it down as a deliberate skip so I don't later think I forgot.

### FINT-4350: File Integrity Monitoring (`aide`)

A 45-60 minute setup on its own, which I think deserves its own session. Pushed to Phase 3 part 2.

### Other Skips (and why)

| Suggestion | Why skipped |
|---|---|
| FILE-6310 (×2): separate `/home`, `/var` partitions | Would require disk re-layout; not worth it on single-drive laptop |
| LOGG-2154: remote syslog | No syslog server to send to |
| TIME-3104: NTP daemon | systemd-timesyncd is already the NTP client (false positive) |
| BOOT-5264: systemd service hardening | Per-service tuning, low ROI before AppArmor |
| TOOL-5002: config management | Ansible/Puppet for a single laptop = overkill |
| CRYP-7902: certificate expiration | No custom certs to track |
| USB-1000, STRG-1846: disable USB storage | I actively use USB storage |

---

## Lynis Score Progression

| Run | Hardening Index | Suggestions | Warnings |
|---|---|---|---|
| Start of session (after baseline restored) | 69 / 100 | 33 | 1 (PKGS-7322) |
| After auditd + UFW + sysctl + package cleanup | 73 / 100 | 20 | 1 |
| After auth + core dumps + compilers + hostname + pwquality | 76 / 100 | ~18 | 1 |

Net session gain: +7 points (69 → 76). Decent, though I think the cheap points are mostly used up and what's left is real work.

The remaining warning is `PKGS-7322` (Vulnerable packages): 17 upstream-blocked CVEs in core packages (grub, libxml2, pam, coreutils, openssl, systemd, perl, etc.) for which Arch hasn't published a patched build yet. Not much I can do beyond keeping an eye on https://security.archlinux.org/, and it's the same situation I documented in the 2026-05-30 case study.

Overall I'm happy with where this landed. Getting back to the old baseline was tedious, but the part past it is where I actually learned something, the auditd smoke test most of all.

---

## Verification Steps

I verified each change live:

- `sysctl <key>` confirmed each kernel parameter took effect
- `sudo ufw status verbose` + `systemctl is-enabled ufw` + `systemctl is-active ufw` confirmed the firewall is persistent
- `sudo auditctl -l` confirmed 23 rules loaded
- `sudo ausearch -k identity -ts recent` confirmed events captured end-to-end
- `passwd` with weak input confirmed pwquality enforces the 12-char minimum
- `arch-audit` confirmed 3 High-severity CVEs eliminated
- `hostnamectl` confirmed the FQDN persisted
- `grep` against `/etc/login.defs` confirmed all 6 settings landed correctly
- Snapper pre/post snapshots bracket every pacman operation (rollback available)

---

## Lessons Learned (the ones that carry over)

1. Audit before action. Restoring the previous baseline assumed nothing, I verified what survived the reinstall before making changes. That saved time and prevented duplicate work.

2. Skipping something on purpose is fine as long as the reasoning is written down. Passing on `kernel.modules_disabled` for a 1-point gain because it would break my daily workflow is, I think, the same call as deciding which tickets can wait at a real job.

3. `sed -i` beats vim for surgical config edits, especially for auth-critical files where one wrong line breaks login. The sed command itself is the documentation, and I learned this one the hard way with the PAM edit above.

4. Auto-installers lie, or at least don't tell you everything. `linutil`'s "recommended UFW settings" had silently allowed SSH/HTTP/HTTPS inbound. Always audit what a convenience tool did.

5. A warning that doesn't break behavior is logging, not a problem. The `[WARN] We failed to find wayland buffer with id: X. This should be impossible.` messages from awww-daemon sound scary and are just noise; I ignored them once I understood them. Same with auditd's "Old style watch rules are slower", it's informational, not a failure.

6. Cache layers fool the unaware, and they fooled me. zsh caches binary paths (`hash -r` to refresh), Lynis caches its last result file (re-run to get fresh data), and `which` lies if you lack execute permission. Know your cache layers, or at least know they exist.

7. Reboot is the real persistence test. Many of these changes apply at boot via systemd, sysctl-system, or modprobe.d. Until you reboot and confirm everything still works, you haven't actually finished.

---

## What's Next (Phase 3 Part 2)

Saved for a future session:

| Topic | Estimated effort | Lynis impact |
|---|---|---|
| AppArmor profiles | 60-90 min | +5-7 points (new layer) |
| File integrity monitoring (aide) | 45-60 min | Closes FINT-4350 |
| Process accounting (sysstat, psacct) | 20 min | Closes ACCT-9622/9626 |
| Restrict clang same as gcc | 5 min | Closes remaining HRDN-7222 gap |
| FILE-7524 investigation | 10-30 min | Closes that suggestion |
| Secure Boot with self-enrolled keys + signed kernel | 2-3 hours | Big trust-boundary win, no Lynis points |
| TPM2-backed LUKS auto-unlock | 1-2 hours | UX improvement, no Lynis points |

Target for next session: push the Lynis score to 80+ and get the trust boundary work done (Secure Boot + TPM2). Honestly I'm more interested in the last two rows than the score, no Lynis points but they actually change the trust boundary.

---

## Repository Cross-Reference

- Notes I used during this session: [linux-hardening-notes/notes/firewall-basics.md](../notes/firewall-basics.md), [post-install-checklist.md](../notes/post-install-checklist.md)
- Previous baseline: [arch-hardening-2026-05-30.md](./arch-hardening-2026-05-30.md)
- Automation: [bash-admin-scripts/scripts/security-check.sh](https://github.com/BertinatorX/bash-admin-scripts/blob/main/scripts/security-check.sh), which I should be re-running weekly to catch drift

---

Session length: ~4 hours
Snapper snapshots created: ~10 (auto-bracketed each pacman operation)
Files modified: 8 (sysctl.d/99-hardening.conf, audit/rules.d/99-hardening.rules, ufw rules, login.defs, pam.d/system-auth, security/pwquality.conf, security/limits.conf, modprobe.d/blacklist-rare-net.conf, /etc/issue, /etc/hosts)
Packages removed: 64
Packages installed: 8 (lynis, rkhunter, arch-audit, libpwquality + deps, zathura + mupdf, tenacity)
Result: Lynis 69 → 76 (+7) | 3 High + 1 Medium + 1 Low CVE eliminated | audit pipeline working end to end
