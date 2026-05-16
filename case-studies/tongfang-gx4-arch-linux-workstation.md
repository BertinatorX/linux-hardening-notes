# Case Study: TongFang GX4 Arch Linux Workstation

## Summary

This case study documents the configuration and troubleshooting work performed on my TongFang GX4 Linux workstation. The goal was to build a stable daily-driver Arch Linux system for information systems coursework, virtualization labs, Linux administration practice, and cybersecurity fundamentals.

## Hardware baseline

- System: TongFang GX4 laptop/workstation
- CPU: AMD Ryzen AI 9 HX 370
- Memory: 124GB LPDDR5x
- Storage: 3.6TB NVMe
- Graphics: Radeon 890M
- Wireless lab adapter: Alfa Wi-Fi 6E adapter using the MediaTek MT7921AU chipset

## Operating system and desktop environment

- Primary OS: Arch Linux
- Desktop environment: KDE Plasma on X11
- Boot: rEFInd
- Shell: Zsh with Oh My Zsh
- Encryption: LUKS full-disk encryption
- Virtualization: QEMU/KVM with virt-manager

## Work performed

### Desktop configuration and system telemetry

Configured KDE Plasma, KWin, Kvantum, and Conky to create a high-contrast desktop environment with visible system telemetry.

Key tasks:

- Replaced a GNOME-focused theme that did not fit the KDE/X11 environment.
- Configured Kvantum for SVG-based theme rendering.
- Added a Conky status overlay for uptime, CPU, RAM, wireless signal, gateway, and storage usage.
- Added startup delay logic so Conky loads after the compositor, avoiding transparency rendering problems.

Support relevance:

- Shows configuration troubleshooting.
- Shows attention to usability and monitoring.
- Shows ability to document changes that affect startup behavior.

### Encrypted storage expansion

Reclaimed unused NVMe space and expanded the encrypted storage layout.

High-level sequence:

1. Booted from a live ISO so filesystems would remain unmounted.
2. Unlocked the LUKS encryption layer.
3. Expanded the physical partition boundary with `parted resizepart`.
4. Resized the encrypted container with `cryptsetup resize`.
5. Extended the LVM physical volume and logical volume.
6. Ran `e2fsck -f` when `resize2fs` required a filesystem check before expansion.
7. Completed filesystem expansion and verified available storage.

Support relevance:

- Shows careful maintenance around encrypted disks.
- Shows awareness of safe change procedure before modifying partitions.
- Shows ability to troubleshoot a failed resize step instead of forcing unsafe changes.

### Wireless throughput troubleshooting

Troubleshot wireless performance for an Alfa Wi-Fi 6E adapter using the MediaTek MT7921AU chipset.

Findings:

- Initial throughput was approximately 230 Mbps.
- Wireless power-save behavior and conservative defaults were suspected contributors.
- TCP congestion control was changed from CUBIC to BBR.
- Observed throughput improved to approximately 900 Mbps under the tested conditions.
- USB port selection affected performance, with some ports producing much lower throughput.
- Band selection mattered because the network exposed both 2.4GHz and 5GHz options.

Support relevance:

- Shows network troubleshooting process.
- Shows testing of hardware, driver, protocol, and physical port variables.
- Shows ability to document before-and-after results.

### Virtualization migration

Moved virtualization work from VirtualBox to QEMU/KVM for better native Linux integration.

Key tasks:

- Installed and configured QEMU/KVM tooling.
- Used virt-manager for VM administration.
- Added OVMF/UEFI support for modern guest boot behavior.
- Used VirtIO drivers for improved guest hardware recognition.
- Resolved QEMU permission issues involving access to external storage.
- Configured KDE Wallet integration for VS Code credential storage behavior.

Support relevance:

- Shows virtualization and lab isolation experience.
- Shows troubleshooting of permissions and credential-store issues.
- Shows ability to run Windows and security lab environments without compromising the primary Linux install.

### Software audit and cleanup

Reviewed installed software and removed redundant or unused applications.

Examples:

- Removed unnecessary browsers after choosing a primary privacy-focused browser.
- Replaced VirtualBox with QEMU/KVM for the main virtualization workflow.
- Documented package-management behavior related to externally managed Python environments and system package protection.

Support relevance:

- Shows system hygiene.
- Shows awareness of package manager boundaries.
- Shows ability to reduce unnecessary software and document why.

## Lessons learned

- Partition and encryption work should be planned, backed up, and performed from a safe live environment when needed.
- Performance troubleshooting requires testing multiple layers: hardware port, driver behavior, wireless band, power settings, and network stack configuration.
- Virtualization is easier to maintain when storage permissions, guest drivers, and firmware requirements are documented.
- Desktop customization can still demonstrate support-relevant skills when it includes repeatable configuration, monitoring, and troubleshooting.

## Career relevance

This project supports entry-level roles involving:

- IT support
- Desktop support
- Linux support
- NOC support
- Junior system administration
- Cybersecurity internship work

The main value is not the visual theme itself. The value is the documented process: install, configure, test, troubleshoot, verify, and document.
