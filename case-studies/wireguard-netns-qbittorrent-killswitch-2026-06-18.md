# WireGuard network-namespace kill-switch + NAT-PMP port forwarding for qBittorrent

*CachyOS (Arch) · KDE Plasma (X11) · 2026-06-18*

## Objective

I wanted qBittorrent confined so it can only reach the internet through a ProtonVPN WireGuard tunnel, and it had to fail closed: if the tunnel drops, the traffic has to die, not fall back to the ISP. Then I layered ProtonVPN's NAT-PMP port forwarding on top so inbound peer connections work.

## Why a network namespace, not a firewall kill-switch

The usual "kill-switch" is a set of firewall marks/rules that drop non-VPN traffic. It works, but it depends on rule ordering, and a reconnect, a startup gap, or a misordered rule can leak. A network namespace makes the guarantee structural instead. qBittorrent runs inside a namespace whose only routable interface is the WireGuard device, so there is simply no ISP route in there to leak to. The kill-switch is by construction, not by firewall race.

## Architecture

A systemd oneshot (`vpn-netns.service`) builds the namespace `vpn`. `wg0` is created in the host namespace and then moved into `vpn`. By WireGuard's design the encrypted UDP socket stays bound in the host namespace, so the ciphertext still goes out over the real Wi-Fi route, while the cleartext `wg0` is the namespace's only default route.

A private veth `/30` (`10.200.200.1` on the host, `10.200.200.2` in the namespace) carries the WebUI only, never egress traffic.

Inside the namespace there's defense in depth, I didn't want to trust one layer alone: an nftables table (default-drop), DNS pinned to Proton's resolver through `/etc/netns/vpn/resolv.conf`, an `nsswitch.conf` override so the latent `nss-resolve`/systemd-resolved DNS leak can't happen, IPv6 turned off and checked that it's really gone, a watchdog timer checking the tunnel is still up, and a `systemd-sleep` hook that re-asserts the tunnel after a resume.

`qbittorrent-nox` runs as a sandboxed systemd service joined to the namespace. The WebUI binds to the veth address only and stays password-protected from the host browser.

## Port forwarding

ProtonVPN offers port forwarding via NAT-PMP. I have a helper (`vpn-portforward.service`) running inside the namespace that renews the ~60-second lease every 30s with `natpmpc -g 10.2.0.1 -a 1 0 {tcp,udp}`, parses the mapped public port, and pushes it into qBittorrent's listen port through the WebUI API. It compares every cycle, so it fixes itself when the port changes or qBittorrent restarts.

## Verification (prove the negative)

- Egress IP inside the namespace differs from the host IP (Proton vs ISP).
- DNS resolves only through the Proton resolver, and no IPv6 address exists in the namespace.
- Kill-switch proof: `sudo ip -n vpn link set wg0 down`, then egress attempts time out and *never* print the ISP IP.

The third one is the one I care about, the first two only show the tunnel works while it's up, and a kill-switch isn't proven until you drop it and watch the traffic die.

## Debugging notes (the interesting part)

1. **Headless first run.** `qbittorrent-nox` blocks on an interactive legal-notice prompt, and as a service with no stdin it just hangs (~2 MB RAM, never opens the WebUI). I fixed it by pre-accepting the notice with `[LegalNotice] Accepted=true` in `qBittorrent.conf`.
2. **systemd `ExecStartPre` privilege model.** I had the pre-flight checks running as the unprivileged service user at first, and they failed two ways: an unprivileged process can't open an ICMP socket in a fresh namespace under `NoNewPrivileges=`, and it can't read `/etc/wireguard` (mode `700`). The fix was to prefix those specific checks with `+` so they run as root but still inside the unit's namespaces.
3. **"Firewalled" despite a healthy tunnel.** The kill-switch's nft input chain only accepted `established,related` on `wg0`, so inbound peer connections to the forwarded port were hitting the default drop. The fix was to accept inbound on `wg0` *after* the explicit WebUI-port drop. Proton only forwards the single mapped port, so opening inbound there doesn't expose much, and I'm fine with that.
4. **The DNS bind race.** This is the one I'm least happy with. qBittorrent would intermittently resolve nothing (trackers "Host not found", DHT 0 nodes) because its `/etc/resolv.conf` bind-mount was silently losing to NetworkManager rewriting that file at startup, leaving it on the host's LAN resolver. That resolver is unreachable from inside the namespace, so it failed *closed* (no leak) but broke name resolution. I tried a `mount --bind` workaround and `ProtectSystem=strict` blocked it, then a validation `ExecStartPre` tripped on the `700` `/etc/wireguard` permission. I settled for the plain bind, which works on a clean restart, and a single `systemctl restart qbittorrent-vpn.service` puts it back. The bulletproof fix is launching via `ip netns exec`, which auto-binds the namespace resolver every time, but I've left it documented for a later pass because it trades away `ProtectSystem=strict`, and I'm not sure that's a trade I want to make.
5. **WebUI auto-ban.** After I changed the WebUI password, the port-forward helper kept authenticating with the stale one, so qBittorrent banned the helper's source address (in-memory, ~1 hour) and the helper *renewed* the ban by retrying. Clearing it was just a qBittorrent restart, and I whitelisted the helper's `/32` (`AuthSubnetWhitelist`) so it skips login entirely. No credential to drift, no ban surface, and the host browser still needs the password.

## Outcome

qBittorrent is confined to the tunnel, I've tested it for leaks, and it's reachable on the forwarded port. The whole stack is reversible, it adds no host routing, no host DNS change, and no host firewall rule, so it removes cleanly. Actual key material and credentials live in root-only `600` files and never in unit arguments or logs. Overall I'm happy with it, the namespace approach did what I wanted and the DNS bind race is the only part I'd call unfinished.

## Lessons

- Structural isolation (a namespace) beats rule ordering (firewall marks) for a kill-switch.
- systemd sandboxing (`ProtectSystem`, `NoNewPrivileges`, `BindReadOnlyPaths`) interacts in non-obvious ways with namespace tooling. Know when the `+` privilege prefix is required and when a sandbox option silently blocks a mount, I hit both here.
- NetworkManager owning `/etc/resolv.conf` makes bind-mounting it racy. For a namespaced service the `ip netns exec` auto-bind is the reliable path, even if I haven't switched to it yet.
- Always verify the negative. The kill-switch is only proven when the tunnel-down test fails to leak.
