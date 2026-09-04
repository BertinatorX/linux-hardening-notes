# Linux Post-Install Checklist

## Goal

A repeatable checklist for preparing a fresh Linux installation for daily use, lab work, or entry-level administration practice, so I stop missing steps.

## Environment

- Personal Linux lab system or virtual machine
- Tested concepts intended for Arch Linux, Fedora, or similar distributions
- Commands may vary by distribution

## Checklist

### Confirm system identity

```bash
hostnamectl
uname -a
cat /etc/os-release
```

Expected result: Hostname, kernel, and distribution version match what I installed.

### Update packages

Arch-based systems:

```bash
sudo pacman -Syu
```

Fedora-based systems:

```bash
sudo dnf upgrade --refresh
```

Expected result: Packages update with no unresolved dependency errors.

### Confirm time and time sync

```bash
timedatectl
```

If time synchronization is disabled:

```bash
sudo timedatectl set-ntp true
```

Expected result: Time zone, local time, and NTP status are correct. This is the one I'm most likely to skip, so I make a point of checking it.

### Check users and sudo access

```bash
whoami
id
groups
sudo -v
```

Expected result: The main user is in the expected groups and can use `sudo` when needed.

### Check disk layout

```bash
lsblk
df -h
```

Expected result: Root, boot, home, swap, and any encrypted volumes show up the way I laid them out.

### Check network connectivity

```bash
ip addr
ip route
ping -c 4 1.1.1.1
ping -c 4 example.com
```

Expected result: The system has an IP address, default route, and working DNS resolution.

### Check firewall status

Common Fedora command:

```bash
sudo firewall-cmd --state
sudo firewall-cmd --list-all
```

Common UFW command:

```bash
sudo ufw status verbose
```

Expected result: The firewall service is running and only expected services are allowed.

### Check running services

```bash
systemctl --failed
systemctl list-units --type=service --state=running
```

Expected result: No failed services, or only known non-critical lab issues.

### Review boot logs

```bash
journalctl -p 3 -xb
```

Expected result: No critical boot errors that need action right away.

## Verification

I call the system ready when:

- Packages are updated.
- Time sync is working.
- Network and DNS work.
- Firewall status is known.
- No unexpected failed services are present.
- Basic documentation has been updated.

## What I learned

The list keeps me from missing configuration steps, and when something breaks I walk it again instead of guessing. Overall it's a short list and maybe a bit obvious, but I think the same habit is useful in help desk, desktop support, system administration, and security-focused lab work, and I'd rather have it written down than trust myself to remember every step.
