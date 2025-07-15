#!/bin/bash
set -e

DISK="/dev/sdb"
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
METADATA_LV="thinmeta"
THIN_LV="lvdata"
THIN_LV_SIZE="5T"
MOUNT_POINT="/data"
FS_TYPE="ext4"
BUFFER_MB=64

echo "🧼 Cleaning up previous setup on $DISK..."
umount "$MOUNT_POINT" 2>/dev/null || true
umount "${DISK}1" 2>/dev/null || true
fuser -vk "$DISK" 2>/dev/null || true
fuser -vk "${DISK}1" 2>/dev/null || true
lvremove -fy "$VG_NAME" 2>/dev/null || true
vgremove -fy "$VG_NAME" 2>/dev/null || true
pvremove -ff -y "${DISK}1" 2>/dev/null || true
wipefs -a "$DISK" || true
dd if=/dev/zero of="$DISK" bs=512 count=10000 status=none || true
partprobe "$DISK" || echo "⚠️ Could not refresh partition table."

echo "🔎 Checking required commands..."
for cmd in pvcreate vgcreate lvcreate lvconvert mkfs.ext4 mount parted vgs; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ Missing: $cmd. Please install it:"
    echo "    sudo apt install -y lvm2 parted"
    exit 1
  fi
done

echo "📦 Partitioning $DISK..."
parted -s "$DISK" mklabel gpt
parted -a optimal "$DISK" mkpart primary 0% 100%
PART="${DISK}1"
sleep 2
partprobe "$DISK"

echo "🛠️ Creating LVM structure..."
pvcreate "$PART"
vgcreate "$VG_NAME" "$PART"
lvcreate -L 1G -n "$METADATA_LV" "$VG_NAME"

FREE_SIZE=$(vgs "$VG_NAME" --units m --noheadings -o vg_free | tr -d '[:space:]' | sed 's/m//')
THINPOOL_SIZE_MB=$((FREE_SIZE - BUFFER_MB))

if (( THINPOOL_SIZE_MB <= 0 )); then
  echo "❌ Not enough space to create thin pool."
  exit 1
fi

echo "🧮 Free VG space: ${FREE_SIZE}MB, using ${THINPOOL_SIZE_MB}MB for thin pool."
lvcreate -L "${THINPOOL_SIZE_MB}M" -n "$THINPOOL_NAME" "$VG_NAME"
lvconvert --chunksize 512K --type thin-pool --poolmetadata "${VG_NAME}/${METADATA_LV}" "${VG_NAME}/${THINPOOL_NAME}"
lvchange --metadataprofile thin-performance "${VG_NAME}/${THINPOOL_NAME}" || true

echo "💽 Creating thin LV ($THIN_LV_SIZE)..."
lvcreate -V "$THIN_LV_SIZE" --thinpool "$THINPOOL_NAME" -n "$THIN_LV" "$VG_NAME"

echo "🧷 Formatting $FS_TYPE..."
if [ "$FS_TYPE" == "ext4" ]; then
    mkfs.ext4 "/dev/${VG_NAME}/${THIN_LV}"
else
    mkfs.xfs "/dev/${VG_NAME}/${THIN_LV}"
fi

mkdir -p "$MOUNT_POINT"
mount "/dev/${VG_NAME}/${THIN_LV}" "$MOUNT_POINT"

if ! grep -qs "$MOUNT_POINT" /etc/fstab; then
  echo "/dev/${VG_NAME}/${THIN_LV} $MOUNT_POINT $FS_TYPE defaults 0 2" >> /etc/fstab
fi

echo "✅ 40TB thin-provisioned volume is ready at $MOUNT_POINT"
