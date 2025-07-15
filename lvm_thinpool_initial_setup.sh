#!/bin/bash

set -e

# === Dependency Check ===
for cmd in pvcreate vgcreate lvcreate lvconvert mkfs.ext4 mkfs.xfs mount parted vgs; do
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

# 1. Partition the disk
echo "📦 Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -a optimal "$DISK" mkpart primary 0% 100%
PART="${DISK}1"
sleep 2

# 2. Create PV
pvcreate "$PART"

# 3. Create VG
vgcreate "$VG_NAME" "$PART"

# 4. Create Metadata LV
lvcreate -L 1G -n "$METADATA_LV" "$VG_NAME"

# 5. Create Thin Pool LV using all remaining space
FREE_SIZE=$(vgs "$VG_NAME" --units m --noheadings -o vg_free | tr -d '[:space:]' | sed 's/m//' | awk '{print int($1)}')

if (( FREE_SIZE < 10000 )); then
  echo "⚠️ Warning: Only ${FREE_SIZE}MB free space. Thin provisioning will work but watch usage!"
fi

lvcreate -L "${FREE_SIZE}M" -n "$THINPOOL_NAME" "$VG_NAME"

# 6. Convert to thin pool
lvconvert --type thin-pool --poolmetadata "${VG_NAME}/${METADATA_LV}" "${VG_NAME}/${THINPOOL_NAME}"

# 7. Enable auto-extension policy
lvchange --metadataprofile thin-performance "${VG_NAME}/${THINPOOL_NAME}" || true
lvs --segments -o+seg_monitor

# 8. Create virtual 40TB Thin LV
echo "💾 Creating 40TB thin logical volume..."
lvcreate -V "$THIN_LV_SIZE" --thinpool "$THINPOOL_NAME" -n "$THIN_LV" "$VG_NAME"

# 9. Format the volume
echo "🧷 Formatting LV with $FS_TYPE..."
if [ "$FS_TYPE" == "ext4" ]; then
    mkfs.ext4 "/dev/${VG_NAME}/${THIN_LV}"
elif [ "$FS_TYPE" == "xfs" ]; then
    mkfs.xfs "/dev/${VG_NAME}/${THIN_LV}"
else
    echo "Unsupported filesystem type: $FS_TYPE"
    exit 1
fi

# 10. Mount
mkdir -p "$MOUNT_POINT"
mount "/dev/${VG_NAME}/${THIN_LV}" "$MOUNT_POINT"

# 11. Add to fstab
echo "/dev/${VG_NAME}/${THIN_LV} $MOUNT_POINT $FS_TYPE defaults 0 2" >> /etc/fstab

echo "✅ 40TB thin-provisioned volume mounted at $MOUNT_POINT"
