package com.islandbridge

import android.app.Application
import com.astraisland.client.IslandClient
import org.json.JSONObject

class BridgeApp : Application() {
    companion object {
        /** Set on the main thread in onCreate — lets Binder-side entry points
         *  (EventProvider) reach the singleton without a Context cast chain. */
        @Volatile var instance: BridgeApp? = null
            private set
    }

    lateinit var island: IslandClient
        private set
    lateinit var bridge: IslandBridge
        private set
    lateinit var chat: ChatStore
        private set
    lateinit var link: SseClient
        private set

    override fun onCreate() {
        super.onCreate()
        instance = this
        chat = ChatStore()
        island = IslandClient(this) { id, action ->
            // island action buttons (回复/删除会话) — bridge is a
            // lateinit created right after, guard for early taps
            if (::bridge.isInitialized) bridge.onAction(id, action)
        }
        island.onReadyChanged = { ready ->
            if (ready) { bridge.resync(); chat.log("岛已就绪") }
            else chat.log("岛连接断开: " + island.state)
        }
        island.onEvent = { id, event, _ ->
            chat.log("岛事件 $event ($id)")
            // 用户划走 / 60s 到期 / 系统结束 —— 同步收账
            if (event == "onDismissedByUser" || event == "onExpired" ||
                event == "onEndedBySystem") {
                if (::bridge.isInitialized) bridge.userDismissed(id)
            }
        }
        island.onReply = { id, text ->
            if (::bridge.isInitialized) bridge.onReplyText(id, text)
        }
        bridge = IslandBridge(this, island, chat::log)
        link = SseClient { line -> handleEvent(line) }
        link.onState = { s -> chat.log("SSE: $s") }
        island.connect()
        // a provider call can beat onCreate here (cold Binder wake) — replay
        // whatever EventSink had to queue, now that island/bridge exist
        EventSink.onAppReady(this)
    }

    fun connectTo(host: String, port: Int) = link.connectTo(host, port)
    fun disconnect() = link.disconnect()

    /** Reconnect from saved prefs — called by BridgeService on (re)start
     *  and keep-alive pings. No-op until a host has been configured. */
    fun ensureConnected() {
        val p = getSharedPreferences("bridge", MODE_PRIVATE)
        val host = p.getString("host", null) ?: return
        link.connectTo(host, p.getInt("port", 8787))
    }

    // Two sources feed the same protocol: PC daemon over SSE and the LSPosed
    // module inside Doubao Android. When both report the same message the
    // phone is authoritative — a mid/tid claimed by "mobile" ignores pc
    // frames until its chat.end/plan.end.
    private val owner = HashMap<String, String>()

    fun handleEvent(o: JSONObject, fromMobile: Boolean = false) {
        val t = o.optString("t")
        if (t == "ping") return
        val key = o.optString("mid").ifEmpty { o.optString("tid") }
        if (key.isNotEmpty() &&
            (t.startsWith("chat.") || t.startsWith("plan."))) {
            if (fromMobile) {
                owner[key] = "mobile"          // phone always wins
            } else {
                if (owner[key] == "mobile") {
                    chat.log("丢弃PC帧(手机优先): $t $key")
                    return
                }
                if (t == "chat.start" || t == "plan.start") owner[key] = "pc"
            }
            if (t == "chat.end" || t == "plan.end") owner.remove(key)
        }
        bridge.handle(o, fromMobile)
        chat.handle(o)
    }

    fun handleEvent(line: String) {
        val o = try { JSONObject(line) } catch (e: Exception) { return }
        handleEvent(o)
    }
}
