package com.islandbridge

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.Binder
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Base64
import android.util.Log
import org.json.JSONObject

const val AUTHORITY_EVENTS = "com.islandbridge.events"
private const val TAG_EV = "IslandBridge"

/**
 * Single funnel for normalized island events, whatever transport delivered
 * them. The same frame can legitimately arrive over more than one channel
 * (provider direct, provider via the system_server relay, root relay,
 * legacy broadcast), so dedupe by payload within a short window.
 */
object EventSink {
    private const val WINDOW_MS = 3000L

    /** payload -> delivery time, for cross-transport dedupe. */
    private val recent = HashMap<String, Long>()

    /** Frames that arrived before the Application finished onCreate.
     *
     *  A ContentProvider is instantiated and callable BEFORE
     *  Application.onCreate runs, so a cold Binder wake can hand us an event
     *  while BridgeApp.instance is still null — the old code dropped it and
     *  the very first card of a cold start was lost. Stash instead, and let
     *  BridgeApp drain once it is ready. */
    private val preInit = ArrayList<Pair<String, Boolean>>()

    /** False until BridgeApp.onCreate has wired island/bridge. */
    @Volatile var ready = false
        private set

    private fun isFresh(json: String): Boolean = synchronized(recent) {
        val now = android.os.SystemClock.elapsedRealtime()
        if (now - (recent[json] ?: 0L) < WINDOW_MS) return false
        recent[json] = now
        if (recent.size > 64) {
            recent.entries.removeIf { now - it.value > WINDOW_MS }
        }
        return true
    }

    /** @return true if accepted (dispatched now, or queued for app start). */
    fun submit(json: String, fromMobile: Boolean): Boolean {
        val o = try { JSONObject(json) } catch (e: Exception) { return false }
        if (o.optString("t") == "ping") return true
        // dedupe first: the same frame legitimately arrives over several
        // channels, and a queued duplicate must not be replayed twice
        if (!isFresh(json)) return false
        val app = BridgeApp.instance
        if (app == null || !ready) {
            synchronized(preInit) {
                if (preInit.size < 64) preInit.add(json to fromMobile)
            }
            Log.i(TAG_EV, "queued pre-init ${o.optString("t")}")
            return true
        }
        return dispatch(app, json, o, fromMobile)
    }

    /** Called at the end of BridgeApp.onCreate — replays anything that
     *  arrived while the provider was already live but the app wasn't. */
    fun onAppReady(app: BridgeApp) {
        ready = true
        val drain = synchronized(preInit) {
            val c = ArrayList(preInit); preInit.clear(); c
        }
        for ((json, fromMobile) in drain) {
            try {
                dispatch(app, json, JSONObject(json), fromMobile)
            } catch (_: Throwable) {}
        }
        if (drain.isNotEmpty()) Log.i(TAG_EV, "replayed ${drain.size} pre-init")
    }

    private fun dispatch(app: BridgeApp, json: String, o: JSONObject,
                         fromMobile: Boolean): Boolean {
        Log.i(TAG_EV, "ev ok ${o.optString("t")} ${o.optString("mid")} " +
            "mobile=$fromMobile")
        // the binder caller may have just unfrozen us — make sure the
        // foreground service + island session are up before dispatching
        try { BridgeService.start(app) } catch (_: Throwable) {}
        app.handleEvent(o, fromMobile)
        return true
    }
}

/**
 * Binder delivery endpoint — replaces the manifest-broadcast hop.
 *
 * Why this exists: ColorOS/Hans *defers* broadcasts aimed at a frozen
 * cached app (`not runnable because DEFER_BY_OPLUS ... SUB_REASON: FROZEN`,
 * `DEFERRED for manifest com.islandbridge.BridgeEventReceiver`) and does
 * NOT flush the queue on a later thaw. A Binder transaction does the
 * opposite — it *unfreezes* the target (UNFREEZE_REASON_BINDER_TXNS /
 * UNFREEZE_REASON_GET_PROVIDER). Measured on this device: a forced-frozen
 * com.islandbridge flipped from `freeze=1 wchan=do_freezer_trap` to
 * `freeze=0 wchan=do_epoll_wait` on a single `content call`, ~1.1 s.
 *
 * Authorization: the provider is exported so the Doubao process (uid of
 * com.larus.nova) and system_server can reach it, but every call is
 * checked against an explicit uid allowlist — root, system_server, shell,
 * ourselves, and Doubao. Anything else is rejected.
 */
class EventProvider : ContentProvider() {

    private val main = Handler(Looper.getMainLooper())

    override fun onCreate(): Boolean = true

    override fun call(method: String, arg: String?, extras: Bundle?): Bundle? {
        val uid = Binder.getCallingUid()
        if (!isAllowed(uid)) {
            Log.w(TAG_EV, "provider call rejected: method=$method uid=$uid")
            throw SecurityException("uid $uid may not deliver island events")
        }
        val out = Bundle()
        when (method) {
            "event" -> {
                val raw = extras?.getString("ev")
                    ?: arg?.takeIf { it.isNotEmpty() }
                    ?: extras?.getString("evb")?.let(::decodeB64)
                if (raw.isNullOrEmpty()) {
                    out.putBoolean("ok", false)
                    out.putString("err", "empty payload")
                    return out
                }
                // Source label: the payload may declare its own origin, and the
                // caller may pass it as an extra. Either beats the per-transport
                // default below, so a PC frame relayed over LAN is not shown as
                // 「手机」 and vice versa.
                //
                // fromMobile=true means the phone/Doubao path, which wins over
                // PC frames for the same message id (see BridgeApp.owner).
                val declared = extras?.getString("src")
                val fromMobile = when (declared?.lowercase()) {
                    "pc", "desktop", "电脑" -> false
                    "mobile", "phone", "手机" -> true
                    else -> !raw.contains("\"src\":\"pc\"")   // default: mobile
                }
                val fresh = deliver(raw, fromMobile)
                out.putBoolean("ok", true)
                out.putBoolean("fresh", fresh)
                Log.i(TAG_EV, "provider ev uid=$uid len=${raw.length} fresh=$fresh")
            }
            "ping" -> {
                // pure thaw/probe: no payload, just the Binder txn
                out.putBoolean("ok", true)
                try { BridgeService.start(context!!) } catch (_: Throwable) {}
            }
            else -> {
                out.putBoolean("ok", false)
                out.putString("err", "unknown method $method")
            }
        }
        return out
    }

    /** Marshal onto the main thread so provider callers (binder threads)
     *  never touch the island client concurrently with UI/receiver paths.
     *
     *  If the app hasn't finished starting yet, queue straight from this
     *  binder thread instead — posting to main and waiting would deadlock
     *  when the call arrives *during* BridgeApp.onCreate (the cold-wake
     *  case), and the 2s latch would expire and report a false miss. */
    private fun deliver(json: String, fromMobile: Boolean): Boolean {
        if (!EventSink.ready) return EventSink.submit(json, fromMobile)
        if (Looper.myLooper() == Looper.getMainLooper()) {
            return EventSink.submit(json, fromMobile)
        }
        var fresh = false
        val latch = java.util.concurrent.CountDownLatch(1)
        main.post {
            fresh = EventSink.submit(json, fromMobile)
            latch.countDown()
        }
        // bounded wait: a hung dispatcher must not wedge the caller
        latch.await(2000, java.util.concurrent.TimeUnit.MILLISECONDS)
        return fresh
    }

    private fun decodeB64(s: String): String? = try {
        String(Base64.decode(s, Base64.DEFAULT), Charsets.UTF_8)
    } catch (e: Exception) { null }

    private fun isAllowed(uid: Int): Boolean {
        if (uid == Process.myUid()) return true
        if (uid == 0 || uid == Process.SYSTEM_UID) return true   // root, system_server
        if (uid == Process.SHELL_UID) return true                // adb / root relay
        if (uid == doubaoUid()) return true                      // in-process module
        return false
    }

    @Volatile private var doubao: Int = -2
    private fun doubaoUid(): Int {
        if (doubao != -2) return doubao
        doubao = try {
            context!!.packageManager
                .getPackageUid("com.larus.nova", 0)
        } catch (e: Exception) { -1 }
        return doubao
    }

    /** Debug surface: `content query --uri content://com.islandbridge.events`
     *  both proves reachability and acts as a pure thaw probe. */
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?)
            : Cursor {
        val uid = Binder.getCallingUid()
        if (!isAllowed(uid)) throw SecurityException("uid $uid may not query")
        val c = MatrixCursor(arrayOf("authority", "uid", "ok"))
        c.addRow(arrayOf(AUTHORITY_EVENTS, uid, 1))
        return c
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, s: String?, a: Array<out String>?): Int = 0
    override fun update(uri: Uri, v: ContentValues?, s: String?,
                        a: Array<out String>?): Int = 0
}
