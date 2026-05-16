# Linux Hardening Notes

Practical Linux administration and security notes from my personal lab environment. This repository documents repeatable setup, hardening, and troubleshooting steps for Linux systems with an emphasis on reliability, security basics, and clear technical documentation.

## Purpose

I am an Information Systems student transitioning into entry-level IT support and cybersecurity. This project is meant to show how I approach Linux configuration, system hardening, documentation, and troubleshooting in a structured way.

## Skills demonstrated

- Linux installation and post-install configuration
- User and group management
- Full-disk encryption concepts with LUKS
- Firewall and SSH hardening basics
- Package management and system updates
- Service management with `systemctl`
- Basic log review and troubleshooting
- Clear documentation for repeatable technical work

## Lab environment

The notes in this repository are based on personal lab systems and virtual machines. My current learning environment includes:

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

## Repository structure

```text
linux-hardening-notes/
├── README.md
├── case-studies/
│   └── tongfang-gx4-arch-linux-workstation.md
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
└── references/
    └── command-cheatsheet.md
```

## Planned documentation

### Post-install checklist

A checklist for preparing a fresh Linux installation for daily use or lab work. Topics include system updates, time sync, package cleanup, firewall enablement, user account checks, and basic verification commands.

### User and permission basics

Notes covering Linux users, groups, file permissions, ownership, `sudo`, and safe administrative habits.

### Firewall basics

Basic host firewall notes using common Linux firewall tools. The goal is to document how to confirm firewall status, allow only needed services, and verify open ports.

### SSH hardening

A practical checklist for safer SSH configuration in a lab setting, including key-based login concepts, disabling unnecessary access, and checking service status.

### LUKS encryption notes

Study notes on Linux full-disk encryption concepts, encrypted partitions, recovery considerations, and documentation habits for avoiding lockout.

### LUKS/LVM resize recovery

Notes from reclaiming unused NVMe space, resizing an encrypted LUKS container, extending LVM, and resolving filesystem resize requirements with `e2fsck` before `resize2fs`.

### Wi-Fi throughput tuning

Notes from troubleshooting wireless throughput on an Alfa Wi-Fi 6E adapter using a MediaTek MT7921AU chipset, including power-save settings, TCP congestion control, port testing, and band selection.

### QEMU/KVM lab notes

Notes from moving from VirtualBox to QEMU/KVM, configuring OVMF/UEFI, VirtIO drivers, and resolving permission issues for external storage access.

### KDE/Conky desktop telemetry

Notes from configuring KDE Plasma, KWin, Kvantum, and Conky to display system telemetry while documenting configuration changes and startup behavior.

### Log review basics

Introductory notes on reviewing Linux logs for support and troubleshooting. Topics include boot logs, authentication logs, service failures, and common `journalctl` commands.

## Example checklist format

Each note will use a consistent format:

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

This repository supports entry-level roles such as:

- IT Support Specialist
- Help Desk Technician
- Desktop Support Technician
- Linux Support Technician
- NOC Technician
- Cybersecurity Intern
- Junior System Administrator

The focus is not on advanced production administration. The focus is on showing structured learning, safe configuration habits, and the ability to document technical work clearly.

## Current certification status

I am currently studying for CompTIA Tech+ and plan to complete the exam by October 2026.

## Safety note

This repository does not include passwords, private keys, customer data, internal company data, or sensitive system screenshots.
