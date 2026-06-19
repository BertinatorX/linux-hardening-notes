> **STATUS (2026-06-19): NOT posted.** An existing CachyOS forum thread already reports the same s2idle/LPS0 freeze on this hardware, so this draft is kept for reference rather than filed as a duplicate. The canonical report is the kernel Bugzilla one: https://bugzilla.kernel.org/show_bug.cgi?id=221664

TITLE:
Resume from s2idle hard-freezes — AiStone X4SP4NAL (Ryzen AI 300 "Krackan Point") — broken LPS0 \_SB.PEP._DSM

BODY:
Posting in case it helps others with this whitebox, and to ask whether a kernel-side quirk is feasible.

**TL;DR:** On an AiStone X4SP4NAL (AMD Ryzen AI 300, `product_family = STX\KRK`, Radeon 880M/890M), resume from s2idle **hard-freezes** (forced power-off). Root cause is a broken BIOS LPS0 method `\_SB.PEP._DSM` — it references a non-existent `\_SB.ACDC.RTAC`. Unbinding `amd_pmc` around suspend reliably works around it.

## System
- **Machine:** AiStone X4SP4NAL · `product_family = STX\KRK` (Ryzen AI 300 / Krackan–Strix Point)
- **BIOS:** AMI `N.1.20PCS09`, 2025-09-29
- **GPU:** Radeon 880M/890M `[1002:150e] rev c1` (RDNA 3.5), `amdgpu`; NPU `amdxdna`
- **Kernel:** `linux-cachyos 7.0.12` (also present: stock `linux 7.0.12.arch1-1`)
- **Sleep:** `/sys/power/mem_sleep = [s2idle]` (no S3); `amd_pmc` loaded; `linux-firmware`/`amd-ucode = 20260519`

## Symptom
Resume hard-hangs (black screen → forced power-off). `/sys/power/suspend_stats/total_hw_sleep = 0` (never reaches real S0ix). Journal shows `PM: suspend entry (s2idle)` with **no** matching `PM: suspend exit`. `amdgpu` logs nothing.

## Smoking-gun firmware error (on resume)
```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.ACDC.RTAC], AE_NOT_FOUND (.../psargs-332)
ACPI Error: Aborting method \_SB.PEP._DSM due to previous error (AE_NOT_FOUND) (.../psparse-531)
ACPI: \_SB_.PEP_: Failed to transitioned to state screen on
```

## Other DSDT errors (every boot)
```
ACPI BIOS Error: Failure creating named object [\_SB.PCI0.GPPC.XHC0.RHUB.PRT5._PRR], AE_ALREADY_EXISTS
ACPI BIOS Error: Failure creating named object [\_SB.PCI0.GPP5.WLAN._DSM], AE_ALREADY_EXISTS
ACPI BIOS Error: Could not resolve symbol [\_SB.PCI0.SBRG.EC0._REG.DPMF], AE_NOT_FOUND
```

## Bisection (localizes it to the amd_pmc / s0i3 handshake)
Per the kernel AMD-debugging guide, unbinding `amd_pmc` so the platform is never told to start s0i3 makes suspend/resume **succeed**:
```
echo AMDI000A:00 > /sys/bus/platform/drivers/amd_pmc/unbind
systemctl suspend     # resumes cleanly; suspend_stats/success goes 0 -> 1
```
With `amd_pmc` bound (normal), the kernel drives the broken `\_SB.PEP._DSM` and freezes on resume.

## Workaround I'm currently using
A `systemd-sleep` hook (`/usr/lib/systemd/system-sleep/`) that on `pre` does `echo AMDI000A:00 > /sys/bus/platform/drivers/amd_pmc/unbind` and disables i8042 keyboard wake (the flaky EC spurious-wakes in <1s), and on `post` rebinds + re-enables. Result: a shallow s2idle that resumes reliably. Tradeoffs: no deep s0i3 (higher idle drain), and wake is via power button / lid, not a keypress.

## Asks
- Is a DMI quirk / firmware-presence check feasible to avoid driving the broken LPS0 handshake on this board?
- Anyone else on `STX\KRK` whitebox boards seeing this? Any BIOS with a fix?

Happy to test patches and attach a full `amd-s2idle` report + `journalctl -b -1 -k` from a failed cycle.
