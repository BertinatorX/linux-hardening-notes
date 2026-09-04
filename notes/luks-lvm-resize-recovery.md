# LUKS and LVM Resize Recovery Notes

## Goal

Reclaim the unused NVMe space and grow the encrypted Linux install into it using LUKS and LVM. Kept high-level on purpose, the sequence is the useful part.

## Safety warning

Partition, encryption, and filesystem changes can wipe out your data. These are personal lab notes, so back up anything important before trying similar work.

## Scenario

Unused storage was sitting on the NVMe drive and I wanted it inside the encrypted Linux environment.

## High-level workflow

1. Boot from a live ISO.
2. Confirm the target disk and partitions.
3. Unlock the LUKS container.
4. Expand the partition boundary.
5. Resize the LUKS container.
6. Extend the LVM physical volume.
7. Extend the logical volume.
8. Check the filesystem.
9. Resize the filesystem.
10. Verify the final capacity.

## Example commands

Confirm layout:

```bash
lsblk
sudo fdisk -l
```

Unlock encrypted container:

```bash
sudo cryptsetup open /dev/<partition> <mapped-name>
```

Resize partition boundary:

```bash
sudo parted /dev/<disk>
```

Resize LUKS container:

```bash
sudo cryptsetup resize <mapped-name>
```

Resize LVM physical volume:

```bash
sudo pvresize /dev/mapper/<mapped-name>
```

Extend logical volume:

```bash
sudo lvextend -l +100%FREE /dev/<volume-group>/<logical-volume>
```

Check filesystem:

```bash
sudo e2fsck -f /dev/<volume-group>/<logical-volume>
```

Resize filesystem:

```bash
sudo resize2fs /dev/<volume-group>/<logical-volume>
```

Verify:

```bash
lsblk
df -h
```

## Troubleshooting

The snag was `resize2fs` refusing to run until I did a forced check with `e2fsck -f` first. Annoying, but it's the tool doing its job, filesystem tools may stop an operation until integrity checks are done, so I'd plan for that step next time.

## What I learned

Growing encrypted storage means going through every layer in turn. I count five: partition, LUKS container, LVM physical volume, logical volume, filesystem, each handled in the correct order. Overall none of the commands are hard, the order is what matters.
