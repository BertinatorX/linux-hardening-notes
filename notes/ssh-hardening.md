# SSH Hardening Notes

## Goal

Basic SSH hardening steps for my own Linux lab. These are learning notes, so I'd review them before using any of this on a production system.

## Environment

- Linux virtual machine or personal lab system
- OpenSSH server installed
- Administrative access with `sudo`

## Check SSH service status

```bash
systemctl status sshd
```

Some distributions use:

```bash
systemctl status ssh
```

Expected result: The service is active only if remote access is needed.

## Back up the configuration file

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
```

Expected result: A backup exists before making changes.

## Review key settings

Open the configuration file:

```bash
sudo nano /etc/ssh/sshd_config
```

Common settings to review:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
```

## Validate configuration before restart

```bash
sudo sshd -t
```

Expected result: No syntax errors are returned.

## Restart SSH safely

```bash
sudo systemctl restart sshd
```

If the system uses `ssh`:

```bash
sudo systemctl restart ssh
```

## Verify access

Before closing the current session, open a second terminal and test login:

```bash
ssh user@host
```

Expected result: The user can log in using the intended method.

## Troubleshooting notes

- If login fails, use the existing active session to restore the backup file.
- Confirm the correct username, hostname, and key path.
- Check logs with `journalctl -u sshd` or `journalctl -u ssh`.
- Confirm the firewall allows SSH only if remote access is required.

## What I learned

SSH hardening, for me, is really about careful change control. I don't want to lock myself out, so I back up the config file first, validate the syntax, and test login from a second terminal before closing the first one, then I write down the exact changes I made. Overall it's simple stuff, I just don't trust a restart until I've proven I can still get in.
