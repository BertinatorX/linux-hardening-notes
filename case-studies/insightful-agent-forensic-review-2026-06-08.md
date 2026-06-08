# Forensic Review of an Opaque Work Agent on a Personal Device

**Date:** 2026-06-08
**System:** Arch Linux 7.0.11 on AiStone X4SP4NAL (TongFang GX4) — personal daily-driver laptop
**Subject:** "Workpuls" / Insightful (https://insightful.io) — workforce-analytics agent
**Distribution:** AppImage (`Workpuls.AppImage`), manually installed
**Author:** Alberto R. (BertinatorX)
**Skills demonstrated:** AppImage analysis, Electron forensic artifact triage, network IoC extraction, SQLite forensics, BYOD risk reasoning

---

## Context

I installed an AppImage labeled `Workpuls.AppImage` to evaluate it as a work agent — Insightful is a workforce-analytics platform sold to employers for time tracking, application usage, and (optionally) screenshot/screen-record capture. The installer was manually run; the agent launched briefly via the menu entry but I terminated it within minutes after deciding to assess it before granting it standing access to my machine.

The .desktop launchers later failed because the AppImage path I'd configured was incorrect, leaving the menu entries pointing at a non-existent binary. This forced a triage decision: clean up the failed install entirely, then review what the brief runtime had captured before re-installing it correctly with appropriate isolation.

This case study documents the forensic walkthrough I performed before re-introducing the agent in a sandboxed configuration.

---

## Pre-removal Inventory

After the broken launcher symptoms, I first enumerated every artifact left behind:

```bash
find ~/.local/share/applications ~/.local/share/AppImage ~/Desktop \
  -iname "*workp*" -o -iname "*Workpuls*" 2>/dev/null
```

Three files found:

| Path | Type |
|---|---|
| `~/.local/share/applications/workpuls-agent.desktop` | Original install's launcher |
| `~/.local/share/applications/workplus.desktop` | Typo'd second launcher |
| `~/.local/share/AppImage/Workpuls.AppImage` | The AppImage itself |

Auto-restart vector check (all returned empty):
```bash
systemctl --user list-units --all | grep -i workp
systemctl --user list-unit-files | grep -i workp
ls ~/.config/systemd/user/ 2>/dev/null | grep -i workp
ls ~/.config/autostart/ 2>/dev/null | grep -i workp
```

**Finding:** No persistence vectors — the agent had no systemd user unit and no XDG autostart entry. It would not have launched again on its own after this session.

---

## Identifying the Application Data Directory

```bash
ls -la ~/.config 2>/dev/null | grep -iE "workp"
```

Returned a 366-byte directory at `~/.config/workpuls-agent/` last modified `Jun 7 22:56`. The structure matched a textbook **Electron / Chromium-derived application profile** (Cookies, GPUCache, DawnCache, Local Storage, etc.). This told me, before reading any of the contents, that:

- The agent uses **Electron** (Chromium + Node.js packaged as a desktop app)
- It would have its own embedded browser engine, **separate from any system browser**
- It will exhibit Chromium's full network stack — including HTTP/3, QUIC, and HSTS pinning
- Standard Chromium forensic techniques would apply

---

## File-System Layout (Electron Application Profile)

```
~/.config/workpuls-agent/
├── blob_storage/             # Web Worker blobs
├── Cache/                    # HTTP cache
├── Code Cache/               # JIT'd Chromium V8 bytecode
├── Cookies                   # SQLite — HTTP cookies (20 KB — populated)
├── Cookies-journal           # SQLite WAL journal (empty)
├── Crashpad/                 # Crash reports
├── DawnCache/                # WebGPU shader cache
├── Dictionaries/             # Spellcheck dictionaries
├── GPUCache/                 # GL shaders
├── Local Storage/            # Web localStorage backing
├── logs/main/                # App logs (empty — short runtime)
├── Network Persistent State  # JSON — HSTS, HTTP/3 advertised services
├── Preferences               # JSON — user prefs (57 B — minimal)
├── sentry/                   # Sentry crash reporter state
├── Session Storage/          # Web sessionStorage backing
├── storage                   # SQLite — 475 KB — likely the agent's local DB
└── TransportSecurity         # HSTS pin cache
```

The mode bits on every file/dir were `0700` or `0600`. **The agent isolated its data from other users**, which is fine practice — but doesn't constrain what the agent itself can see or do as that user.

---

## Reading the Server Topology (No Code Execution Required)

The most informative artifact for a forensic walkthrough is `Network Persistent State`. This is a JSON file Chromium writes to remember HTTP/3 protocol negotiation per remote host. Reading it reveals every server the application actually attempted to contact, without ever running the app again.

```bash
strings "~/.config/workpuls-agent/Network Persistent State" | head -20
```

Parsed output:

```json
{
  "net": {
    "http_server_properties": {
      "servers": [
        { "server": "https://redirector.gvt1.com",  "supports_spdy": true },
        { "server": "https://r2---sn-2xv2axnjvh-q4fs.gvt1.com" },
        { "server": "https://insightful-updates.io", "supports_spdy": true },
        { "server": "https://www.gravatar.com",      "supports_spdy": true },
        { "server": "https://app.insightful.io",     "supports_spdy": true },
        { "server": "https://o1124917.ingest.sentry.io", "supports_spdy": true }
      ],
      "supports_quic": {
        "address": "192.168.1.228",
        "used_quic": true
      }
    }
  }
}
```

### Network indicators of compromise (IoC) — interpreted

| Endpoint | Purpose | Risk Class |
|---|---|---|
| `app.insightful.io` | **Insightful main application server.** This is where session/event data is uploaded. Captured screenshots, timeline events, and idle detection all flow here. | **Vendor — first-party data destination** |
| `insightful-updates.io` | Insightful's update channel. The agent will fetch new versions, possibly unsigned, from here. | **Vendor — supply chain risk** |
| `o1124917.ingest.sentry.io` | Sentry telemetry endpoint. Receives stack traces, version, OS, sometimes breadcrumb data from app errors. | **Third-party telemetry** |
| `redirector.gvt1.com`, `r2---sn-...gvt1.com` | Google Update infrastructure (Chromium baseline). | Benign — built into Electron |
| `www.gravatar.com` | Gravatar profile image lookups. | Benign |

**Conclusion:** The agent communicates with **three Insightful-controlled domains** plus one third-party telemetry endpoint plus standard Electron/Google update infrastructure. Before granting standing access on a personal machine, these endpoints define the trust boundary I am extending.

**Branding observation:** the binary is named "Workpuls" but the domains are "insightful.io". Insightful is the **rebranded name of Workpuls** (rebrand circa late 2022). This rebrand is documented publicly and not anomalous, but in a real triage I would document the dual identity so it doesn't surprise me later in firewall logs.

### Outbound IP observed

```
"address":"192.168.1.228","used_quic":true
```

This is the source IP my laptop had on the LAN at the time of capture. QUIC was used for outbound — meaning **HTTP/3 over UDP 443**, not the usual TCP-based HTTPS. Worth noting because some firewall rules built around TCP/443 will silently miss QUIC traffic.

---

## Local Storage Artifact

```bash
file ~/.config/workpuls-agent/storage
```

```
SQLite 3.x database, last written using SQLite version 3053002,
file counter 43, database pages 116
```

**Interpretation:**

- `file counter 43` — the database has had 43 write transactions committed. Suggests modest activity during the short runtime, not silent dormancy
- `database pages 116` — at the default 4 KB page size, that's ~475 KB. Matches the file size on disk
- Real-world follow-up: open with `sqlite3 storage .tables` to enumerate tables. In a vendor evaluation context I would do this to understand *what schemas the agent uses locally* — events, screenshots, idle counters, etc. — before deciding whether the data ever leaves the machine pre-upload.

```bash
cat ~/.config/workpuls-agent/Preferences
```

```json
{"spellcheck":{"dictionaries":["en-US"],"dictionary":""}}
```

Only 57 bytes. No employer/team binding visible — confirming the agent never completed a sign-in/registration handshake before I terminated it. This is forensically important: **no employer is yet associated with my install on Insightful's backend**. Re-installation under the correct employer context would create a fresh association.

---

## Removal vs Re-installation Decision

For this evaluation the chosen path was: **full removal, then re-install with appropriate isolation when work onboarding requires it.**

### Removal procedure

Removed the launchers and AppImage:
```bash
rm ~/.local/share/applications/workpuls-agent.desktop
rm ~/.local/share/applications/workplus.desktop
rm ~/.local/share/AppImage/Workpuls.AppImage
```

Refreshed the desktop database to drop stale menu entries:
```bash
update-desktop-database ~/.local/share/applications
```

Removed the application data directory:
```bash
rm -rf ~/.config/workpuls-agent
```

Verified clean:
```bash
find ~/.local/share/applications ~/.local/share/AppImage -iname "*workp*" -o -iname "*Workpuls*"
ls -la ~/.config/ | grep -i workp
```

Both returned empty.

---

## Re-installation Plan (BYOD With Isolation)

When work onboarding requires Insightful, the goal is **work-time data capture without standing access to the rest of my personal system**. The technical options, in increasing isolation:

| Approach | Isolation | UX cost | Picked? |
|---|---|---|---|
| Reinstall AppImage as-is | None — full access to home dir, network, processes | Lowest | ❌ |
| Run Insightful via `firejail` profile | Filesystem and network whitelist | Some setup, transparent in use | Strong candidate |
| Run Insightful inside a Flatpak with restricted permissions | Filesystem portal + DBus | Minor | Candidate |
| Run Insightful inside a dedicated GNOME Boxes / QEMU VM with shared display | Full kernel isolation | Boot a VM each work session | Strongest — but high friction |
| Buy a $200 ChromeOS / cheap second laptop as the work device | Hardware isolation | Cost + carry | Most secure — last resort |

My approach for personal-laptop BYOD will be **firejail with a custom profile**, scoped to:
- Whitelist `~/Documents/Work` and Insightful's own config dir as the only writable home paths
- Allow outbound network only to the identified Insightful endpoints (`app.insightful.io`, `insightful-updates.io`, `o1124917.ingest.sentry.io`)
- Deny access to `~/.ssh`, `~/.gnupg`, the `linux-hardening-notes` repo, browser cookies, password manager state, every personal config dir
- Disable webcam, microphone, and clipboard access by default (re-enable per-call only if the work mandate explicitly requires it)

This means even if the Insightful agent has a vulnerability or its servers are breached, the attacker is confined to a sandbox that contains nothing personal of value.

The Insightful screenshot/screen-record feature, if enabled by the employer, would still capture *what's on screen during work hours*. That is a workflow control (close personal apps before clocking in) rather than a technical one.

---

## Lessons Learned (Generalizable)

1. **AppImage = no package manager, no audit trail.** The OS doesn't know what an AppImage installed, what it depends on, or where its data lives. Treat every AppImage as a black box and document everything yourself.

2. **Electron app data directories are forensic gold.** `Network Persistent State`, `Preferences`, `storage` (SQLite), and `Cookies` (SQLite) reveal the application's server topology, configuration, and stored state — all without running the binary.

3. **Read-only triage before execution.** `file`, `strings`, `cat`, `sqlite3 .tables` give you a high-resolution picture without ever launching the suspect program a second time.

4. **HTTP/3 / QUIC is a real blind spot.** Many simple firewall rules target TCP/443; QUIC uses UDP/443. Any firewall protecting against an exfiltrating agent needs to cover both — or block UDP/443 outbound entirely.

5. **Rebrand drift is a real OSINT problem.** Workpuls → Insightful means searching for "Workpuls" in vulnerability databases or incident reports may miss recent issues. Always pivot from binary brand → owning company → current product name.

6. **No employer association captured = clean re-onboarding possible.** Confirming, via Preferences and Cookies inspection, that no employer binding exists means a future re-install can be done correctly with no stale identity baggage.

7. **BYOD requires choosing your isolation layer in advance.** The right time to set up firejail / VMs / sandboxing is **before** the work agent is reinstalled, not after. Otherwise the agent has a window of unconstrained access on first run.

---

## Future Work

- [ ] Stand up a firejail profile for Insightful with the network whitelist documented above
- [ ] Verify the firejail profile catches outbound QUIC (UDP/443) attempts to non-whitelisted hosts
- [ ] Decide on a "work directory" convention (`~/Documents/Work/`) that is the agent's only writable area outside its own config
- [ ] Document the employer onboarding flow once it occurs (where the registration token goes, whether it lives in `Preferences` or a separate file) and capture that artifact for future reference

---

**Total time:** ~10 minutes of triage + write-up
**Result:** Full removal verified; re-installation plan with sandboxing documented; forensic artifacts catalogued for future reference.
