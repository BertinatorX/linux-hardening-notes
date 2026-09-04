# Linux Hardening Notes

These are my Linux admin and security notes from my own lab: setup, hardening, and troubleshooting steps I've worked through, written down so I can repeat them, with emphasis on reliability, security basics, and clear write-ups.

## Purpose

I'm an Information Systems student moving into entry-level IT support and cybersecurity. This repo is my record of how I actually go about Linux configuration, system hardening, documentation, and troubleshooting, in a structured way instead of fixing things and forgetting them.

## Skills I practiced

What I got hands-on with here:

- Linux installation and post-install configuration
- User and group management
- Full-disk encryption concepts with LUKS
- Firewall and SSH hardening basics
- Package management and system updates
- Service management with `systemctl`
- Basic log review and troubleshooting
- Clear documentation for repeatable technical work

## Lab environment

The notes come from my own lab systems and virtual machines, not production. What I'm learning on:

- TongFang GX4 laptop/workstation
- AMD Ryzen AI 9 HX 370 platform
- 124GB RAM
- 3.6TB NVMe storage
- Arch Linux
- Fedora Linux
- Kali Linux for security training labs
- QEMU/KVM virtualization
- Bash and Zsh shell environments
- Git for version control

## Repo layout

```text
linux-hardening-notes/
├── README.md
├── case-studies/
│   ├── tongfang-gx4-arch-linux-workstation.md
│   ├── arch-hardening-2026-05-30.md
│   ├── arch-hardening-2026-06-07.md
│   ├── arch-hardening-2026-06-08.md
│   ├── insightful-agent-forensic-review-2026-06-08.md
│   ├── amd-s2idle-resume-freeze-2026-06-17.md
│   ├── amd-s2idle-kernel-bracket-and-upstream-collaboration-2026-07.md
│   ├── arch-hardening-2026-06-18.md
│   └── wireguard-netns-qbittorrent-killswitch-2026-06-18.md
├── bug-reports/
│   ├── strix-s2idle-bugreport.md
│   └── strix-s2idle-forumpost.md
├── aide/
├── notes/
│   ├── post-install-checklist.md
│   ├── user-and-permission-basics.md
│   ├── firewall-basics.md
│   ├── ssh-hardening.md
│   ├── luks-encryption-notes.md
│   ├── luks-lvm-resize-recovery.md
│   ├── qemu-kvm-lab-notes.md
│   ├── wifi-throughput-tuning.md
│   ├── kde-conky-desktop-telemetry.md
│   └── log-review-basics.md
├── scripts/
│   └── system-health-check.sh
└── references/
    └── command-cheatsheet.md
```

## Notes, written and planned

### Post-install checklist

What I run through on a fresh Linux install for daily use or lab work: system updates, time sync, package cleanup, turning the firewall on, user account checks, and basic verification commands. Nothing clever, just what's annoying to forget.

### User and permission basics

Users, groups, file permissions, ownership, `sudo`, and safe admin habits. Permissions are what I second-guess most, so I want my own explanation handy.

### Firewall basics

Host firewall notes using the common Linux firewall tools: confirming firewall status, allowing only needed services, and verifying open ports, because assuming it's on isn't good enough.

### SSH hardening

A practical checklist for safer SSH configuration in a lab setting: key-based login concepts, disabling access that isn't needed, and checking service status.

### LUKS encryption notes

Study notes on Linux full-disk encryption concepts, encrypted partitions, recovery considerations, and the documentation habits that keep you from locking yourself out. The lockout part is the one I care about most.

### LUKS/LVM resize recovery

Notes from a real problem: reclaiming unused NVMe space, resizing an encrypted LUKS container, extending LVM, and resizing the filesystem, which needs `e2fsck` run before `resize2fs`. Simple on paper, less so on an encrypted volume.

### Wi-Fi throughput tuning

Troubleshooting wireless throughput on an Alfa Wi-Fi 6E adapter with a MediaTek MT7921AU chipset: power-save settings, TCP congestion control, port testing, and band selection.

### QEMU/KVM lab notes

Notes from moving off VirtualBox onto QEMU/KVM, setting up OVMF/UEFI and VirtIO drivers, and sorting out the permission issues I hit with external storage. More work than I expected, no regrets.

### KDE/Conky desktop telemetry

Setting up KDE Plasma, KWin, Kvantum, and Conky to show system telemetry, with the configuration changes and startup behavior written down as I went. Partly for looks, I'll admit.

### Log review basics

Introductory notes on reading Linux logs for support and troubleshooting: boot logs, authentication logs, service failures, and common `journalctl` commands. Introductory on purpose, it's day-one help desk level.

## Checklist format

Each note will use the same skeleton:

```text
Goal:
Environment:
Commands used:
Expected result:
Verification:
Troubleshooting notes:
What I learned:
```

## Career relevance

The roles I'm aiming at with this, all entry-level:

- IT Support Specialist
- Help Desk Technician
- Desktop Support Technician
- Linux Support Technician
- NOC Technician
- Cybersecurity Intern
- Junior System Administrator

I'm not claiming advanced production administration here, I haven't done that yet. What it does show is organized learning, careful configuration habits, and clear write-ups of technical work. Overall it's a beginner's repo, but a careful one.

## Certification status

I'm studying for CompTIA Tech+ right now and plan to have the exam done by October 2026.

## Safety note

No passwords, private keys, customer data, internal company data, or sensitive system screenshots are in this repo.

## Development note

Parts of this repo, including debugging sessions, documentation drafting, and script review, were worked through with Claude (Anthropic's AI assistant, via Claude Code), used as a pair-debugging and writing aid. I ran all the commands myself on my own hardware, and the decisions and result checks were mine too.
