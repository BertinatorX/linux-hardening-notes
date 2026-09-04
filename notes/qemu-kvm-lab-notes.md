# QEMU/KVM Lab Notes

## Goal

I moved my Linux virtualization labs from VirtualBox to QEMU/KVM and wanted the setup steps in one place.

## Purpose

I use the VMs to test operating systems, network configs, and security tools in isolated environments, so the main workstation isn't at risk.

## Tools

- QEMU
- KVM
- virt-manager
- OVMF/UEFI firmware
- VirtIO drivers

## Setup

### Virtualization support

```bash
lscpu | grep -i virtualization
```

### libvirt service

```bash
systemctl status libvirtd
```

### Group membership

```bash
groups
```

Look for `libvirt` or similar, the name depends on the distro.

## Windows guests

Windows guests may need:

- OVMF/UEFI firmware
- VirtIO storage drivers
- VirtIO network drivers
- Correct ISO attachment during installation

## Permission errors

The annoying one was QEMU permission errors on external storage. The fix was reviewing QEMU/libvirt permissions and writing down which user or daemon account actually needed access.

## Credential store

VS Code kept throwing keyring errors until I fixed the KDE Wallet integration and launched it with the password store behavior it expected. More of a desktop problem than a VM problem, but it was the same mess.

## What I learned

Virtualization trouble is rarely one thing. Mine mixed storage permissions, user groups, firmware settings, guest drivers, and desktop credential handling, which is five places to look. I wrote it down so I'm not redoing this on the next VM rebuild.
