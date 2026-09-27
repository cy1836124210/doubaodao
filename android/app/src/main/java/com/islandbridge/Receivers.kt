package com.islandbridge

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import org.json.JSONObject

/** Woken by explicit keep-alive broadcasts from the LSPosed module
 *  (DoubaoHookEntry pings while com.larus.nova runs, and periodically from
 *  system_server). Wakes the foreground service + reconnects SSE. */
class KeepAliveReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == ACTION_KEEPALIVE || i.action == BridgeService.ACTION_PING) {
            // Only the copy of the module running INSIDE Doubao stamps the
            // heartbeat ("src"="doubao"). The system_server copy pings too,
            // and it keeps pinging even when Doubao is dead or the scope was
            // never checked — counting that would report "模块已生效" on a
            // module that does nothing. See EnvCheck.
            if (i.action == ACTION_KEEPALIVE &&
                i.getStringExtra("src") == "doubao") {
                EnvCheck.noteModulePing()
            }
            BridgeService.start(ctx)
        }
    }

    companion object {
        const val ACTION_KEEPALIVE = "com.islandbridge.KEEPALIVE"
    }
}

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED) BridgeService.start(ctx)
    }
}

/** Receives normalized events captured inside the Doubao process by the
 *  LSPosed module and feeds the same pipeline as the PC SSE stream.
 *  (Unprotected broadcast — display-only data; worst case is a spoofed
 *  island lyric line.)
 *
 *  NOTE: this is now the *fallback* transport. Broadcasts to a frozen
 *  cached app are DEFER_BY_OPLUS'd and never flushed on thaw, so the
 *  primary path is EventProvider (a Binder txn, which unfreezes us). */
class BridgeEventReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        // v=1: "ev" is raw JSON (sent from the Doubao process or the
        // system_server relay). v=2: "evb" is base64(JSON), re-broadcast by
        // the root daemon — the only delivery that survives a fully dead
        // app on ColorOS (uid-1000 broadcasts are still prevent-started).
        val ev = when (i.getIntExtra("v", 0)) {
            1 -> i.getStringExtra("ev")
            2 -> i.getStringExtra("evb")?.let {
                try { String(android.util.Base64.decode(it,
                    android.util.Base64.DEFAULT), Charsets.UTF_8)
                } catch (e: Exception) { null }
            }
            else -> null
        } ?: return
        // EVENT = captured inside Doubao by the LSPosed module (mobile path).
        // EVENT_PC = debug/test hook injecting a frame as if it arrived over
        // the PC SSE link — used to exercise the mobile-priority dedup.
        val fromMobile = i.action != ACTION_EVENT_PC
        android.util.Log.i("IslandBridge", "recv bcast ${i.action}")
        EventSink.submit(ev, fromMobile)
    }

    companion object {
        const val ACTION_EVENT = "com.islandbridge.EVENT"
        const val ACTION_EVENT_PC = "com.islandbridge.EVENT_PC"
    }
}

/** Island card blank-area tap (openIntent PendingIntent targets this):
 *  opens Doubao and ends the card —「操作过才消失」. */
class OpenDoubaoReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        val app = ctx.applicationContext as BridgeApp
        app.bridge.cardTapped()
    }
}
