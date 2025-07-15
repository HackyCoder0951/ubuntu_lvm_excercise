#!/bin/bash

set -e

# === Dependency Check ===
for cmd in pvcreate vgcreate lvcreate lvconvert mkfs.ext4 mount parted vgs; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command '$cmd' not found. Please install it first:"
    echo "    sudo apt update && sudo apt install -y lvm2 parted"
    exit 1
  fi
done

# ========== CONFIGURATION ==========
DISK="/dev/sdb"            # Physical disk
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
METADATA_LV="thinmeta"
THIN_LV="lvdata"
THIN_LV_SIZE="40T"         # 40TB virtual size
MOUNT_POINT="/data"
FS_TYPE="ext4"
# ===================================

echo "📦 Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -a optimal "$DISK" mkpart primary 0% 100%
PART="${DISK}1"
sleep 2
partprobe "$DISK" || echo "⚠️ Could not notify kernel. A reboot may be required."

# Cleanup if rerunning
umount "$MOUNT_POINT" 2>/dev/null || true
lvremove -fy "$VG_NAME/$THIN_LV" 2>/dev/null || true
lvremove -fy "$VG_NAME/$THINPOOL_NAME" 2>/dev/null || true
lvremove -fy "$VG_NAME/$METADATA_LV" 2>/dev/null || true
vgremove -fy "$VG_NAME" 2>/dev/null || true
pvremove -ff -y "$PART" 2>/dev/null || true

# 1. Create PV
pvcreate "$PART"

# 2. Create VG
vgcreate "$VG_NAME" "$PART"

# 3. Create Metadata LV
lvcreate -L 1G -n "$METADATA_LV" "$VG_NAME"

# 4. Create Thin Pool LV (leave 128MB for conversion)
FREE_SIZE=$(vgs "$VG_NAME" --units m --noheadings -o vg_free | tr -d '[:space:]' | sed 's/m//')
THINPOOL_SIZE_MB=$((FREE_SIZE - 128))

if (( THINPOOL_SIZE_MB <= 0 )); then
  echo "❌ Not enough space to create thin pool. Only ${FREE_SIZE}MB available."
  exit 1
fi

echo "🧮 Free space: ${FREE_SIZE}MB, allocating ${THINPOOL_SIZE_MB}MB to thin pool..."

lvcreate -L "${THINPOOL_SIZE_MB}M" -n "$THINPOOL_NAME" "$VG_NAME"

# 5. Convert to thin pool
lvconvert --type thin-pool --poolmetadata "${VG_NAME}/${METADATA_LV}" "${VG_NAME}/${THINPOOL_NAME}"

# 6. Enable auto-extend policy
lvchange --metadataprofile thin-performance "${VG_NAME}/${THINPOOL_NAME}" || true
lvs --segments -o+seg_monitor

# 7. Create 40TB virtual thin LV
lvcreate -V "$THIN_LV_SIZE" --thinpool "$THINPOOL_NAME" -n "$THIN_LV" "$VG_NAME"

# 8. Format the LV
echo "🧷 Formatting LV with $FS_TYPE..."
if [ "$FS_TYPE" == "ext4" ]; then
    mkfs.ext4 "/dev/${VG_NAME}/${THIN_LV}"
elif [ "$FS_TYPE" == "xfs" ]; then
    mkfs.xfs "/dev/${VG_NAME}/${THIN_LV}"
else
    echo "Unsupported filesystem type: $FS_TYPE"
    exit 1
fi

# 9. Mount it
mkdir -p "$MOUNT_POINT"
mount "/dev/${VG_NAME}/${THIN_LV}" "$MOUNT_POINT"

# 10. Add to fstab
if ! grep -qs "$MOUNT_POINT" /etc/fstab; then
  echo "/dev/${VG_NAME}/${THIN_LV} $MOUNT_POINT $FS_TYPE defaults 0 2" >> /etc/fstab
fi

echo "✅ Thin-provisioned 40TB volume mounted at $MOUNT_POINT"
