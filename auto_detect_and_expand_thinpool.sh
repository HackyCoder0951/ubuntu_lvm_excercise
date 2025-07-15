#!/bin/bash

# ================================
VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
EXPAND_UNIT="G"
LOG_FILE="/var/log/lvm_auto_expand.log"
# ================================

log() {
    echo "[$(date +'%F %T')] $1" | tee -a "$LOG_FILE"
}

get_new_disks() {
    lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | while read disk; do
        # Skip if already partitioned or in use
        if lsblk "$disk" | grep -q -E "─[[:alnum:]]+"; then continue; fi
        if pvs | grep -q "$disk"; then continue; fi
        echo "$disk"
    done
}

expand_thin_pool() {
    local vg="$1"
    local thinpool="$2"
    local free_size=$(vgs "$vg" --units g --nosuffix --noheadings -o vg_free | awk '{print int($1)}')

    if (( free_size > 0 )); then
        log "Extending $vg/$thinpool by ${free_size}G"
        lvextend -L +${free_size}G /dev/${vg}/${thinpool} && log "✅ Extended successfully"
    else
        log "⚠️ No free space in volume group to extend thin pool."
    fi
}

# =========== MAIN ===========
log "🔍 Scanning for new unpartitioned disks..."
new_disks=$(get_new_disks)

if [ -z "$new_disks" ]; then
    log "✅ No new disks found. Nothing to do."
    exit 0
fi

for disk in $new_disks; do
    log "🧩 Found new disk: $disk"

    # Partition the disk
    log "📦 Partitioning $disk..."
    parted -s "$disk" mklabel gpt
    parted -a optimal "$disk" mkpart primary 0% 100%
    part="${disk}1"
    sleep 2
    partprobe "$disk"

    # Create PV and extend VG
    log "🔧 Creating PV and adding $part to $VG_NAME..."
    pvcreate "$part" && vgextend "$VG_NAME" "$part"

    # Expand thin pool
    expand_thin_pool "$VG_NAME" "$THINPOOL_NAME"
done

log "🎉 All detected disks processed successfully."
