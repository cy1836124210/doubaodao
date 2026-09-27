#!/system/bin/sh
# Hunt for the @lspbridge-* abstract unix socket and whoever owns it.
O=/data/local/tmp/sock2.txt
: > $O
echo "### all unix sockets with lspbridge/island/astra in path" >> $O
for pid in $(ls /proc | grep -E '^[0-9]+$'); do
  ls -l /proc/$pid/fd 2>/dev/null | grep -iE 'lspbridge|island|astra' | while read l; do
    echo "pid=$pid ($(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | cut -c1-60)) $l" >> $O
  done
done
echo "### /proc/net/unix entries" >> $O
grep -iE 'lspbridge|island|astra' /proc/net/unix >> $O 2>&1
echo "### astraflow own sockets/props" >> $O
getprop 2>/dev/null | grep -iE 'island|astra|lspbridge' >> $O
cat $O
