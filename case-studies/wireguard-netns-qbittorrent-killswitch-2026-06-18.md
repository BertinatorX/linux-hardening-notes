# WireGuard network-namespace kill-switch + NAT-PMP port forwarding for qBittorrent

*CachyOS (Arch) · KDE Plasma (X11) · 2026-06-18*

## Objective

Confine qBittorrent so it can reach the internet **only** through a ProtonVPN WireGuard
tunnel, fail-closed — if the tunnel drops, traffic must die rather than fall back to the
ISP — then layer ProtonVPN's NAT-PMP port forwarding on top so inbound peer connections work.

## Why a network namespace, not a firewall kill-switch

The common "kill-switch" is a set of firewall marks/rules that drop non-VPN traffic. It works,
but it is rule-ordering dependent: a reconnect, a startup gap, or a misordered rule can leak.
A **network namespace** makes the guarantee structural instead. qBittorrent runs inside a
namespace whose only routable interface is the WireGuard device — there is simply no ISP route
in that namespace to leak to. The kill-switch is by construction, not by firewall race.

## Architecture

- A systemd oneshot (`vpn-netns.service`) builds namespace `vpn`.
- `wg0` is created in the host namespace and then **moved** into `vpn`. By WireGuard's design the
  encrypted UDP socket stays bound in the host namespace, so ciphertext still egresses via the
  real Wi-Fi route, while the cleartext `wg0` is the namespace's sole default route.
- A private veth `/30` (`10.200.200.1` host ↔ `10.200.200.2` namespace) carries the WebUI only —
  never egress traffic.
- Defense in depth inside the namespace: an nftables table (default-drop), DNS pinned to Proton's
  resolver via `/etc/netns/vpn/resolv.conf`, an `nsswitch.conf` override to defeat the latent
  `nss-resolve`/systemd-resolved DNS leak, IPv6 disabled and asserted absent, a watchdog timer
  enforcing live tunnel health, and a `systemd-sleep` hook to re-assert the tunnel on resume.
- `qbittorrent-nox` runs as a sandboxed systemd service joined to the namespace; the WebUI binds
  to the veth address only and stays password-protected from the host browser.

## Port forwarding

ProtonVPN offers port forwarding via NAT-PMP. A helper (`vpn-portforward.service`) runs inside the
namespace, renews the ~60-second lease every 30s with `natpmpc -g 10.2.0.1 -a 1 0 {tcp,udp}`, parses
the mapped public port, and syncs it into qBittorrent's listen port through the WebUI API — comparing
every cycle so it self-heals across port changes and qBittorrent restarts.

## Verification (prove the negative)

- Egress IP inside the namespace differs from the host IP (Proton vs ISP).
- DNS resolves only through the Proton resolver; no IPv6 address exists in the namespace.
- **Kill-switch proof:** `sudo ip -n vpn link set wg0 down` → egress attempts time out and *never*
  print the ISP IP. A kill-switch isn't proven until you drop the tunnel and watch traffic die.

## Debugging notes (the interesting part)

1. **Headless first run.** `qbittorrent-nox` blocks on an interactive legal-notice prompt; as a
   service with no stdin it just hangs (~2 MB RAM, never opens the WebUI). Fix: pre-accept with
   `[LegalNotice] Accepted=true` in `qBittorrent.conf`.
2. **systemd `ExecStartPre` privilege model.** Pre-flight checks initially ran as the unprivileged
   service user and failed two ways: an unprivileged process can't open an ICMP socket in a fresh
   namespace under `NoNewPrivileges=`, and can't read `/etc/wireguard` (mode `700`). Fix: prefix
   those specific checks with `+` so they run as root within the unit's namespaces.
3. **"Firewalled" despite a healthy tunnel.** The kill-switch's nft input chain accepted only
   `established,related` on `wg0`, so inbound peer connections to the forwarded port hit the default
   drop. Fix: accept inbound on `wg0` *after* the explicit WebUI-port drop. Proton only forwards the
   single mapped port, so exposure stays minimal.
4. **The DNS bind race.** qBittorrent intermittently resolved nothing (trackers "Host not found",
   DHT 0 nodes) because its `/etc/resolv.conf` bind-mount silently lost to NetworkManager rewriting
   that file at startup, leaving it on the host's LAN resolver — which is unreachable from inside the
   namespace, so it failed *closed* (no leak) but broke name resolution. A `mount --bind` workaround
   was blocked by `ProtectSystem=strict`; a validation `ExecStartPre` then tripped on the `700`
   `/etc/wireguard` permission. Pragmatic resolution: the plain bind works on a clean restart, and a
   single `systemctl restart qbittorrent-vpn.service` re-establishes it. The bulletproof fix —
   launching via `ip netns exec`, which auto-binds the namespace resolver every time — is documented
   for a later pass because it trades away `ProtectSystem=strict`.
5. **WebUI auto-ban.** After a WebUI password change, the port-forward helper kept authenticating with
   the stale password, so qBittorrent banned the helper's source address (in-memory, ~1 hour) and the
   helper *renewed* the ban by retrying. Fix: clear it by restarting qBittorrent, and whitelist the
   helper's `/32` (`AuthSubnetWhitelist`) so it bypasses login entirely — no credential to drift, no
   ban surface, while the host browser still requires the password.

## Outcome

qBittorrent is confined to the tunnel, leak-verified, and reachable on the forwarded port. The whole
stack is reversible: it adds no host routing, no host DNS change, and no host firewall rule, so it
removes cleanly. Actual key material and credentials are kept in root-only `600` files and never in
unit arguments or logs.

## Lessons

- Structural isolation (a namespace) beats rule ordering (firewall marks) for a kill-switch.
- systemd sandboxing (`ProtectSystem`, `NoNewPrivileges`, `BindReadOnlyPaths`) interacts in
  non-obvious ways with namespace tooling — know when the `+` privilege prefix is required and when a
  sandbox option silently blocks a mount.
- NetworkManager owning `/etc/resolv.conf` makes bind-mounting it racy; for a namespaced service the
  `ip netns exec` auto-bind is the reliable path.
- Always verify the negative — the kill-switch is only proven when the tunnel-down test fails to leak.
