# Proving an AMD s2idle Freeze Is Firmware, Not a Kernel Regression — Working the Bug Upstream

**Date:** 2026-07 (follow-on to the 2026-06-17 root-cause case study)
**System:** Arch/CachyOS · AiStone X4SP4NAL (TongFang GX4) · AMD Ryzen AI 9 HX 370 (Strix Point) · Radeon 890M · LUKS-encrypted Btrfs root
**Subject:** After root-causing the resume freeze and filing it upstream, an AMD maintainer engaged — this documents the structured testing that answered his questions
**Author:** Alberto R. (BertinatorX)
**Skills demonstrated:** kernel regression bracketing, controlled A/B test design, reading `System.map` to reason about which commits are present, writing a guarded self-verifying test harness, firmware/vendor research, disciplined no-overclaim communication with an upstream maintainer

> Background: the [2026-06-17 case study](amd-s2idle-resume-freeze-2026-06-17.md) traced this laptop's hard-freeze-on-resume to a broken platform ACPI method — `\_SB.PEP._DSM` referencing a non-existent `\_SB.ACDC.RTAC` — plus a USB-C (UBTC/UCSI) `Notify 0x80` storm, and shipped an `amd_pmc`-unbind `systemd-sleep` hook as the working mitigation. The bug was filed on kernel Bugzilla (#221664). This follow-up is what happened when AMD's s2idle maintainer picked it up.

---

## The question the maintainer asked

The upstream maintainer's first move was the right one: **is this a regression?** If a recent kernel broke something that used to work, that's a bisectable kernel bug. If every kernel behaves the same way, the problem lives below the kernel — in firmware — and the fix is a quirk or a BIOS update, not a code bisect.

Answering that cleanly meant testing across kernel versions under the *exact* condition that triggers the freeze, and being rigorous about not fooling myself.

## Test design: make the failure honest

The trap here is subtle. The mitigation hook unbinds `amd_pmc` at suspend time, which *prevents* the freeze. So any test with the hook active would "pass" on every kernel and produce a false negative. The whole point was to test with `amd_pmc` **bound** — i.e. to deliberately reproduce the hang.

I wrote a small test harness with four guards that refuse to run an invalid test:

1. **Right kernel** — abort if booted into the daily-driver kernel instead of the version under test.
2. **Exactly one variable** — abort if the intended kernel flag isn't on `/proc/cmdline` (or if two are).
3. **`amd_pmc` bound** — abort if the driver is unbound (the mitigation would mask the result).
4. **Hook disabled** — abort if the `systemd-sleep` workaround is still executable.

It then quiesces background services, arms a 45-second `rtcwake`, records `last_hw_sleep` / `total_hw_sleep` before and after, and — critically — **persists the pre-suspend state to disk before suspending**, because the expected outcome is a hard hang requiring a forced power-off. If only the "SUSPENDING" line survives the reset, that *is* the data point: the machine never came back.

```text
=== IOMMU hw-sleep test: 7.1.3 + amd_iommu=off ===
pre : last_hw_sleep=0  total_hw_sleep=0
status: SUSPENDING   <-- only this line survived the forced power-off => resume hung
```

A guard-railed test you can't accidentally run wrong is worth more than a careful test you run by hand — I'd already been burned once by a run where the hook silently unbound the driver mid-suspend and turned a real test into a shallow "pass."

## The kernel bracket

Each version was tested with `amd_pmc` bound and the mitigation disabled. Booting a specific kernel on a LUKS root meant confirming the initramfs still carried the `encrypt` hook and keyfile each time — a kernel swap that broke auto-unlock would have been a self-inflicted lockout.

| Kernel | Result |
|---|---|
| `7.0.12` | Hard hang on resume — forced power-off |
| `6.19.14` | Hard hang on resume — forced power-off |
| `6.18.x LTS` | Hard hang on resume — forced power-off |

**All three hang identically.** For the 6.19 test I also checked the on-disk `System.map` and confirmed the embedded-controller platform-driver rework from the 7.0 cycle was **absent** from 6.19 — so that commit couldn't be the cause, yet the machine still hung. The bug predates the window a bisect could have covered.

Conclusion: **not a regression.** Every kernel is affected the same way, which points squarely back at the firmware defect already documented.

## Ruling out IOMMU/DMA

The maintainer's next suggestion was to go back to a mainline kernel and try two IOMMU options separately — a common lever for DMA-related suspend hangs:

| Boot flag (mainline `7.1.3`) | Result |
|---|---|
| `amd_iommu=off` | No change — hard hang on resume |
| `iommu=pt` | No change — briefly reached a frozen login screen, then wedged; never resumed |

Neither changed the behavior, so an IOMMU/DMA interaction is ruled out. (I set these up as clearly-labeled one-off GRUB entries cloned from the mainline boot entry, so the default boot was never at risk and any power-cycle landed back on the normal kernel.)

## The BIOS question

"Have you tried a BIOS update?" deserved a real answer, not a shrug. This laptop ships under a reseller badge, so the first task was identifying the actual platform: the DMI model **X4SP4NAL** is a TongFang **GX4** barebone, the same board sold as the XMG EVO 14 (E25), TUXEDO InfinityBook 14 Gen10 AMD, and PCSpecialist Lafité 14 AI. The installed BIOS is a PCSpecialist-suffixed build of TongFang base **N.1.20**.

Findings:
- The platform isn't on LVFS/`fwupd`, so no update path there.
- Across every reseller channel, the only build newer than mine is one same-base release whose changelog is "various minor bugfixes" — nothing about suspend, ACPI, or the EC.
- A user on the *same chassis* running that newer build still reports the identical s2idle hang.
- No post-`N.1.20` platform BIOS exists publicly.

And a firm decision on risk: **do not cross-flash another reseller's BIOS/EC package.** These builds pair BIOS and EC firmware and differ in DMI/EC configuration; a bad flash on this chassis has no software recovery path (SPI hardware programmer only). The payoff — a same-base build with no relevant changelog — did not come close to justifying a brick risk.

## Outcome and what it demonstrates

The evidence now forms a complete, consistent picture: a long-standing **platform-firmware defect**, reproducible across four kernel series, unaffected by IOMMU options, with no BIOS update that addresses it. It is not a kernel regression. The `amd_pmc`-unbind `systemd-sleep` hook remains the only working mitigation on any kernel, and the real fix path is a kernel-side DMI quirk for this board or a corrected platform BIOS.

The part I'm proudest of isn't any single test — it's the discipline around them:
- **Report behavior, not conclusions you can't back.** When a wedge stopped the journal from flushing per-cycle residency, I reported "it hung and required a forced power-off," not a hardware-sleep number I didn't actually capture.
- **Isolate one variable at a time**, with guards that make an invalid run impossible.
- **Protect the machine you're breaking on purpose** — persist results before the crash, keep a known-good default boot, verify LUKS survives every kernel swap, and check the filesystem after each forced reset.

Working a real bug with an upstream maintainer is as much about being a trustworthy data source as it is about the debugging itself.
