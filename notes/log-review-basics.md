# Linux Log Review Basics

## Goal

Practice basic Linux log review for support and troubleshooting scenarios.

## Check failed services

```bash
systemctl --failed
```

Expected result: Failed services are identified for review.

## Review current boot errors

```bash
journalctl -p 3 -xb
```

Expected result: Critical errors from the current boot are displayed.

## Review a specific service

```bash
journalctl -u sshd
```

If the distribution uses `ssh`:

```bash
journalctl -u ssh
```

## Follow logs live

```bash
journalctl -f
```

Expected result: New log entries appear in real time.

## Review authentication events

Common locations vary by distribution:

```bash
sudo journalctl | grep -i "failed password"
sudo journalctl | grep -i "authentication failure"
```

## Ticket note format

```text
Issue:
Time observed:
Command used:
Relevant log line:
Likely cause:
Action taken:
Verification:
Escalation needed:
```

## What I learned

Log review is useful only when notes are clear. A good support note should include the exact command, relevant timestamp, observed error, and what was done next.
