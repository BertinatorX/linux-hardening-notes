# Case Study: TongFang GX4 Arch Linux Workstation

## Summary

I did this configuration and troubleshooting work on my TongFang GX4 Linux workstation. The goal was a stable daily-driver Arch Linux system for information systems coursework, virtualization labs, Linux administration practice, and cybersecurity fundamentals, and most of what follows is the troubleshooting, not the install.

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

I wanted a high-contrast desktop with visible system telemetry, so I configured KDE Plasma, KWin, Kvantum, and Conky to get there. The main pieces:

- Replaced a GNOME-focused theme that didn't fit the KDE/X11 environment.
- Configured Kvantum for SVG-based theme rendering.
- Added a Conky status overlay for uptime, CPU, RAM, wireless signal, gateway, and storage usage.
- Added startup delay logic so Conky loads after the compositor, which avoids transparency rendering problems.

Support relevance: a themed desktop looks like the least serious item here, but it still took configuration troubleshooting, it was about usability and monitoring, and the startup delay is a change to startup behavior, which needs documenting.

### Encrypted storage expansion

There was unused space sitting on the NVMe, so I reclaimed it and expanded the encrypted storage layout. The order I did it in:

1. Booted from a live ISO so the filesystems would stay unmounted.
2. Unlocked the LUKS encryption layer.
3. Expanded the physical partition boundary with `parted resizepart`.
4. Resized the encrypted container with `cryptsetup resize`.
5. Extended the LVM physical volume and logical volume.
6. Ran `e2fsck -f` when `resize2fs` required a filesystem check before expansion.
7. Completed the filesystem expansion and verified the available storage.

Support relevance: careful maintenance around encrypted disks, and knowing the safe change procedure before touching partitions. When the resize step failed I troubleshot it instead of forcing unsafe changes, which I think is the real skill.

### Wireless throughput troubleshooting

I troubleshot wireless performance for the Alfa Wi-Fi 6E adapter using the MediaTek MT7921AU chipset. Initial throughput was approximately 230 Mbps. I suspected wireless power-save behavior and conservative defaults were part of it. I changed TCP congestion control from CUBIC to BBR, and observed throughput improved to approximately 900 Mbps under the tested conditions. USB port selection affected performance, some ports produced much lower throughput, and band selection mattered because the network exposed both 2.4GHz and 5GHz options. Overall a big improvement, but it wasn't one fix, it was several variables stacked up.

Support relevance: a network troubleshooting process, testing hardware, driver, protocol, and physical port variables, with the before-and-after results written down instead of trusted to memory.

### Virtualization migration

I moved my virtualization work from VirtualBox to QEMU/KVM, mainly because it's native to Linux and fits in better. What that involved:

- Installed and configured the QEMU/KVM tooling.
- Used virt-manager for VM administration.
- Added OVMF/UEFI support so guests boot like a modern machine.
- Used VirtIO drivers so guests recognize their hardware better.
- Resolved QEMU permission issues involving access to external storage.
- Configured KDE Wallet integration for VS Code credential storage behavior.

Support relevance: virtualization and lab isolation experience, plus the permission and credential-store troubleshooting, which was honestly the more realistic part. I can run Windows and security lab environments without compromising the primary Linux install.

### Software audit and cleanup

I went through everything installed and removed what was redundant or unused. A few examples:

- Removed the extra browsers once I settled on a primary privacy-focused browser.
- Replaced VirtualBox with QEMU/KVM for the main virtualization workflow.
- Documented package-management behavior related to externally managed Python environments and system package protection.

Support relevance: system hygiene, which I'm not pretending is impressive. What matters is knowing the package manager's boundaries and cutting unnecessary software while writing down why.

## Lessons learned

- Partition and encryption work should be planned, backed up, and done from a safe live environment when needed.
- Performance troubleshooting requires testing multiple layers: hardware port, driver behavior, wireless band, power settings, and network stack configuration.
- Virtualization is easier to maintain when storage permissions, guest drivers, and firmware requirements are documented.
- Desktop customization can still show support-relevant skills when it includes repeatable configuration, monitoring, and troubleshooting. A Conky overlay isn't a security project, but the process is the same.

## Career relevance

This project lines up with entry-level roles like:

- IT support
- Desktop support
- Linux support
- NOC support
- Junior system administration
- Cybersecurity internship work

The visual theme isn't the value here, and I'm not pretending it is. The value is the documented process: install, configure, test, troubleshoot, verify, and document. That's what transfers.
