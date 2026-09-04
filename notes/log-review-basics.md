# Linux Log Review Basics

## Goal

Practice basic Linux log review for support and troubleshooting scenarios.

## Check failed services

```bash
systemctl --failed
```

Expected result: any failed services get listed for review.

## Review current boot errors

```bash
journalctl -p 3 -xb
```

Expected result: critical errors from the current boot show up.

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

Expected result: new log entries show up in real time.

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

Log review is only useful when the notes are clear. A good support note should have the exact command, the relevant timestamp, the error I actually saw, and what I did next.
