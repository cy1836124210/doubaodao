#!/system/bin/sh
# IslandBridge LAN listener (worker) — 监听配置的地址/端口，把收到的事件送到岛上。
#
# Listens for newline-delimited JSON island events and pushes each one into
# the bridge app over the SAME Binder channel the relay uses, so a PC or
# script on the LAN can inject frames even when the app is frozen or dead.
#
# Why this lives in the root relay and not in the app: the app is a cached
# process ColorOS freezes (wchan=do_freezer_trap), which kills its sockets and
# stops its loop. uid 0 is never frozen, so the listener must live here.
#
# SERVER MODEL: BusyBox `nc -lk -p PORT -e handler` forks a handler per
# connection and keeps listening. Plain `nc -l -p` exits after ONE connection
# and leaves a ~1 s dead window while the loop restarts — measured on this
# device, that gap silently dropped 9 of 10 rapid frames of a Doubao stream
# (only chat.start and chat.end, sent seconds apart, survived). Do not
# regress this to a non-forking listener.
#
# Config: /data/data/com.islandbridge/files/ib_listen.conf
#   BIND=0.0.0.0     # address to listen on ('0.0.0.0' = all interfaces)
#   PORT=8799
#   TOKEN=SECRET     # if set, every line must be "SECRET<TAB><json>"
#
# Wire format (one event per line):
#   <JSON>\n                          when TOKEN is empty
#   <TOKEN>\t<JSON>\n                 when TOKEN is set
#
# Started by /data/adb/service.d/islandbridge.sh — never place this file in
# service.d directly, since KernelSU executes every .sh found there.

export PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH
BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=

LOG=/data/local/tmp/islandbridge_relay.log
CONF=/data/data/com.islandbridge/files/ib_listen.conf
URI=content://com.islandbridge.events
PIDFILE=/data/data/com.islandbridge/files/ib_listen.pid
HANDLER=/data/adb/islandbridge/handler.sh

BIND=0.0.0.0
PORT=8799
TOKEN=

# shellcheck disable=SC1090
[ -f "$CONF" ] && . "$CONF"

# The per-connection handler. Written here so config and parsing stay in one
# file; nc -e execs it with the socket on stdin/stdout.
cat > "$HANDLER" <<HANDLER_EOF
#!/system/bin/sh
export PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:\$PATH
TOKEN='$TOKEN'
URI='$URI'
LOG='$LOG'
while IFS= read -r line; do
    [ -z "\$line" ] && continue
    PAYLOAD=\$line
    if [ -n "\$TOKEN" ]; then
        case "\$line" in
            "\$TOKEN"*)
                PAYLOAD=\$(printf '%s' "\${line#"\$TOKEN"}" | sed 's/^[[:space:]]*//')
                ;;
            *)
                echo "\$(date) dropped: bad token" >> "\$LOG" 2>/dev/null
                continue ;;
        esac
    fi
    case "\$PAYLOAD" in
        \{*) ;;
        *) echo "\$(date) dropped: not json" >> "\$LOG" 2>/dev/null; continue ;;
    esac
    B64=\$(printf '%s' "\$PAYLOAD" | base64 -w0 2>/dev/null)
    # src=pc: anything arriving over the LAN listener is a computer-side frame,
    # so the island card must say 「电脑」 rather than 「手机」. The relay worker
    # (Doubao hook queue) leaves src unset and therefore reports 「手机」.
    OUT=\$(content call --uri "\$URI" --method event \
        --extra evb:s:"\$B64" --extra src:s:pc 2>/dev/null)
    case "\$OUT" in
        *ok=true*) echo "\$(date) tcp->binder ok" >> "\$LOG" 2>/dev/null ;;
        *) echo "\$(date) tcp->binder miss" >> "\$LOG" 2>/dev/null ;;
    esac
done
HANDLER_EOF
chmod 755 "$HANDLER" 2>/dev/null

echo "$$" > "$PIDFILE" 2>/dev/null
echo "$(date) listener start bind=$BIND port=$PORT auth=$([ -n "$TOKEN" ] && echo on || echo off) pid=$$" \
    >> "$LOG" 2>/dev/null

# Prefer the forking server (no gap between connections). Fall back to the
# simple loop only if this nc build lacks -e.
if [ -n "$BB" ]; then
    while true; do
        if [ "$BIND" = "0.0.0.0" ] || [ -z "$BIND" ]; then
            "$BB" nc -lk -p "$PORT" -e "$HANDLER" 2>>"$LOG"
        else
            "$BB" nc -lk -s "$BIND" -p "$PORT" -e "$HANDLER" 2>>"$LOG" \
                || "$BB" nc -lk -p "$PORT" -e "$HANDLER" 2>>"$LOG"
        fi
        echo "$(date) listener exited, restarting" >> "$LOG" 2>/dev/null
        sleep 1
    done
fi

# ---- fallback: single-connection loop (lossy under rapid frames) ----
listen_once() {
    if [ "$BIND" = "0.0.0.0" ] || [ -z "$BIND" ]; then
        nc -l -p "$PORT" 2>/dev/null
    else
        nc -l -s "$BIND" -p "$PORT" 2>/dev/null || nc -l -p "$PORT" 2>/dev/null
    fi
}

while true; do
    listen_once | "$HANDLER"
    sleep 1
done
