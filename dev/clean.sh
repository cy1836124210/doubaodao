#!/system/bin/sh
echo "########## CLEAN SLATE ##########"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*|*nc*) echo "  kill $p: $c"; kill -9 $p 2>/dev/null ;; esac
done
sleep 2
echo "  survivors:"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*) echo "    ${d#/proc/}: $c" ;; esac
done

echo
echo "########## RESTART ONCE ##########"
rm -f /data/adb/islandbridge/.lock 2>/dev/null
: > /data/local/tmp/islandbridge_relay.log
sh /data/adb/service.d/islandbridge.sh
sleep 4
echo "  processes:"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*) echo "    ${d#/proc/}: $c" ;; esac
done
echo "  port: $(netstat -tlnp 2>/dev/null | grep ':8799')"

echo
echo "########## TEST INJECTION ##########"
APKG=com.islandbridge
am force-stop $APKG; sleep 2
printf 'zqtok123\t{"t":"plan.start","tid":"d1","title":"DIAG CARD","total":0}\n' | nc 127.0.0.1 8799
echo "  nc rc=$?"
sleep 5
echo "  app pid: [$(pidof $APKG)]"
echo "  --- log ---"; cat /data/local/tmp/islandbridge_relay.log
