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

# Scan /dev/sd[b-z] and /dev/nvme*n1 to avoid /dev/fd0, /dev/sr0, /dev/loop*, etc.
get_new_disks() {
    for disk in /dev/sd[b-z] /dev/nvme*n1; do
        # Skip non-block devices
        [ -b "$disk" ] || continue

        # Skip if already partitioned
        if lsblk "$disk" | grep -q -E "─[[:alnum:]]+"; then
            log "⚠️  Skipping $disk (already partitioned)"
            continue
        fi

        # Skip if already a PV
        if pvs | grep -q "$disk"; then
            log "⚠️  Skipping $disk (already a PV)"
            continue
        fi

        echo "$disk"
    done
}

expand_thin_pool() {
    local vg="$1"
    local thinpool="$2"
    local free_size=$(vgs "$vg" --units g --nosuffix --noheadings -o vg_free | awk '{print int($1)}')

    free_size=$((free_size - 1))  # Leave buffer
    if (( free_size > 0 )); then
        log "📈 Extending $vg/$thinpool by ${free_size}G"
        lvextend -L +${free_size}G /dev/${vg}/${thinpool} && log "✅ Thin pool extended successfully"
    else
        log "⚠️ Not enough free space after buffer — skipping lvextend."
    fi
}

# =========== MAIN ===========
log "🔍 Scanning for new unpartitioned disks..."

get_new_disks | while read -r disk; do
    [ -z "$disk" ] && continue
    log "🧩 Found new disk: $disk"

    log "📦 Partitioning $disk..."
    parted -s "$disk" mklabel gpt
    parted -a optimal "$disk" mkpart primary 0% 100%
    part="${disk}1"
    sleep 2
    partprobe "$disk"

    log "🔧 Creating PV and adding $part to $VG_NAME..."
    pvcreate "$part" && vgextend "$VG_NAME" "$part"

    expand_thin_pool "$VG_NAME" "$THINPOOL_NAME"
done

log "🎉 All detected disks processed and thin pool expanded."
