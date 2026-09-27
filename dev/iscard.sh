#!/system/bin/sh
echo "########## 1. Did our plan.start reach the island and get a result code? ##########"
logcat -d 2>/dev/null | grep -iE "IslandBridge.*(plan|start|bind|island|render)" | tail -30

echo
echo "########## 2. AstraIsland activity creation / card lifecycle ##########"
logcat -d 2>/dev/null | grep -iE "AstraIsland/(Protocol|Activity|Host|Render|Card)" | tail -25

echo
echo "########## 3. Any island errors for us? ##########"
logcat -d 2>/dev/null | grep -iE "island.*(reject|denied|permission|quota|rate|invalid|fail)" | tail -15

echo
echo "########## 4. Our app's own island-client state ##########"
logcat -d 2>/dev/null | grep -E "AstraIsland/Protocol|IslandBridge" | grep -iE "state|ready|connect|session" | tail -10
