package com.islandbridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/** Foreground keep-alive service: holds the SSE connection alive while the
 *  app is swiped away. Started by MainActivity, BootReceiver, and by the
 *  LSPosed keep-alive pings (KeepAliveReceiver). */
class BridgeService : Service() {

    companion object {
        private const val CH = "bridge"
        private const val NID = 42
        const val ACTION_PING = "com.islandbridge.PING"

        fun start(ctx: Context) {
            val i = Intent(ctx, BridgeService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i)
                else ctx.startService(i)
            } catch (t: Throwable) {
                // FGS-not-allowed and friends used to vanish silently here
                android.util.Log.w("IslandBridge", "svc start fail: $t")
            }
        }
    }

    private var wl: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(
                CH, "豆包岛桥", NotificationManager.IMPORTANCE_MIN))
        }
        val b: Notification.Builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(this, CH) else Notification.Builder(this)
        val n: Notification = b
            .setContentTitle("豆包岛桥运行中")
            .setContentText("保持与电脑的连接")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .build()
        startForegroundCompat(NID, n)
        // ColorOS/Hans freezes cached apps (socket dies even with FGS);
        // a partial wake lock keeps the SSE thread alive
        try {
            wl = (getSystemService(PowerManager::class.java))
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "islandbridge:sse")
                .apply { setReferenceCounted(false); acquire() }
        } catch (_: Exception) {}
        ensureRootRelay()
        (application as BridgeApp).ensureConnected()
    }

    /** Install + start the root runtime.
     *
     *  The LSPosed module inside Doubao appends island events to a queue
     *  file; a uid-0 worker drains it and pushes each frame into this app
     *  over Binder (root is exempt from both the freezer and
     *  OplusAppStartupManager's "do not want to launch"). That worker must
     *  NOT run from the app's own process — ColorOS freezes us
     *  (wchan=do_freezer_trap), which would stop the loop.
     *
     *  Canonical layout, owned by KernelSU so it survives reboots and app
     *  updates:
     *    /data/adb/service.d/islandbridge.sh  launcher (the ONLY .sh there,
     *                                         because service.d executes
     *                                         every .sh it contains)
     *    /data/adb/islandbridge/relay.sh      queue -> Binder worker
     *    /data/adb/islandbridge/listen.sh     LAN listener worker
     *
     *  Files are refreshed only when their contents differ, and the launcher
     *  is idempotent (it will not double-spawn). On a fresh install nothing
     *  is present yet, so this bootstraps from assets. */
    private fun ensureRootRelay() {
        Thread {
            try {
                val dir = "/data/adb/islandbridge"
                val scripts = mapOf(
                    "relay.sh" to "$dir/relay.sh",
                    "listen.sh" to "$dir/listen.sh",
                    "launcher.sh" to "/data/adb/service.d/islandbridge.sh")
                val cmds = StringBuilder()
                cmds.append("mkdir -p $dir; ")
                for ((asset, dst) in scripts) {
                    // ship the script into the app's own dir first (root reads
                    // it from there — writable without su, so a failed write
                    // is reported instead of failing silently)
                    val tmp = java.io.File(filesDir, asset)
                    val fresh = assets.open("root/$asset").use { it.readBytes() }
                    val changed = !tmp.exists() || !tmp.readBytes().contentEquals(fresh)
                    if (changed) {
                        tmp.writeBytes(fresh)
                        android.util.Log.i("IslandBridge", "staged $asset")
                    }
                    cmds.append("cp -f ${tmp.absolutePath} $dst; ")
                    cmds.append("chmod 755 $dst; chown 0:0 $dst; ")
                }
                cmds.append("sh /data/adb/service.d/islandbridge.sh; ")
                val p = Runtime.getRuntime().exec(arrayOf("su", "-c", cmds.toString()))
                p.waitFor()
                android.util.Log.i("IslandBridge",
                    "root runtime ensured (rc=${p.exitValue()})")
            } catch (t: Throwable) {
                android.util.Log.w("IslandBridge", "relay spawn fail: $t")
            }
        }.start()
    }

    private fun startForegroundCompat(id: Int, n: Notification) {
        if (Build.VERSION.SDK_INT >= 34)
            startForeground(id, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        else startForeground(id, n)
    }

    override fun onStartCommand(i: Intent?, flags: Int, startId: Int): Int {
        (application as BridgeApp).ensureConnected()
        return START_STICKY
    }

    override fun onBind(i: Intent?): IBinder? = null
}
