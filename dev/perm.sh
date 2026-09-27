#!/system/bin/sh
echo "### SystemUI: requested permissions section ###"
dumpsys package com.android.systemui 2>/dev/null | sed -n '/requested permissions:/,/install permissions:/p' | head -40
echo
echo "### SystemUI: any island mention at all ###"
dumpsys package com.android.systemui 2>/dev/null | grep -in "island" | head -20
echo
echo "### which packages HOLD the island permission (uid list) ###"
dumpsys package permissions 2>/dev/null | grep -B2 -A12 "com.astraflow.tool.island.permission.PUBLISH_ACTIVITY" | head -40
