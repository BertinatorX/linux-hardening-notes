# Linux Command Cheatsheet

## System information

```bash
hostnamectl
uname -a
cat /etc/os-release
uptime
```

## Disk and storage

```bash
lsblk
df -h
du -sh *
```

## Networking

```bash
ip addr
ip route
ping -c 4 1.1.1.1
ping -c 4 example.com
ss -tulpen
```

## Services and logs

```bash
systemctl status <service>
systemctl --failed
journalctl -u <service>
journalctl -p 3 -xb
```

## Users and permissions

```bash
whoami
id
groups
ls -la
chmod
chown
```

## Package management

Arch:

```bash
sudo pacman -Syu
pacman -Q
```

Fedora:

```bash
sudo dnf upgrade --refresh
dnf list installed
```
