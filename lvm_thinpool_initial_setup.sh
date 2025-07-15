#!/bin/bash

set -e

# ========== CONFIGURATION ==========
DISK="/dev/sdb"            # Target disk
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
METADATA_LV="thinmeta"
THIN_LV="lvdata"
THIN_LV_SIZE="40T"         # 40TB virtual size
MOUNT_POINT="/data"
FS_TYPE="ext4"             # ext4 or xfs
# ===================================

# ==== Clean up if /dev/sdb or /dev/sdb1 already in use ====
echo "🔍 Checking if /dev/sdb is already used..."

if pvs | grep -q "/dev/sdb"; then
  echo "⚠️ Detected existing LVM configuration on /dev/sdb. Cleaning it up..."

  # Unmount if mounted
  umount "$MOUNT_POINT" 2>/dev/null || true

  # Remove VG, LVs
  VG_EXIST=$(pvs --noheadings -o vg_name /dev/sdb | awk '{print $1}')
  if [ -n "$VG_EXIST" ]; then
    echo "💣 Removing Volume Group: $VG_EXIST"
    lvremove -fy "$VG_EXIST" 2>/dev/null || true
    vgremove -fy "$VG_EXIST" 2>/dev/null || true
  fi

  echo "🧹 Removing PV from /dev/sdb"
  pvremove -ff -y /dev/sdb 2>/dev/null || true
fi

# Remove /dev/sdb1 if it exists
if lsblk /dev/sdb1 &>/dev/null; then
  echo "🧽 Wiping /dev/sdb1..."
  umount /dev/sdb1 2>/dev/null || true
  wipefs -a /dev/sdb1 || true
fi

# Full disk wipe
echo "🚫 Wiping partition table on /dev/sdb..."
wipefs -a /dev/sdb
dd if=/dev/zero of=/dev/sdb bs=512 count=10000 status=none
partprobe /dev/sdb || echo "⚠️ Could not re-read partition table. A reboot may be required."

# === Dependency Check ===
echo "🔎 Checking required commands..."
for cmd in pvcreate vgcreate lvcreate lvconvert mkfs.ext4 mount parted vgs; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command '$cmd' not found:"
    echo "    sudo apt update && sudo apt install -y lvm2 parted"
    exit 1
  fi
done

# 1. Partition the disk
echo "📦 Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -a optimal "$DISK" mkpart primary 0% 100%
PART="${DISK}1"
sleep 2
partprobe "$DISK"

# 2. Create PV
pvcreate "$PART"

# 3. Create VG
vgcreate "$VG_NAME" "$PART"

# 4. Create Metadata LV
lvcreate -L 1G -n "$METADATA_LV" "$VG_NAME"

# 5. Calculate thin pool size (leave 128MB)
FREE_SIZE=$(vgs "$VG_NAME" --units m --noheadings -o vg_free | tr -d '[:space:]' | sed 's/m//' | awk '{printf("%d", $1)}')
THINPOOL_SIZE_MB=$((FREE_SIZE - 128))

if (( THINPOOL_SIZE_MB <= 0 )); then
  echo "❌ Not enough space to create thin pool. Only ${FREE_SIZE}MB free."
  exit 1
fi

echo "🧮 Free VG space: ${FREE_SIZE}MB, using ${THINPOOL_SIZE_MB}MB for thin pool."

# 6. Create thin pool LV
lvcreate -L "${THINPOOL_SIZE_MB}M" -n "$THINPOOL_NAME" "$VG_NAME"

# 7. Convert to thin pool
lvconvert --type thin-pool --poolmetadata "${VG_NAME}/${METADATA_LV}" "${VG_NAME}/${THINPOOL_NAME}"

# 8. Enable auto-extend
lvchange --metadataprofile thin-performance "${VG_NAME}/${THINPOOL_NAME}" || true
lvs --segments -o+seg_monitor

# 9. Create 40TB thin LV
lvcreate -V "$THIN_LV_SIZE" --thinpool "$THINPOOL_NAME" -n "$THIN_LV" "$VG_NAME"

# 10. Format the LV
echo "🧷 Formatting LV with $FS_TYPE..."
if [ "$FS_TYPE" == "ext4" ]; then
    mkfs.ext4 "/dev/${VG_NAME}/${THIN_LV}"
elif [ "$FS_TYPE" == "xfs" ]; then
    mkfs.xfs "/dev/${VG_NAME}/${THIN_LV}"
else
    echo "❌ Unsupported filesystem: $FS_TYPE"
    exit 1
fi

# 11. Mount
mkdir -p "$MOUNT_POINT"
mount "/dev/${VG_NAME}/${THIN_LV}" "$MOUNT_POINT"

# 12. Update fstab
if ! grep -qs "$MOUNT_POINT" /etc/fstab; then
  echo "/dev/${VG_NAME}/${THIN_LV} $MOUNT_POINT $FS_TYPE defaults 0 2" >> /etc/fstab
fi

echo "✅ 40TB thin-provisioned volume is ready and mounted at $MOUNT_POINT"
