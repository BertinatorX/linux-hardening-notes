# Proving an AMD s2idle Freeze Is Firmware, Not a Kernel Regression: Working the Bug Upstream

**Date:** 2026-07 (follow-on to the 2026-06-17 root-cause case study)
**System:** Arch/CachyOS · AiStone X4SP4NAL (TongFang GX4) · AMD Ryzen AI 9 HX 370 (Strix Point) · Radeon 890M · LUKS-encrypted Btrfs root
**Subject:** After root-causing the resume freeze and filing it upstream, an AMD maintainer engaged; this is the structured testing that answered his questions
**Author:** Alberto R. (BertinatorX)
**Skills demonstrated:** kernel regression bracketing, controlled A/B test design, reading `System.map` to reason about which commits are present, writing a guarded self-verifying test harness, firmware/vendor research, disciplined no-overclaim communication with an upstream maintainer

> Background: the [2026-06-17 case study](amd-s2idle-resume-freeze-2026-06-17.md) traced this laptop's hard-freeze-on-resume to a broken platform ACPI method (`\_SB.PEP._DSM` referencing a non-existent `\_SB.ACDC.RTAC`) plus a USB-C (UBTC/UCSI) `Notify 0x80` storm, and shipped an `amd_pmc`-unbind `systemd-sleep` hook as the working mitigation. I filed the bug on kernel Bugzilla (#221664). This follow-up is what happened when AMD's s2idle maintainer picked it up.

---

## The question the maintainer asked

The maintainer's first move was the right one, he wanted to know whether this was a regression, and it's a fair question. If a recent kernel broke something that used to work, that's a bisectable kernel bug. If every kernel behaves the same way, the problem lives below the kernel, in firmware, and a bisect would find nothing, the fix would have to be a quirk or a BIOS update.

Answering that cleanly meant testing across kernel versions under the exact condition that triggers the freeze, and I had to be careful not to fool myself.

## Test design: make the failure honest

The trap here is easy to walk into. The mitigation hook unbinds `amd_pmc` at suspend time, and that unbind is what prevents the freeze, so any test with the hook active would "pass" on every kernel and hand me a false negative. The whole point was to test with `amd_pmc` bound, in other words to deliberately reproduce the hang.

I wrote a small test harness with four guards that refuse to run an invalid test:

1. Right kernel: abort if booted into the daily-driver kernel instead of the version under test.
2. Exactly one variable: abort if the intended kernel flag isn't on `/proc/cmdline` (or if two are).
3. `amd_pmc` bound: abort if the driver is unbound (the mitigation would mask the result).
4. Hook disabled: abort if the `systemd-sleep` workaround is still executable.

Once the guards pass, it quiesces background services, arms a 45-second `rtcwake`, records `last_hw_sleep` / `total_hw_sleep` before and after, and, the part I care about most, persists the pre-suspend state to disk before suspending, because the expected outcome is a hard hang that needs a forced power-off. If only the "SUSPENDING" line survives the reset, that is the data point, the machine never came back.

```text
=== IOMMU hw-sleep test: 7.1.3 + amd_iommu=off ===
pre : last_hw_sleep=0  total_hw_sleep=0
status: SUSPENDING   <-- only this line survived the forced power-off => resume hung
```

I put the guards in because I'd already been burned once, a run where the hook silently unbound the driver mid-suspend and turned a real test into a shallow "pass." I didn't trust myself to catch that by hand a second time, so I made the script catch it for me, which is also an easier thing to tell a maintainer than "I was careful."

## The kernel bracket

I tested each version with `amd_pmc` bound and the mitigation disabled. Booting a specific kernel on a LUKS root meant confirming the initramfs still carried the `encrypt` hook and keyfile each time, because a kernel swap that broke auto-unlock would have been a lockout I did to myself.

| Kernel | Result |
|---|---|
| `7.0.12` | Hard hang on resume, forced power-off |
| `6.19.14` | Hard hang on resume, forced power-off |
| `6.18.x LTS` | Hard hang on resume, forced power-off |

All three hang identically. For the 6.19 test I also checked the on-disk `System.map` and confirmed the embedded-controller platform-driver rework from the 7.0 cycle was absent from 6.19, so that commit couldn't be the cause, yet the machine still hung. The bug predates the window a bisect could have covered.

So my answer to the maintainer was no, this isn't a regression. Every kernel I tried hangs the same way, which points straight back at the firmware defect I'd already documented in the first case study.

## Ruling out IOMMU/DMA

The maintainer's next suggestion was to go back to a mainline kernel and try two IOMMU options separately, since that's a common lever for DMA-related suspend hangs:

| Boot flag (mainline `7.1.3`) | Result |
|---|---|
| `amd_iommu=off` | No change, hard hang on resume |
| `iommu=pt` | No change; briefly reached a frozen login screen, then wedged, never resumed |

Neither one changed the behavior, so I could rule out an IOMMU/DMA interaction. I set these up as clearly-labeled one-off GRUB entries cloned from the mainline boot entry, so the default boot was never at risk and any power-cycle landed me back on the normal kernel.

## The BIOS question

The maintainer also asked whether I'd tried a BIOS update, and I didn't want to answer that with a shrug. This laptop ships under a reseller badge, so the first job was figuring out what the platform actually is: the DMI model X4SP4NAL is a TongFang GX4 barebone, the same board sold as the XMG EVO 14 (E25), TUXEDO InfinityBook 14 Gen10 AMD, and PCSpecialist Lafité 14 AI. The installed BIOS is a PCSpecialist-suffixed build of TongFang base N.1.20.

What I found:
- The platform isn't on LVFS/`fwupd`, so no update path there.
- Across every reseller channel, the only build newer than mine is one same-base release whose changelog just says "various minor bugfixes" and nothing about suspend, ACPI, or the EC.
- A user on the same chassis running that newer build still reports the identical s2idle hang.
- No post-`N.1.20` platform BIOS exists publicly.

The one thing I decided firmly was not to cross-flash another reseller's BIOS/EC package. These builds pair BIOS and EC firmware and differ in DMI/EC configuration, and a bad flash on this chassis has no software recovery path (SPI hardware programmer only). The payoff would have been a same-base build with no relevant changelog, which didn't come close to justifying a brick risk.

## Outcome and what it demonstrates

Putting it all together, what I've got is a long-standing platform-firmware defect. It reproduces across four kernel series and neither IOMMU option touched it, and on the firmware side there is no BIOS update that addresses it. It isn't a kernel regression. The `amd_pmc`-unbind `systemd-sleep` hook is still the only working mitigation on any kernel, and the real fix has to come from a kernel-side DMI quirk for this board or a corrected platform BIOS.

The thing I'd actually point to is how careful I was about the process, more than any single result. I only reported what I saw. When a wedge stopped the journal from flushing per-cycle residency, I told the maintainer "it hung and required a forced power-off" and left it at that, because I didn't actually capture a hardware-sleep number and I wasn't going to guess at one. I changed one variable at a time and let the guards refuse any run that wasn't set up right, which is the only reason I trust the tables above. And since I was crashing my own daily machine on purpose, I persisted results before each crash, kept a known-good default boot, checked that LUKS still unlocked after every kernel swap, and ran a filesystem check after each forced reset.

Overall I'm happy with how this went, the maintainer got straight answers to all three of his questions and I don't think I overclaimed anything, but the laptop still needs the hook on every kernel and the actual fix is out of my hands until either a DMI quirk lands upstream or a corrected platform BIOS shows up.
