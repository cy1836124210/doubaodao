#!/system/bin/sh
# IslandBridge root event relay (worker).
#
# The LSPosed module inside com.larus.nova appends each island event as one
# base64 line to <nova filesDir>/ibq.log. We run as uid 0, read those lines
# and push each into the bridge app.
#
# TRANSPORT: a Binder transaction (`content call`) into
# com.islandbridge.events — NOT a broadcast. On ColorOS a broadcast aimed at
# a frozen cached app is DEFER_BY_OPLUS'd and the deferred queue is never
# flushed on a later thaw (measured), whereas a Binder txn actively thaws the
# target (UNFREEZE_REASON_BINDER_TXNS): forced-frozen -> freeze=0 in ~1.1s.
# Root is also exempt from OplusAppStartupManager's "do not want to launch",
# so the provider call succeeds even when the app is fully stopped.
#
# Started by /data/adb/service.d/islandbridge.sh (never run directly by
# service.d — service.d executes every .sh it contains).

LOG=/data/local/tmp/islandbridge_relay.log
F=/data/data/com.larus.nova/files/ibq.log
P=$F.proc
PIDFILE=/data/data/com.islandbridge/files/ib_relay.pid
URI=content://com.islandbridge.events

# KernelSU service.d PATH lacks coreutils/busybox (sleep, base64, date...).
export PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH

echo "$$" > "$PIDFILE" 2>/dev/null
echo "$(date) relay start pid=$$" >> "$LOG" 2>/dev/null

# drop whatever accumulated while we weren't running — stale events only
: > "$F" 2>/dev/null

while true; do
    if [ -s "$F" ]; then
        # rotate first: new appends land on a fresh file, nothing is lost
        mv "$F" "$P" 2>/dev/null
        while IFS= read -r b64; do
            [ -z "$b64" ] && continue
            OUT=$(content call --uri "$URI" --method event \
                    --extra evb:s:"$b64" 2>/dev/null)
            case "$OUT" in
                *ok=true*) echo "$(date) binder ok" >> "$LOG" 2>/dev/null; continue ;;
            esac
            echo "$(date) binder miss, bcast fallback" >> "$LOG" 2>/dev/null
            am broadcast -a com.islandbridge.EVENT \
                -n com.islandbridge/.BridgeEventReceiver \
                --ei v 2 --es evb "$b64" >/dev/null 2>&1
        done < "$P" 2>/dev/null
        rm -f "$P" 2>/dev/null
    fi
    sleep 1
done
