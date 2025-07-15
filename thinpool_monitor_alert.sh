#!/bin/bash

VG_NAME="vgthin"
THINPOOL_NAME="thinpool"
THRESHOLD=80
LOG_FILE="/var/log/lvm_thinpool_monitor.log"

log() {
    echo "[$(date +'%F %T')] $1" | tee -a "$LOG_FILE"
}

USAGE=$(lvs --noheadings -o data_percent /dev/${VG_NAME}/${THINPOOL_NAME} | awk '{printf("%.0f", $1)}')

if [ "$USAGE" -ge "$THRESHOLD" ]; then
    log "🚨 WARNING: Thin pool $VG_NAME/$THINPOOL_NAME is ${USAGE}% full!"
    wall "🚨 WARNING: LVM Thin Pool ${VG_NAME}/${THINPOOL_NAME} is ${USAGE}% full — please add disk!"
else
    log "✅ Thin pool usage is safe (${USAGE}%)."
fi

