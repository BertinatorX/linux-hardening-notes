# Resume from s2idle hard-freezes — AiStone X4SP4NAL (Ryzen AI 300, "STX\KRK") — broken LPS0 `\_SB.PEP._DSM`

**Filed:** Kernel Bugzilla — https://bugzilla.kernel.org/show_bug.cgi?id=221664 (2026-06-19). Not cross-posted to the CachyOS forum — an existing thread already reports the same s2idle/LPS0 issue on this hardware, so a duplicate was avoided.

## System
- **Machine:** AiStone X4SP4NAL (board AiStone X4SP4NAL), `product_family = STX\KRK` (AMD Ryzen AI 300 / Strix–Krackan Point)
- **BIOS:** American Megatrends `N.1.20PCS09`, 2025-09-29
- **GPU:** AMD Radeon 880M/890M iGPU `[1002:150e] rev c1` (RDNA 3.5), `amdgpu`; NPU `amdxdna`
- **Kernel:** `linux-cachyos 7.0.12` (also reproducible to test on stock `linux 7.0.12.arch1-1`)
- **Distro:** CachyOS (Arch), KDE Plasma 6.6.5
- **Sleep:** `/sys/power/mem_sleep = [s2idle]` (no S3); `amd_pmc` loaded; `linux-firmware/amd-ucode = 20260519` (current)

## Symptom
Resume from s2idle **hard-hangs** (black screen, requires forced power-off). `/sys/power/suspend_stats/total_hw_sleep = 0` and `last_hw_sleep = 0` — the platform never reaches real S0ix. Journal shows `PM: suspend entry (s2idle)` with **no** matching `PM: suspend exit`, followed by a forced reboot. `amdgpu` logs no errors.

## Smoking-gun firmware error (on resume)
```
ACPI BIOS Error (bug): Could not resolve symbol [\_SB.ACDC.RTAC], AE_NOT_FOUND (.../psargs-332)
ACPI Error: Aborting method \_SB.PEP._DSM due to previous error (AE_NOT_FOUND) (.../psparse-531)
ACPI: \_SB_.PEP_: Failed to transitioned to state screen on
```
i.e. the LPS0/uPEP `_DSM` method the s0i3 handshake relies on is broken in the DSDT (references a non-existent `\_SB.ACDC.RTAC`).

## Other DSDT errors (every boot)
```
ACPI BIOS Error: Failure creating named object [\_SB.PCI0.GPPC.XHC0.RHUB.PRT5._PRR], AE_ALREADY_EXISTS
ACPI BIOS Error: Failure creating named object [\_SB.PCI0.GPP5.WLAN._DSM], AE_ALREADY_EXISTS
ACPI BIOS Error: Could not resolve symbol [\_SB.PCI0.SBRG.EC0._REG.DPMF], AE_NOT_FOUND
```

## Bisection that localizes it to the amd_pmc/s0i3 handshake
Per docs.kernel.org/arch/x86/amd-debugging.html, unbinding `amd_pmc` (so the platform is never told to start s0i3) makes suspend/resume **succeed**:
```
echo AMDI000A:00 > /sys/bus/platform/drivers/amd_pmc/unbind
systemctl suspend      # resumes cleanly; suspend_stats/success increments 0 -> 1
```
With `amd_pmc` bound (normal), the kernel drives the broken `\_SB.PEP._DSM` and freezes on resume.

## amd-s2idle report confirms (full report attached: amd-s2idle-report.txt)
- ✅ ACPI FADT supports Low-power S0 idle · ✅ LPS0 `_DSM` enabled (Microsoft uPEP GUID)
- `amd_pmc` loaded — SMC program 11, firmware `93.13.0`; VBIOS `113-STRIXEMU-001`
- Cycle result: **"Did not reach hardware sleep state."** The `\_SB.PEP._DSM` → `\_SB.ACDC.RTAC` `AE_NOT_FOUND` abort fires even on a *survivable* shallow cycle (captured here with `amd_pmc` unbound via `--logind`), i.e. the broken method is invoked unconditionally during LPS0 entry/exit; with `amd_pmc` bound it takes the box down on resume.

## Request
A DMI quirk / firmware-presence check to avoid driving the broken LPS0 `\_SB.PEP._DSM` handshake on this board (or guidance). Full `amd-s2idle` report attached; can also provide `journalctl -b -1 -k` from a real failed (`amd_pmc`-bound) cycle on request.
