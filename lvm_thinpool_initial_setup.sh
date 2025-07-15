#!/bin/bash

set -e

# === Dependency Check ===
for cmd in pvcreate vgcreate lvcreate vgs parted; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Required command '$cmd' not found. Please install it first:"
    echo "    sudo apt update && sudo apt install -y lvm2 parted"
    exit 1
  fi
done

# ========= CONFIGURATION ===========
DISK="/dev/sdb"           # Initial disk for thin LVM setup
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
METADATA_LV="thinmeta"
THIN_LV="lvdata"
THIN_LV_SIZE="100T"       # Thin provisioned virtual size
MOUNT_POINT="/data"
FS_TYPE="ext4"            # or xfs
# ====================================

# 1. Partition the disk
echo "📦 Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -a optimal "$DISK" mkpart primary 0% 100%
PART="${DISK}1"
sleep 2

# 2. Create Physical Volume
pvcreate "$PART"

# 3. Create Volume Group
vgcreate "$VG_NAME" "$PART"

# 4. Create Metadata LV (optional but recommended)
lvcreate -L 1G -n "$METADATA_LV" "$VG_NAME"

# 5. Create Thin Pool using remaining space
FREE_SIZE=$(vgs "$VG_NAME" --noheadings -o vg_free --units g | tr -dc '0-9.')
lvcreate -L "${FREE_SIZE}G" --poolmetadata "${VG_NAME}/${METADATA_LV}" --type thin-pool -n "$THINPOOL_NAME" "$VG_NAME"

# 6. Create Thin Logical Volume (virtual size > physical)
lvcreate -V "$THIN_LV_SIZE" --thinpool "$THINPOOL_NAME" -n "$THIN_LV" "$VG_NAME"

# 7. Format the thin LV
echo "🧷 Formatting LV with $FS_TYPE..."
if [ "$FS_TYPE" == "ext4" ]; then
    mkfs.ext4 "/dev/${VG_NAME}/${THIN_LV}"
elif [ "$FS_TYPE" == "xfs" ]; then
    mkfs.xfs "/dev/${VG_NAME}/${THIN_LV}"
else
    echo "Unsupported filesystem type: $FS_TYPE"
    exit 1
fi

# 8. Mount it
mkdir -p "$MOUNT_POINT"
mount "/dev/${VG_NAME}/${THIN_LV}" "$MOUNT_POINT"

# 9. Add to /etc/fstab
echo "/dev/${VG_NAME}/${THIN_LV} $MOUNT_POINT $FS_TYPE defaults 0 2" >> /etc/fstab

echo "✅ LVM thin-provisioned setup complete!"