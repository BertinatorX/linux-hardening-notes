# LUKS and LVM Resize Recovery Notes

## Goal

Document the high-level process used to reclaim unused NVMe storage and expand an encrypted Linux installation using LUKS and LVM.

## Safety warning

Partition, encryption, and filesystem changes can cause data loss. These notes are for personal lab documentation. Always back up important data before attempting similar work.

## Scenario

Unused storage existed on the NVMe drive and needed to be added to the encrypted Linux environment.

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

## Example command categories

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

## Troubleshooting note

During this process, filesystem resizing required a forced filesystem check with `e2fsck -f` before `resize2fs` would proceed. This was a useful reminder that filesystem tools may stop an operation until integrity checks are completed.

## What I learned

Encrypted storage expansion is a multi-layer process. The partition, LUKS container, LVM physical volume, logical volume, and filesystem each need to be handled in the correct order.
