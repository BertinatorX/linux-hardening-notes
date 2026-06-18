# Diagnosing an AMD s2idle Resume Hard-Freeze Down to a Single Broken ACPI Method

**Date:** 2026-06-17
**System:** CachyOS (Arch-based) · kernel `linux-cachyos 7.0.12` · AiStone X4SP4NAL (TongFang GX4) · AMD Ryzen AI 9 HX 370 (Strix/Krackan Point) · LUKS-encrypted Btrfs root
**Subject:** Laptop hard-freezes on resume from suspend; forced power-off was the only recovery
**Author:** Alberto R. (BertinatorX)
**Skills demonstrated:** systemd-journald forensics, AMD `amd_pmc`/s0i3 driver bisection, ACPI/DSDT defect reading, kernel-doc-driven debugging, building a verified `systemd-sleep` workaround, upstream bug reporting with `amd-s2idle`

---

## Problem

Every suspend ended the same way: screen black on resume, machine fully unresponsive, only a forced power-off recovered it. On a LUKS/Btrfs root each hard reset risks filesystem damage, so this was the highest-priority stability issue on the box. As a stopgap I had disabled all automatic suspend, lid actions, and the screen locker — i.e. I'd given up on sleep entirely.

The boot journal also carried four `Failed to find module` errors and a cluster of ACPI BIOS errors, but those turned out to be separate (stale VirtualBox/`acpi_call` module-load entries) and were cleaned up independently.

## First reading: this is the platform, not the desktop

```bash
cat /sys/power/mem_sleep                    # [s2idle]  — no S3/deep, modern-standby only
cat /sys/power/suspend_stats/total_hw_sleep # 0         — never reached real hardware S0ix
journalctl -k | grep -i 'PM: suspend'
#  PM: suspend entry (s2idle)   <-- with NO matching "PM: suspend exit", then a forced reboot
```

Two facts framed everything:

1. **`total_hw_sleep = 0`** — even when it "slept," the platform never entered the hardware low-power state.
2. **`suspend entry` with no `suspend exit`** — the kernel hung on the suspend/resume path itself, hard enough that nothing more reached the journal. `amdgpu` logged *zero* errors, which rules a display-driver fault out: a GPU bug leaves a trail; a platform hard-hang leaves silence.

`/proc/acpi/wakeup` showed every USB/USB4 controller and the WLAN armed as wake sources, and the DSDT threw errors on a USB port (`XHC0.RHUB.PRT5._PRR`) and the embedded controller (`EC0._REG.DPMF`) on every boot — all subsystems involved in s2idle.

## Bisection: the kernel's own method

The kernel AMD-debugging guide (docs.kernel.org/arch/x86/amd-debugging.html) prescribes the decisive test: unbind `amd_pmc` so the kernel never tells the platform to start s0i3, which prevents the freeze and lets you read what failed.

```bash
echo AMDI000A:00 | sudo tee /sys/bus/platform/drivers/amd_pmc/unbind
sudo systemctl suspend     # resumes cleanly; suspend_stats/success goes 0 -> 1
```

It resumed. With `amd_pmc` bound (normal operation) the box freezes; with it unbound it survives. That localizes the fault to the **`amd_pmc` / s0i3 firmware handshake**, not the generic device-suspend path.

## Root cause: a broken LPS0 `_DSM` in the firmware

Capturing the resume-side journal exposed the smoking gun:

```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.ACDC.RTAC], AE_NOT_FOUND
ACPI Error: Aborting method \_SB.PEP._DSM due to previous error (AE_NOT_FOUND)
ACPI: \_SB_.PEP_: Failed to transitioned to state screen on
```

`\_SB.PEP._DSM` is the Power-Engine-Plugin / **LPS0 "low-power S0 idle" method** — the exact ACPI interface `amd_pmc` drives to arm hardware s0i3. This board's AMI firmware ships it broken: it calls `\_SB.ACDC.RTAC`, an object that does not exist in the DSDT. So when `amd_pmc` drives the s0i3 handshake through that broken method, the resume hangs.

**This is a firmware/DSDT defect, not a Linux bug.** It is consistent with every other clue: `total_hw_sleep = 0`, no amdgpu errors, and the EC/USB DSDT errors in the same tables.

## The workaround: unbind `amd_pmc` around every suspend

Since the broken method is only driven when `amd_pmc` is bound, the fix is to unbind it for the duration of the suspend. A second, separate bug surfaced during validation: the i8042 keyboard controller (IRQ 1) spurious-wakes the machine in ~0.4 s, so a hands-off test never *held* — that wake source also has to be gated.

`/usr/lib/systemd/system-sleep/50-amd-pmc-workaround`:

```sh
#!/bin/sh
PMC=AMDI000A:00
KBD=/sys/devices/platform/i8042/serio0/power/wakeup
case "$1" in
  pre)
    echo "$PMC"   > /sys/bus/platform/drivers/amd_pmc/unbind 2>/dev/null
    echo disabled > "$KBD" 2>/dev/null
    ;;
  post)
    echo "$PMC"  > /sys/bus/platform/drivers/amd_pmc/bind 2>/dev/null
    echo enabled > "$KBD" 2>/dev/null
    ;;
esac
exit 0
```

This applies to **every** suspend path that goes through logind (lid close, menu, idle auto-suspend), because they all run `systemd-sleep` hooks.

### Verification

A real `systemctl suspend` (the same route lid/menu/auto-suspend use) was logged end-to-end:

```
amd-pmc-workaround: pre suspend: amd_pmc unbound, i8042 keyboard wake disabled
PM: suspend entry (s2idle)
Timekeeping suspended for 35.999 seconds      <-- held the full window
PM: Triggering wakeup from IRQ 9              <-- woke from the RTC alarm, not the keyboard
PM: suspend exit
amd-pmc-workaround: post suspend: amd_pmc rebound, i8042 keyboard wake enabled
```

`suspend_stats/success` incremented across repeated cycles. The `\_SB.PEP._DSM` error still logs on resume but is now harmless — the machine comes back.

**Tradeoffs (honest scope):** this is a shallow s2idle. It resumes reliably but does not reach deep hardware S0ix, so idle-in-suspend power draw is higher (closer to screen-off than true sleep), and the machine must be woken with the power button or lid, not a keypress. It is a stopgap until a fixed BIOS or an upstream DMI quirk lands.

## Upstream reporting

To make the report actionable rather than a generic "my laptop won't resume," I captured the official AMD diagnostic **without a deliberate freeze**: install `amd-debug-tools`, then run `amd-s2idle test --logind` so the cycle routes through the workaround hook (resumes cleanly) while the tool still collects the full FADT/LPS0 flags, the broken `_DSM`, ACPI tables, and firmware versions.

- Kernel Bugzilla (Drivers → Power-Management), CC the `amd_pmc` maintainer, with the `amd-s2idle` report attached.
- CachyOS forum thread for community visibility and other TongFang GX4 owners.

## Lessons Learned (Generalizable)

1. **`total_hw_sleep = 0` + `entry`-without-`exit` is a platform/firmware signature, not a driver one.** A driver crash leaves errors; a firmware hard-hang leaves silence. Read the *absence* of logs as evidence.
2. **The `amd_pmc` unbind is the single highest-value AMD s2idle diagnostic.** It converts an un-debuggable hard freeze into a survivable cycle whose failure you can read.
3. **ACPI `AE_NOT_FOUND` on a `_DSM` is a real firmware defect.** `\_SB.PEP._DSM` failing because it references a non-existent symbol means the s0i3 handshake is broken in the BIOS, not in Linux.
4. **One symptom can hide two bugs.** The freeze (firmware s0i3) and the instant spurious wake (i8042 EC) were independent; the workaround needed to address both.
5. **`systemd-sleep` hooks are the right layer for a per-suspend workaround** — they fire for every logind suspend path, so the fix is uniform across lid/menu/auto-suspend.
6. **Capture upstream diagnostics the cheap way.** Routing `amd-s2idle test` through the workaround via `--logind` gets the full firmware report with no extra hard reset.

## Files Created

- `/usr/lib/systemd/system-sleep/50-amd-pmc-workaround` — the suspend hook (source staged at `~/amd-pmc-suspend-workaround.sh`)
- `~/suspend-debug.sh` — staged diagnostic harness (`baseline | pmc-test | validate | hook-test | after-hang | restore`)
- `~/amd-s2idle-report.txt` — full `amd-s2idle` capture (Bugzilla attachment)
- `~/strix-s2idle-bugreport.md`, `~/strix-s2idle-forumpost.md` — upstream report drafts

## Future Work

- [ ] File the Bugzilla + CachyOS reports; track whether a DMI quirk is accepted upstream
- [ ] Re-check for a TongFang/AMI BIOS newer than `N.1.20PCS09` (2025-09-29); a fixed DSDT removes the need for the workaround and restores deep S0ix
- [ ] Re-test on the stock `linux` kernel to confirm the behavior is not CachyOS-patch-specific
