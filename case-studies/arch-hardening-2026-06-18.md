# Arch Linux Phase 3 Part 3: Re-Hardening After the Reinstall (CachyOS + LUKS) + AIDE

Date: 2026-06-18
System: AiStone X4SP4NAL (TongFang GX4), AMD Ryzen AI 9 HX 370 | CachyOS (Arch rolling) | kernel `linux-cachyos 7.0.12` | LUKS-encrypted Btrfs root | GRUB | KDE Plasma 6.6.5 on X11 (SDDM)
Author: Alberto R. (BertinatorX)
Predecessor: [arch-hardening-2026-06-08.md](./arch-hardening-2026-06-08.md) (Phase 3 Part 2, ended at Lynis 77 on the *previous* Arch install)
Companion: [amd-s2idle-resume-freeze-2026-06-17.md](./amd-s2idle-resume-freeze-2026-06-17.md) (the suspend fix done in the same arc)
Skills demonstrated: rebuilding a defense-in-depth stack from documentation after a disk reinstall, adapting hardening from systemd-boot→GRUB and unencrypted→LUKS, AUR-package toolchain debugging (nettle-4.0 API break), threat-model-driven scope decisions (vs blindly chasing a scanner score), AIDE on a rolling release.

---

## Context

I reinstalled the machine, Arch to CachyOS, this time with LUKS full-disk encryption, GRUB, and KDE on X11 in place of the old systemd-boot/Hyprland/unencrypted setup. My own lesson from Phase 3 Part 2, *"a fresh install wipes every system-level config you ever wrote"*, played out exactly, the whole 06-08 hardening stack was gone. A fresh `lynis audit system` confirmed it: 66/100, down from the 77 I had reached, with AppArmor, firejail, ClamAV, auditd, sysstat, the compilers group, and the sysctl/FQDN work all missing.

I rebuilt the stack with the 06-08 case studies as the blueprint, adapted for the new platform, and I deliberately re-scoped it to my actual threat model instead of re-applying everything just to move the scanner number. The reason is that several Lynis suggestions that would raise the score (password aging, `umask 027`, enforced `pam_pwquality`, a legal banner, a GRUB password) add friction without protecting anything on a single-user laptop with sshd off and LUKS on, so I skipped them on purpose.

---

## What I rebuilt (adapted for GRUB + LUKS)

### 1. AppArmor (MAC), via GRUB this time

On 06-08 I added the LSM cmdline through a systemd-boot loader entry. This install uses GRUB, so the parameters go in `/etc/default/grub`:
```
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet lsm=landlock,lockdown,yama,integrity,apparmor,bpf apparmor=1 audit=1"
```
then `grub-mkconfig -o /boot/grub/grub.cfg` + reboot. Confirmed: `/sys/kernel/security/lsm` now includes `apparmor`, `aa-enabled: Yes`, profiles loaded. The LUKS `cryptdevice`/`root` params live in the separate `GRUB_CMDLINE_LINUX` line and I left that alone, so no boot risk to the encryption.

### 2. firejail: Insightful (Mercor work agent) re-sandboxed

The reinstall left Insightful running as a bare AppImage with full home access, a regression from the 06-08 sandbox. I rebuilt `~/.config/firejail/insightful.profile` (whitelist-mode FS, `caps.drop all`/`noroot`/`seccomp`, webcam/mic off, filtered D-Bus), the `~/.local/bin/insightful` wrapper (`--appimage` + Electron `--no-sandbox`), and the `.desktop` launcher, then repointed the old launcher and its `workpuls://` scheme handlers at the wrapper so there's no bare-launch path. Verified from inside the sandbox: `~/.ssh`, `~/.gnupg`, `~/Projects`, `~/.claude` all come back as *No such file or directory*.

### 3. ClamAV: scheduled + real-time

I re-enabled `clamav-daemon` + `clamav-freshclam` and put the weekly scheduled scan back (`/usr/local/bin/clamav-scheduled-scan.sh` + timer) with the 06-08 `ExcludePath` set, using `clamdscan --fdpass` so the `clamav` user can read files.

New this round is real-time on-access scanning through `clamonacc` (the override adds `--fdpass`, `--move=/root/quarantine`), scoped to `~/Downloads` only. I learned that clamonacc refuses to watch `/tmp` (clamd uses `/tmp` for its own temp files and you end up in a scan loop), so `/tmp` came out of the watch set.

A root service can't reach the KDE session, so desktop alerts come from a user-level `.path`+`.service` that watches the clamonacc log and runs `notify-send` on a detection. The first version misfired because `tail -3` lost the `FOUND` line behind the quarantine-move lines, and because systemd expands `${l}` in `ExecStart`; moving the logic into a script fixed it. Verified end to end with EICAR: detected, quarantined, popup.

### 4. AIDE (file integrity / intrusion detection), the hard one

AIDE got dropped from the Arch repos, it's AUR-only now (`aur/aide 0.19.3`), and it does not compile against `nettle 4.0` because the `nettle_hash_digest_func` signature dropped its `length` argument and `src/md.c:169` passes 3 args. A one-liner patch in the PKGBUILD `prepare()` removing the stale argument fixed it, and I built it with `sg compilers -c 'makepkg -si'` (see lesson #4). Then I wrote a tightly-scoped, adversarially-reviewed config.

It monitors `/etc`, `/boot`, `/usr/local`, `/opt`, root and login dotfiles, and a short allowlist of high-value `/usr` binaries (sudo/su/passwd/shells/systemctl/pacman/libc/PAM/systemd units). Not the bulk of `/usr`, pacman already verifies that (`pacman -Qkk`) and it churns every `-Syu`. It also excludes the churny dev/VM/cache/snapshot trees that the stock config never does.

Rebaselining is automatic through a PostTransaction pacman hook (`aide --update`, logging the diff). Pacman-driven change becomes trusted, so the daily `aide --check` only flags out-of-band drift. The honest tradeoff: this trusts pacman, and the filesystem state at rebaseline time.

The baseline built in 6 s (6,594 entries), which is the narrow scope paying off compared to the ~12-min full-disk scan. The daily `aidecheck.timer` has `Persistent=true` and no `ConditionACPower`, so it runs on a laptop. Drift test verified: a touched `/etc` file fired a critical desktop alert.

### 5. The smaller layers

- sysctl drop-in (`/etc/sysctl.d/99-hardening.conf`): `kptr_restrict=1` (deliberately not 2, since 2 hides pointers from root too and breaks the root eBPF/perf I use for VM/container debugging), `fs.protected_{fifos,regular}=2`, `fs.suid_dumpable=0`, `dev.tty.ldisc_autoload=0`, `send_redirects=0`.
- modprobe blacklist for `dccp`/`rds`/`tipc` (SCTP deliberately left enabled, WebRTC/VPN stacks use it).
- `arch-audit`, run manually with no timer (0 fixable CVEs at the time; the 18 it flagged have no repo fix yet).
- sysstat timers, FQDN in `/etc/hosts` (`127.0.1.1`), and the compilers group (gcc/clang `750 root:compilers`, me in the group), now made durable with a pacman hook that re-applies the mode after every toolchain update. That closes the "pacman resets modes on upgrade" gap from 06-08.
- auditd: a light file-watch ruleset (`/etc/passwd`, `sudoers`, `ssh`, `pam.d`), not the 06-08 `execve` rule, which floods the log on exec-heavy AUR builds and every container/VM start.

---

## Lessons learned (generalizable)

1. A reinstall is a hardening reset, and your `/etc` work is the most fragile thing you own. This is now the second time I've rebuilt the whole stack from notes. The notes (this repo) were the only reason it took an evening and not a week. That's a strong argument for a config-management/restore layer, or at least keeping every `/etc` drop-in in version control.
2. Platform changes break the recipe, not the goal. Going from systemd-boot to GRUB moved the AppArmor cmdline from a loader entry to `/etc/default/grub`. Going from unencrypted to LUKS changed the boot-risk math. The what (enforce AppArmor, integrity-check `/etc`) survived, the how had to be worked out again.
3. The scanner score is a proxy, and chasing it can make the machine worse to use. I ended at 69, below the old 77, and that was on purpose. Password aging, `umask 027`, `pam_pwquality` enforcement, a GRUB password: all of them score points, all of them a net negative on a single-user LUKS laptop. The real posture (firejail isolation, on-access AV, AIDE, the durable compiler hook) gets no credit from Lynis and is higher than the number suggests.
4. Unmaintained AUR packages break on current toolchains, and the fix is usually one line. GNU `acct` failed on modern gcc back on 06-08, this time AIDE 0.19.3 failed on `nettle 4.0`'s changed digest signature. A PKGBUILD `prepare()` `sed` removing the dropped argument fixed it. I also relearned that group membership isn't live until you log in again. The compiler restriction blocked `makepkg`'s `gcc` until `newgrp compilers` (the `user@1000` systemd manager hangs around with the old group set), and `newgrp` in a pasted multi-line block silently eats the lines after it (it `exec`s a new shell and throws away zsh's buffered input). Use `sg <group> -c '...'` instead.
5. On a rolling release, integrity tooling needs an auto-rebaseline or it cries wolf on every update. AIDE's value is catching change between updates, and a PostTransaction pacman hook that re-baselines (logging the absorbed diff) is what makes it usable here, at the documented cost of trusting pacman.
6. Root services can't talk to the desktop, so script around it instead of fighting it. ClamAV on-access and AIDE both use the same trick: `runuser -u mbias -- env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send …`.
7. `systemd` expands `${VAR}` in `ExecStart`. Inline shell with shell variables in a unit gets silently mangled, so put the logic in a script and call that.

---

## Lynis score

| Run | Index | Notes |
|---|---|---|
| 2026-06-08 end (prior install) | 77 | Pre-reinstall peak |
| **2026-06-18 start (reinstall baseline)** | **66** | Everything wiped |
| **2026-06-18 end** | **69** | After the rebuild above |

The +3 understates it badly. AppArmor was already at max MACF credit, firejail, on-access ClamAV, AIDE and the durable hooks earn little to no Lynis points, and the remaining gap to 77 is mostly score-only items I chose to skip (see lesson #3).

---

## Files created/changed this session

System (`/etc`, `/usr/local`, units):
- `/etc/default/grub` (AppArmor LSM cmdline) → `grub-mkconfig`
- `/etc/sysctl.d/99-hardening.conf`, `/etc/modprobe.d/disable-rare-net.conf`
- ClamAV: `/usr/local/bin/clamav-scheduled-scan.sh`, scheduled-scan `.service`/`.timer`, `clamd.conf` exclusions + OnAccess scope, `clamonacc` override
- AIDE: `/etc/aide.conf`, `/etc/aide.conf.d/{10-exclusions,20-scope}.conf`, `/usr/local/bin/aide-{rebaseline,scheduled-check}.sh`, `/etc/pacman.d/hooks/zz-aide-rebaseline.hook`, `/etc/systemd/system/aidecheck.{service,timer}`
- auditd: `/etc/audit/rules.d/99-hardening.rules`
- compilers: `/usr/local/bin/restrict-compilers.sh` + `/etc/pacman.d/hooks/restrict-compilers.hook`, `compilers` group, gcc/g++/clang chmod 750
- `/etc/hosts` FQDN; sysstat timers enabled
- suspend: `/usr/lib/systemd/system-sleep/50-amd-pmc-workaround` (see companion case study)

User (`~`):
- `~/.config/firejail/insightful.profile`, `~/.local/bin/insightful`, `.desktop` launchers
- `~/.config/systemd/user/clamav-onaccess-notify.{path,service}` + `~/.local/bin/clamav-onaccess-notify.sh`

---

## What's still open
- Email alerting for ClamAV/AIDE via Proton Mail Bridge + `msmtp` (the alert scripts already have the email hooks).
- WireGuard→qBittorrent kill-switch (network-namespace, leak-proof).
- Betterbird mail client; Win11 VM (needs `swtpm` reinstalled + OVMF/TPM).
- File the s2idle firmware bug upstream (drafts in `~/strix-s2idle-*`).

## Cross-references
- Previous: [arch-hardening-2026-06-08.md](./arch-hardening-2026-06-08.md) · [insightful-agent-forensic-review-2026-06-08.md](./insightful-agent-forensic-review-2026-06-08.md)
- Companion: [amd-s2idle-resume-freeze-2026-06-17.md](./amd-s2idle-resume-freeze-2026-06-17.md)

Result: the reinstall-wiped box is back to a fully-hardened, documented state I can reproduce, in one session: AppArmor + firejail + ClamAV (scheduled + real-time) + AIDE + auditd + sysctl + compiler restriction, plus the s2idle suspend freeze fixed. Lynis 66→69 (real posture past the old 77).
