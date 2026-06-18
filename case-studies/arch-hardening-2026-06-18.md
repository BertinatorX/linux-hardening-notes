# Arch Linux Phase 3 Part 3 — Post-Reinstall Re-Hardening (CachyOS + LUKS) + AIDE

**Date:** 2026-06-18
**System:** AiStone X4SP4NAL (TongFang GX4) — AMD Ryzen AI 9 HX 370 | **CachyOS** (Arch rolling) | kernel `linux-cachyos 7.0.12` | **LUKS-encrypted Btrfs** root | **GRUB** | KDE Plasma 6.6.5 on **X11** (SDDM)
**Author:** Alberto R. (BertinatorX)
**Predecessor:** [arch-hardening-2026-06-08.md](./arch-hardening-2026-06-08.md) (Phase 3 Part 2, ended at Lynis 77 on the *previous* Arch install)
**Companion:** [amd-s2idle-resume-freeze-2026-06-17.md](./amd-s2idle-resume-freeze-2026-06-17.md) (the suspend fix done in the same arc)
**Skills demonstrated:** rebuilding a defense-in-depth stack from documentation after a disk reinstall, adapting hardening from systemd-boot→GRUB and unencrypted→LUKS, AUR-package toolchain debugging (nettle-4.0 API break), threat-model-driven scope decisions (vs blindly chasing a scanner score), AIDE on a rolling release.

---

## Context

The machine was reinstalled (Arch→**CachyOS**, now with **LUKS full-disk encryption**, **GRUB**, and KDE-X11 in place of the prior systemd-boot/Hyprland/unencrypted setup). Per my own Phase 3 Part 2 lesson — *"a fresh install wipes every system-level config you ever wrote"* — the entire 06-08 hardening stack was gone. A fresh `lynis audit system` confirmed it: **66/100**, down from the 77 I'd reached, with AppArmor, firejail, ClamAV, auditd, sysstat, the compilers group, and the sysctl/FQDN work all absent.

This session rebuilt the stack from the 06-08 case studies as the blueprint — but **adapted for the new platform**, and deliberately **re-scoped to my actual threat model** rather than re-applying everything just to move the scanner number. A key realization drove the scoping: several Lynis suggestions that would raise the score (password aging, `umask 027`, enforced `pam_pwquality`, legal banner, GRUB password) add friction without protecting a *single-user, sshd-off, LUKS-encrypted* laptop, so they were consciously **skipped**.

---

## What was rebuilt (adapted for GRUB + LUKS)

### 1. AppArmor (MAC) — via GRUB this time
06-08 added the LSM cmdline through a systemd-boot loader entry. This install uses **GRUB**, so the parameters go in `/etc/default/grub`:
```
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet lsm=landlock,lockdown,yama,integrity,apparmor,bpf apparmor=1 audit=1"
```
then `grub-mkconfig -o /boot/grub/grub.cfg` + reboot. Confirmed: `/sys/kernel/security/lsm` now includes `apparmor`, `aa-enabled: Yes`, profiles loaded. The LUKS `cryptdevice`/`root` params live in the separate `GRUB_CMDLINE_LINUX` line and were left untouched (no boot risk to the encryption).

### 2. firejail — Insightful (Mercor work agent) re-sandboxed
The reinstall left Insightful running as a **bare AppImage with full home access** — a regression from the 06-08 sandbox. Rebuilt `~/.config/firejail/insightful.profile` (whitelist-mode FS, `caps.drop all`/`noroot`/`seccomp`, webcam/mic off, filtered D-Bus), the `~/.local/bin/insightful` wrapper (`--appimage` + Electron `--no-sandbox`), and the `.desktop` launcher; **repointed the old launcher and its `workpuls://` scheme handlers** at the wrapper so there's no bare-launch path. Verified from inside the sandbox: `~/.ssh`, `~/.gnupg`, `~/Projects`, `~/.claude` all report *No such file or directory*.

### 3. ClamAV — scheduled + real-time
- Re-enabled `clamav-daemon` + `clamav-freshclam`; weekly scheduled scan (`/usr/local/bin/clamav-scheduled-scan.sh` + timer) with the 06-08 `ExcludePath` set; `clamdscan --fdpass` (so the `clamav` user can read files).
- **New this round:** real-time **on-access** scanning via `clamonacc` (override adds `--fdpass`, `--move=/root/quarantine`), scoped to `~/Downloads` only. Learned that **clamonacc refuses to watch `/tmp`** (clamd uses `/tmp` for its own temp files → scan loop), so `/tmp` was dropped from the watch set.
- Desktop alerts: a root service can't reach the KDE session, so a **user-level `.path`+`.service`** watches the clamonacc log and `notify-send`s on a detection. First version mis-fired because `tail -3` lost the `FOUND` line behind the quarantine-move lines, and because **systemd expands `${l}` in `ExecStart`** — fixed by moving the logic to a script. Verified end-to-end with EICAR: detected, quarantined, popup.

### 4. AIDE (file integrity / intrusion detection) — the hard one
AIDE was **dropped from the Arch repos**; it's AUR-only now (`aur/aide 0.19.3`), and it **does not compile against `nettle 4.0`** (the `nettle_hash_digest_func` signature dropped its `length` argument; `src/md.c:169` passes 3 args). Fixed with a PKGBUILD `prepare()` one-liner patch removing the stale argument, built with `sg compilers -c 'makepkg -si'` (see lesson #4). Then a **tightly-scoped, adversarially-reviewed** config:
- Monitors `/etc`, `/boot`, `/usr/local`, `/opt`, root + login dotfiles, and a short **allowlist** of high-value `/usr` binaries (sudo/su/passwd/shells/systemctl/pacman/libc/PAM/systemd units). **Not** the bulk of `/usr` — pacman already verifies it (`pacman -Qkk`) and it churns every `-Syu`.
- Excludes the churny dev/VM/cache/snapshot trees the stock config never does.
- **Auto-rebaseline via a PostTransaction pacman hook** (`aide --update`, logging the diff): pacman-driven change becomes trusted, so the daily `aide --check` only flags **out-of-band** drift. Honest tradeoff: this trusts pacman + the filesystem state at rebaseline time.
- Baseline built in **6 s** (6,594 entries — the narrow scope paying off vs the ~12-min full-disk scan). Daily `aidecheck.timer` (`Persistent=true`, no `ConditionACPower` — so it runs on a laptop). Drift test verified: a touched `/etc` file fired a critical desktop alert.

### 5. The smaller layers
- **sysctl drop-in** (`/etc/sysctl.d/99-hardening.conf`): `kptr_restrict=1` (deliberately **not** 2 — 2 hides pointers from root too, breaking root eBPF/perf I use for VM/container debugging), `fs.protected_{fifos,regular}=2`, `fs.suid_dumpable=0`, `dev.tty.ldisc_autoload=0`, `send_redirects=0`.
- **modprobe blacklist** for `dccp`/`rds`/`tipc` (SCTP deliberately left enabled — WebRTC/VPN stacks use it).
- **`arch-audit`** (manual, no timer — 0 fixable CVEs at the time; the 18 flagged have no repo fix yet).
- **sysstat** timers, **FQDN** in `/etc/hosts` (`127.0.1.1`), **compilers group** (gcc/clang `750 root:compilers`, me in the group) — now made **durable** with a pacman hook that re-applies the mode after every toolchain update (closing the "pacman resets modes on upgrade" gap from 06-08).
- **auditd**: light **file-watch** ruleset (`/etc/passwd`, `sudoers`, `ssh`, `pam.d`) — NOT the 06-08 `execve` rule, which floods the log on exec-heavy AUR builds and every container/VM start.

---

## Lessons Learned (Generalizable)

1. **A reinstall is a hardening reset — your `/etc` work is the most fragile thing you own.** This is now the *second* time I've rebuilt the whole stack from notes. The notes (this repo) were the only reason it took an evening, not a week. Strong argument for a config-management/restore layer or at least keeping every `/etc` drop-in in version control.
2. **Platform changes invalidate the recipe, not the goal.** systemd-boot→GRUB moved the AppArmor cmdline from a loader entry to `/etc/default/grub`. unencrypted→LUKS changed the boot-risk calculus. The *what* (enforce AppArmor, integrity-check `/etc`) survived; the *how* had to be re-derived.
3. **The scanner score is a proxy, and chasing it can make you less usable.** I ended at **69**, below the old 77 — on purpose. Password aging, `umask 027`, `pam_pwquality` enforcement, a GRUB password: all score points, all net-negative on a single-user LUKS laptop. Real posture (firejail isolation, on-access AV, AIDE, the durable compiler hook) is uncredited by Lynis and is *higher* than the number suggests.
4. **Unmaintained AUR packages break on current toolchains — and the fix is usually one line.** GNU `acct` failed on modern gcc in 06-08; this time AIDE 0.19.3 failed on `nettle 4.0`'s changed digest signature. A PKGBUILD `prepare()` `sed` removing the dropped argument fixed it. Also relearned: **group membership isn't live until re-login** — the compiler restriction blocked `makepkg`'s `gcc` until `newgrp compilers` (the `user@1000` systemd manager lingers with the old group set), and **`newgrp` in a pasted multi-line block silently eats the following lines** (it `exec`s a new shell, discarding zsh's buffered input) — use `sg <group> -c '...'` instead.
5. **On a rolling release, integrity tooling needs an auto-rebaseline or it cries wolf every update.** AIDE's value is detecting change *between* updates; a PostTransaction pacman hook that re-baselines (logging the absorbed diff) is what makes it usable here — at the documented cost of trusting pacman.
6. **Root services can't talk to the desktop — script around it, don't fight it.** Both ClamAV on-access and AIDE reuse the same idiom: `runuser -u mbias -- env DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus notify-send …`.
7. **`systemd` expands `${VAR}` in `ExecStart`.** Inline shell with shell variables in a unit will silently mangle; put the logic in a script and call it.

---

## Lynis Score

| Run | Index | Notes |
|---|---|---|
| 2026-06-08 end (prior install) | 77 | Pre-reinstall peak |
| **2026-06-18 start (reinstall baseline)** | **66** | Everything wiped |
| **2026-06-18 end** | **69** | After the rebuild above |

The +3 understates it badly: AppArmor was already at max MACF credit, firejail/on-access-ClamAV/AIDE/the durable hooks earn little-to-no Lynis points, and the remaining gap to 77 is mostly score-only items I chose to skip (see lesson #3).

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
- **Email alerting** for ClamAV/AIDE via **Proton Mail Bridge** + `msmtp` (the alert scripts already have the email hooks).
- **WireGuard→qBittorrent kill-switch** (network-namespace, leak-proof).
- **Betterbird** mail client; **Win11 VM** (needs `swtpm` reinstalled + OVMF/TPM).
- File the s2idle firmware bug upstream (drafts in `~/strix-s2idle-*`).

## Cross-references
- Previous: [arch-hardening-2026-06-08.md](./arch-hardening-2026-06-08.md) · [insightful-agent-forensic-review-2026-06-08.md](./insightful-agent-forensic-review-2026-06-08.md)
- Companion: [amd-s2idle-resume-freeze-2026-06-17.md](./amd-s2idle-resume-freeze-2026-06-17.md)

**Result:** Reinstall-wiped box restored to a fully-hardened, documented, reproducible state in one session — AppArmor + firejail + ClamAV(scheduled+real-time) + AIDE + auditd + sysctl + compiler restriction, plus the s2idle suspend freeze fixed. Lynis 66→69 (real posture past the old 77).
