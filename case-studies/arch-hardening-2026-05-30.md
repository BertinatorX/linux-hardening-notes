# Arch Linux Security Hardening Session
**Date:** 2026-05-30  
**System:** AiStone X4SP4NAL — AMD Ryzen AI 9 HX 370 | Arch Linux (Kernel 7.0.10)  
**Tools Used:** lynis, rkhunter, arch-audit, ufw, auditd

---

## Lynis Audit Score
**Hardening Index: 69/100**  
No warnings. 40 suggestions generated.

---

## Actions Taken

### Firewall
- Installed and enabled UFW
- Set default deny incoming, allow outgoing
- Opened port 2222/tcp for SSH
- Port 22 was never explicitly open in UFW (blocked by default)

### SSH Hardening (/etc/ssh/sshd_config)
- AllowTcpForwarding no
- AllowAgentForwarding no
- ClientAliveCountMax 2
- LogLevel VERBOSE
- MaxAuthTries 3
- MaxSessions 2
- TCPKeepAlive no
- Port 2222

### Kernel Hardening (/etc/sysctl.d/99-hardening.conf)
```
dev.tty.ldisc_autoload = 0
fs.protected_fifos = 2
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1
fs.suid_dumpable = 0
kernel.core_uses_pid = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.randomize_va_space = 2
kernel.sysrq = 0
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.forwarding = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_syncookies = 1
```

### Packages Installed
- `ufw` — firewall frontend
- `lynis` — security audit tool
- `rkhunter` — rootkit scanner
- `audit` + `auditd` — kernel audit daemon
- `arch-audit` — CVE vulnerability checker
- `zathura` + `zathura-pdf-mupdf` — PDF viewer (replaced okular)
- `tenacity` — audio editor (replaced audacity)

### Packages Removed (Vulnerability Reduction)
| Package | CVE Risk | Reason Removed |
|---|---|---|
| `audacity` | Low | Replaced with Tenacity (no telemetry) |
| `djvulibre` | High | Removed with okular, replaced by zathura |
| `jre8-openjdk` | High | Unused Java runtime |
| `jre8-openjdk-headless` | High | Unused Java runtime |
| `java-runtime-common` | — | Orphaned after Java removal |
| `moodle-sync` | — | Unused LMS tool (pulled Java) |
| `calibre` | — | Unused ebook manager |
| `podofo` | Medium | Removed with calibre |

---

## Remaining CVEs (Awaiting Arch Security Patches)
These are core/system packages — no action possible except waiting for upstream patches.

| Package | Risk | Notes |
|---|---|---|
| grub | High | Core bootloader |
| libxml2 | High | Deep system dependency |
| pam | High | Auth library |
| coreutils | Medium | Core utils |
| cpio | Medium | Required by virt-install |
| giflib | Medium | Required by gdal, imlib2 |
| libheif | Medium | Media dependency |
| libtiff | Medium | Media dependency |
| linux | Medium | Kernel |
| openjpeg2 | Medium | Required by ffmpeg, gimp, poppler |
| openssl | Medium | Core crypto library |
| openvpn | Medium | Required by ProtonVPN plugin |
| perl | Medium | System scripting |
| systemd | Medium | Init system |
| wget | Medium | Download tool |
| xdg-utils | Medium | Desktop integration |
| xerces-c | Medium | Required by gdal |

Monitor patches at: https://security.archlinux.org

---

## Automation
Security check script deployed to [bash-admin-scripts](https://github.com/BertinatorX/bash-admin-scripts/blob/main/scripts/security-check.sh)

Run manually:
```
bash ~/path/to/security-check.sh
```

Or schedule weekly via cron:
```
0 8 * * 0 bash /path/to/security-check.sh
```
