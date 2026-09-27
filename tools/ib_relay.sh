#!/system/bin/sh
# IslandBridge root event relay.
# The LSPosed module inside com.larus.nova appends each island event as one
# base64 line to <nova filesDir>/ibq.log. We (uid 0) re-broadcast every line
# to com.islandbridge/.BridgeEventReceiver. Root broadcasts are exempt from
# OplusAppStartupManager's "Do not want to launch" gate, so this is the only
# delivery that revives a fully dead app on ColorOS.
# Spawned by the app itself via su (com.islandbridge has a KernelSU grant);
# outlives the app, dies only at reboot — the app re-spawns it on next start.

F=/data/data/com.larus.nova/files/ibq.log
P=$F.proc
PIDFILE=/data/data/com.islandbridge/files/ib_relay.pid

echo $$ > "$PIDFILE" 2>/dev/null

# drop whatever accumulated while we weren't running — stale events only
: > "$F" 2>/dev/null

while true; do
    if [ -s "$F" ]; then
        # rotate first: new appends land on a fresh file, nothing is lost
        mv "$F" "$P" 2>/dev/null
        while IFS= read -r b64; do
            [ -n "$b64" ] && am broadcast \
                -a com.islandbridge.EVENT \
                -n com.islandbridge/.BridgeEventReceiver \
                --ei v 2 --es evb "$b64" >/dev/null 2>&1
        done < "$P" 2>/dev/null
        rm -f "$P" 2>/dev/null
    fi
    sleep 1
done
