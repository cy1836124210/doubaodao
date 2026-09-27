#!/system/bin/sh
# Q1: does the app's own Java code keep running while backgrounded?
#     (CPU time advancing => a file/socket fix is viable)
# Q2: what does OPLUS think about each process?
L=/data/local/tmp/diag.log
: > $L

PID=$(pidof com.islandbridge | awk '{print $1}')
echo "pid=$PID" >> $L

cpu(){ awk '{print "  utime="$14" stime="$15" state="$3}' /proc/$1/stat 2>/dev/null; }

echo "--- CPU sample 1" >> $L; cpu $PID
sleep 20
echo "--- CPU sample 2 (after 20s)" >> $L; cpu $PID

echo "--- scheduling / state" >> $L
dumpsys activity processes com.islandbridge 2>/dev/null | grep -E 'isFrozen|state: cur|adj=|procstate|schedGroup' | head -8 >> $L

echo "--- oplus freeze bookkeeping" >> $L
dumpsys activity broadcasts 2>/dev/null | grep -m3 "DEFER_BY_OPLUS" >> $L

echo "--- NoActive module present?" >> $L
ls -d /data/adb/modules/cn.myflv.noactive 2>/dev/null >> $L || echo "  no ksu module dir" >> $L
echo "  APK: $(pm path cn.myflv.noactive 2>/dev/null)" >> $L

echo "--- lspd modules currently loaded" >> $L
grep -ho "preloaded [0-9]*/[0-9]* modules" /data/adb/lspd/log/modules_*.log 2>/dev/null | tail -2 >> $L
grep -hoE "\[cn\.myflv\.noactive\]|noactive" /data/adb/lspd/log/modules_*.log 2>/dev/null | tail -3 >> $L

echo "--- FreezerConfig whiteUidSet" >> $L
cat /data/system/NoActive_oe8vPqFB/config/FreezerConfig.json 2>/dev/null >> $L
echo "--- end ---" >> $L
