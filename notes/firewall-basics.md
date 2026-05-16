# Firewall Basics

## Goal

Practice checking and documenting host firewall status on Linux systems.

## Why it matters

Entry-level IT support and cybersecurity work often requires understanding whether a system is reachable on the network and whether access is intentionally allowed or accidentally exposed.

## Check active listening ports

```bash
ss -tulpen
```

Expected result: Review which services are listening and whether they are bound to localhost or all interfaces.

## Fedora firewalld examples

Check firewall state:

```bash
sudo firewall-cmd --state
```

List active configuration:

```bash
sudo firewall-cmd --list-all
```

List open services:

```bash
sudo firewall-cmd --list-services
```

## UFW examples

Check status:

```bash
sudo ufw status verbose
```

Enable UFW:

```bash
sudo ufw enable
```

Deny incoming traffic by default:

```bash
sudo ufw default deny incoming
```

Allow outgoing traffic by default:

```bash
sudo ufw default allow outgoing
```

## Verification

After making firewall changes:

```bash
sudo ufw status numbered
ss -tulpen
```

Expected result: Firewall rules match documented intent.

## Documentation template

```text
System:
Date:
Firewall tool:
Default inbound policy:
Default outbound policy:
Allowed services:
Reason for each allowed service:
Verification command:
Result:
```

## What I learned

Firewall review is not just turning a tool on. It requires understanding what services are running, what access is needed, and how to document the reason for each allowed connection.
