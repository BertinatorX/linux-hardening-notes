# QEMU/KVM Lab Notes

## Goal

Document the move from VirtualBox to QEMU/KVM for Linux-based virtualization labs.

## Purpose

Virtual machines are used to test operating systems, networking configurations, and security tools in isolated environments without risking the primary workstation.

## Tools

- QEMU
- KVM
- virt-manager
- OVMF/UEFI firmware
- VirtIO drivers

## Setup areas

### Confirm virtualization support

```bash
lscpu | grep -i virtualization
```

### Check libvirt service

```bash
systemctl status libvirtd
```

### Confirm user group membership

```bash
groups
```

Expected groups may include `libvirt` or similar depending on distribution.

## Windows guest requirements

Windows guests may require:

- OVMF/UEFI firmware
- VirtIO storage drivers
- VirtIO network drivers
- Correct ISO attachment during installation

## Permission troubleshooting

One issue involved QEMU permission errors when accessing external storage. The resolution required reviewing QEMU/libvirt permissions and documenting which user or daemon account needed access.

## Credential-store note

VS Code produced keyring-related errors until KDE Wallet integration was corrected and VS Code was launched with the expected password store behavior.

## What I learned

Virtualization troubleshooting often combines storage permissions, user groups, firmware settings, guest drivers, and desktop credential handling. Good documentation reduces repeated troubleshooting during future VM rebuilds.
