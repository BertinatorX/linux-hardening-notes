# Diagnosing an AMD s2idle Resume Hard-Freeze Down to a Single Broken ACPI Method

**Date:** 2026-06-17
**System:** CachyOS (Arch-based) · kernel `linux-cachyos 7.0.12` · AiStone X4SP4NAL (TongFang GX4) · AMD Ryzen AI 9 HX 370 (Strix/Krackan Point) · LUKS-encrypted Btrfs root
**Subject:** Laptop hard-freezes on resume from suspend; forced power-off was the only recovery
**Author:** Alberto R. (BertinatorX)
**Skills demonstrated:** systemd-journald forensics, AMD `amd_pmc`/s0i3 driver bisection, ACPI/DSDT defect reading, kernel-doc-driven debugging, building a verified `systemd-sleep` workaround, upstream bug reporting with `amd-s2idle`

---

## Problem

Every suspend ended the same way, screen black on resume, machine completely unresponsive, and the only way out was a forced power-off. On a LUKS/Btrfs root every one of those hard resets is a chance to damage the filesystem, so this was the number one stability problem on the box. My stopgap up to this point had been to turn off all automatic suspend, the lid actions, and the screen locker, which is another way of saying I'd given up on sleep entirely.

The boot journal also had four `Failed to find module` errors and a cluster of ACPI BIOS errors in it, but those turned out to be a separate problem (stale VirtualBox/`acpi_call` module-load entries) and I cleaned them up on their own.

## First reading: this is the platform, not the desktop

```bash
cat /sys/power/mem_sleep                    # [s2idle]  — no S3/deep, modern-standby only
cat /sys/power/suspend_stats/total_hw_sleep # 0         — never reached real hardware S0ix
journalctl -k | grep -i 'PM: suspend'
#  PM: suspend entry (s2idle)   <-- with NO matching "PM: suspend exit", then a forced reboot
```

Two facts framed everything after this:

1. `total_hw_sleep = 0`: even when the laptop "slept," the platform never once reached the hardware low-power state.
2. `suspend entry` with no `suspend exit`: the kernel hung on the suspend/resume path itself, and hung hard enough that nothing else made it into the journal. `amdgpu` logged *zero* errors, and that rules a display-driver fault out: a GPU bug leaves a trail, a platform hard-hang leaves silence.

`/proc/acpi/wakeup` showed every USB/USB4 controller and the WLAN armed as wake sources, and the DSDT threw errors on a USB port (`XHC0.RHUB.PRT5._PRR`) and on the embedded controller (`EC0._REG.DPMF`) on every single boot. All of those subsystems are involved in s2idle.

## Bisection: the kernel's own method

The kernel's own AMD-debugging guide (docs.kernel.org/arch/x86/amd-debugging.html) gives the one test that settles it: unbind `amd_pmc` so the kernel never tells the platform to start s0i3. That keeps the machine from freezing and lets you read what actually failed.

```bash
echo AMDI000A:00 | sudo tee /sys/bus/platform/drivers/amd_pmc/unbind
sudo systemctl suspend     # resumes cleanly; suspend_stats/success goes 0 -> 1
```

It resumed. With `amd_pmc` bound (normal operation) the box freezes, with it unbound it survives. That puts the fault in the `amd_pmc` / s0i3 firmware handshake and not in the generic device-suspend path.

## Root cause: a broken LPS0 `_DSM` in the firmware

Capturing the resume-side journal turned up the smoking gun:

```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.ACDC.RTAC], AE_NOT_FOUND
ACPI Error: Aborting method \_SB.PEP._DSM due to previous error (AE_NOT_FOUND)
ACPI: \_SB_.PEP_: Failed to transitioned to state screen on
```

`\_SB.PEP._DSM` is the Power-Engine-Plugin / LPS0 "low-power S0 idle" method, which is the exact ACPI interface `amd_pmc` drives to arm hardware s0i3. This board's AMI firmware ships it broken: it calls `\_SB.ACDC.RTAC`, an object that does not exist anywhere in the DSDT. So when `amd_pmc` runs the s0i3 handshake through that broken method, the resume hangs.

This is a firmware/DSDT defect, not a Linux bug. It lines up with every other clue I had: `total_hw_sleep = 0`, no amdgpu errors, and the EC/USB DSDT errors sitting in the same tables.

## The workaround: unbind `amd_pmc` around every suspend

The broken method only gets driven while `amd_pmc` is bound, so the fix is to unbind it for the length of the suspend. A second, separate bug showed up while I was validating this: the i8042 keyboard controller (IRQ 1) spurious-wakes the machine in ~0.4 s, so a hands-off test never *held*. That wake source has to be gated too.

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

This covers every suspend path that goes through logind (lid close, menu, idle auto-suspend), because all of them run the `systemd-sleep` hooks.

### Verification

I logged a real `systemctl suspend` (the same route lid/menu/auto-suspend take) end to end:

```
amd-pmc-workaround: pre suspend: amd_pmc unbound, i8042 keyboard wake disabled
PM: suspend entry (s2idle)
Timekeeping suspended for 35.999 seconds      <-- held the full window
PM: Triggering wakeup from IRQ 9              <-- woke from the RTC alarm, not the keyboard
PM: suspend exit
amd-pmc-workaround: post suspend: amd_pmc rebound, i8042 keyboard wake enabled
```

`suspend_stats/success` kept incrementing across repeated cycles. The `\_SB.PEP._DSM` error still logs on resume, but now it's harmless, the machine comes back.

Tradeoffs (honest scope): this is a shallow s2idle. It resumes reliably but it doesn't reach deep hardware S0ix, so idle-in-suspend power draw is higher (closer to screen-off than real sleep), and the machine has to be woken with the power button or the lid, not a keypress. It's a stopgap until a fixed BIOS or an upstream DMI quirk lands.

## Upstream reporting

I wanted the report to be something a maintainer could act on instead of a generic "my laptop won't resume," so I captured the official AMD diagnostic without a deliberate freeze: install `amd-debug-tools`, then run `amd-s2idle test --logind` so the cycle routes through the workaround hook (and resumes cleanly) while the tool still collects the full FADT/LPS0 flags, the broken `_DSM`, the ACPI tables, and the firmware versions.

- Kernel Bugzilla (Drivers → Power-Management), CC the `amd_pmc` maintainer, with the `amd-s2idle` report attached.
- CachyOS forum thread for community visibility and other TongFang GX4 owners.

## Lessons Learned (Generalizable)

1. `total_hw_sleep = 0` + `entry`-without-`exit` is a platform/firmware signature, not a driver one. A driver crash leaves errors, a firmware hard-hang leaves silence. Read the *absence* of logs as evidence.
2. The `amd_pmc` unbind is the single most useful AMD s2idle diagnostic there is. It turns a hard freeze you can't debug into a cycle you survive and whose failure you can actually read.
3. ACPI `AE_NOT_FOUND` on a `_DSM` is a real firmware defect. `\_SB.PEP._DSM` failing because it points at a symbol that doesn't exist means the s0i3 handshake is broken in the BIOS, not in Linux.
4. One symptom can hide two bugs. The freeze (firmware s0i3) and the instant spurious wake (i8042 EC) were independent of each other, and the workaround had to handle both.
5. `systemd-sleep` hooks are the right layer for a per-suspend workaround. They fire for every logind suspend path, so the fix is the same across lid/menu/auto-suspend.
6. Capture upstream diagnostics the cheap way. Routing `amd-s2idle test` through the workaround with `--logind` gets the full firmware report with no extra hard reset.

## Files Created

- `/usr/lib/systemd/system-sleep/50-amd-pmc-workaround`: the suspend hook (source staged at `~/amd-pmc-suspend-workaround.sh`)
- `~/suspend-debug.sh`: staged diagnostic harness (`baseline | pmc-test | validate | hook-test | after-hang | restore`)
- `~/amd-s2idle-report.txt`: the full `amd-s2idle` capture (Bugzilla attachment)
- `~/strix-s2idle-bugreport.md`, `~/strix-s2idle-forumpost.md`: upstream report drafts

## Future Work

- [ ] File the Bugzilla + CachyOS reports; track whether a DMI quirk is accepted upstream
- [ ] Re-check for a TongFang/AMI BIOS newer than `N.1.20PCS09` (2025-09-29); a fixed DSDT removes the need for the workaround and restores deep S0ix
- [ ] Re-test on the stock `linux` kernel to confirm the behavior is not CachyOS-patch-specific
