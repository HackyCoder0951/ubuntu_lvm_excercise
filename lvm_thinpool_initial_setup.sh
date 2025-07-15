#!/bin/bash

set -e

# ========== CONFIGURATION ==========
DISK="/dev/sdb"
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
METADATA_LV="thinmeta"
THIN_LV="lvdata"
THIN_LV_SIZE="40T"
MOUNT_POINT="/data"
FS_TYPE="ext4"
# ===================================

# === Cleanup Phase ===
echo "🧼 Cleaning up previous setup on $DISK..."

umount "$MOUNT_POINT" 2>/dev/null || true
umount "${DISK}1" 2>/dev/null || true
fuser -vk "$DISK" 2>/dev/null || true
fuser -vk "${DISK}1" 2>/dev/null || true

lvremove -fy "$VG_NAME" 2>/dev/null || true
vgremove -fy "$VG_NAME" 2>/dev/null || true
pvremove -ff -y "${DISK}1" 2>/dev/null || true

echo "🧽 Wiping filesystems and partition table..."
wipefs -a "$DISK" || true
dd if=/dev/zero of="$DISK" bs=512 count=10000 status=none || true
partprobe "$DISK" || echo "⚠️ Could not refresh partition table. Reboot may be needed."

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

# 5. Calculate thin pool size (leave 1GB headroom)
FREE_SIZE=$(vgs "$VG_NAME" --units m --noheadings -o vg_free | tr -d '[:space:]' | sed 's/m//' | awk '{printf("%d", $1)}')
THINPOOL_SIZE_MB=$((FREE_SIZE - 1024))

if (( THINPOOL_SIZE_MB <= 0 )); then
  echo "❌ Not enough space to create thin pool. Only ${FREE_SIZE}MB free."
  exit 1
fi

echo "🧮 Free VG space: ${FREE_SIZE}MB, using ${THINPOOL_SIZE_MB}MB for thin pool."

# 6. Create thin pool LV
lvcreate -L "${THINPOOL_SIZE_MB}M" -n "$THINPOOL_NAME" "$VG_NAME"

# 7. Convert to thin pool with chunk size
lvconvert --chunksize 512K --type thin-pool --poolmetadata "${VG_NAME}/${METADATA_LV}" "${VG_NAME}/${THINPOOL_NAME}"

# 8. Enable auto-extend
lvchange --metadataprofile thin-performance "${VG_NAME}/${THINPOOL_NAME}" || true
lvs --segments -o+seg_monitor

# 9. Create 40TB thin-provisioned LV
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
