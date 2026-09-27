package com.islandbridge.xposed

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import de.robv.android.xposed.IXposedHookLoadPackage
import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers
import de.robv.android.xposed.callbacks.XC_LoadPackage
import org.json.JSONObject
import java.io.File

/** LSPosed entry (assets/xposed_init).
 *
 *  Scope 1 — com.larus.nova (per D:\aiwork\apk\REVERSE_NOTES):
 *    · OmniHttpCallByNative.writeMetaInfo/writeChunkData — all SSE stream
 *      bytes → MobileFeedParser → normalized events broadcast to
 *      com.islandbridge/.BridgeEventReceiver (island pipeline).
 *    · Omni{Message,Conversation,AIJob}Dispatcher — hooked read-only and
 *      logged (field layout unknown; check LSPosed log to refine).
 *    · Doubao process also pings the bridge app every 60s (keep-alive
 *      while Doubao runs).
 *
 *  Scope 2 — android (system_server): periodic keep-alive broadcast to
 *    com.islandbridge/.KeepAliveReceiver so the bridge service survives
 *    even when Doubao is closed.
 */
class DoubaoHookEntry : IXposedHookLoadPackage {

    companion object {
        private const val TAG = "IslandBridge"
        private const val PKG_SELF = "com.islandbridge"
        private const val PKG_DOUBAO = "com.larus.nova"
        private const val ACT_EVENT = "com.islandbridge.EVENT"
        private const val ACT_EVENT_RELAY = "com.islandbridge.EVENT_RELAY"
        private const val ACT_KEEPALIVE = "com.islandbridge.KEEPALIVE"
        private const val ACT_SEND = "com.islandbridge.SEND"
        private const val ACT_DELETE = "com.islandbridge.DELETE"
        private const val RC_EVENT = "$PKG_SELF.BridgeEventReceiver"
        private const val RC_KEEPALIVE = "$PKG_SELF.KeepAliveReceiver"
        private const val PING_MS = 60_000L
        private const val SYS_PING_MS = 300_000L
        /** 心跳来源标记（放进 Intent 的 "src"）：豆包进程内的 ping 才能证明
         *  模块真的注入成功；system_server 那个即使豆包没开、作用域没勾也照样发。 */
        private const val SRC_DOUBAO = "doubao"
        private const val SRC_SYSTEM = "system"

        @Volatile private var appCtx: Context? = null
        // per-process statics: the same code can be reached from more than
        // one hook (Application.attach AND callApplicationOnCreate, plus the
        // lazy fallback in ensureCtx) — register exactly once per process or
        // one SEND broadcast lands twice and the message is sent twice
        @Volatile private var cmdRegistered = false
        @Volatile private var pingerStarted = false

        /** Resolve the Doubao Application context lazily —
         *  ActivityThread.currentApplication() works from any thread and needs
         *  no hooks, so this is the last-resort path if both ctx hooks missed. */
        private fun ensureCtx(): Context? {
            appCtx?.let { return it }
            return try {
                val at = XposedHelpers.findClass("android.app.ActivityThread", null)
                (XposedHelpers.callStaticMethod(at, "currentApplication")
                    as? Application)?.also { appCtx = it }
            } catch (_: Throwable) { null }
        }

        private const val AUTH_EVENTS = "com.islandbridge.events"

        /** Primary delivery: a Binder call into the bridge app's
         *  EventProvider. Measured on this device, a forced-frozen
         *  com.islandbridge went `freeze=1 wchan=do_freezer_trap` ->
         *  `freeze=0 wchan=do_epoll_wait` on a single transaction
         *  (UNFREEZE_REASON_BINDER_TXNS / _GET_PROVIDER), ~1.1 s. This is
         *  the only transport that both penetrates the ColorOS freezer and
         *  leaves the app running long enough to render the card.
         *  @return true when the app acknowledged the frame. */
        fun callProvider(ctx: Context?, ev: JSONObject): Boolean {
            if (ctx == null) return false
            return try {
                val b = ctx.contentResolver.call(
                    android.net.Uri.parse("content://" + AUTH_EVENTS),
                    "event", null,
                    android.os.Bundle().apply { putString("ev", ev.toString()) })
                b?.getBoolean("ok") == true
            } catch (t: Throwable) {
                XposedBridge.log("$TAG call fail: ${t.javaClass.simpleName} ${t.message}")
                false
            }
        }

        fun sendTo(ctx: Context?, action: String, receiver: String,
                   ev: JSONObject? = null, src: String? = null) {
            if (ctx == null) return
            // --- primary path: Binder (survives the freezer) ---
            if (action == ACT_EVENT && ev != null && callProvider(ctx, ev)) {
                XposedBridge.log("$TAG ev[$action] via provider")
                return
            }
            try {
                val i = Intent(action)
                    .setComponent(ComponentName(PKG_SELF, receiver))
                    .addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                    .putExtra("v", 1)
                // Which process sent this. The keep-alive pinger runs BOTH
                // inside Doubao (proves injection) and inside system_server
                // (works even when Doubao is dead), and the app must not
                // mistake the second for the first — see EnvCheck.
                if (src != null) i.putExtra("src", src)
                if (ev != null) i.putExtra("ev", ev.toString())
                ctx.sendBroadcast(i)
                // ColorOS OplusAppStartupManager blocks app→app broadcasts
                // that would start a stopped package (observed: every EVENT
                // for BridgeEventReceiver dropped). Also fire an implicit
                // relay action — the receiver registered inside system_server
                // (hookSystem) re-sends it as uid 1000, which the startup
                // manager does not block. App-side dedupes both copies.
                if (action == ACT_EVENT && ev != null) {
                    ctx.sendBroadcast(Intent(ACT_EVENT_RELAY)
                        .putExtra("v", 1).putExtra("ev", ev.toString()))
                    // Root-daemon path: OplusAppStartupManager blocks even
                    // uid-1000 broadcasts to a STOPPED app ("Do not want to
                    // launch"), so the bulletproof fallback is appending the
                    // event to a file — /data/adb/service.d/ib_relay.sh runs
                    // as root, reads it and re-broadcasts (root is exempt).
                    try {
                        val q = File(appCtx?.filesDir, "ibq.log")
                        q.appendText(android.util.Base64.encodeToString(
                            ev.toString().toByteArray(Charsets.UTF_8),
                            android.util.Base64.NO_WRAP) + "\n")
                    } catch (_: Throwable) {}
                }
            } catch (t: Throwable) {
                XposedBridge.log("$TAG send fail: $t")
            }
        }
    }

    /** One-time per-process init once the Application context is known. */
    private fun onAppCtx(app: Application?) {
        if (app == null) return
        appCtx = app
        XposedBridge.log("$TAG nova ctx captured")
        try {
            if (!pingerStarted) {
                pingerStarted = true
                startPinger(app, PING_MS, SRC_DOUBAO)
            }
        } catch (t: Throwable) { XposedBridge.log("$TAG pinger fail: $t") }
        // SEND/STOP commands from our app arrive on this receiver living
        // inside the Doubao process
        try {
            if (!cmdRegistered) {
                cmdRegistered = true
                val f = android.content.IntentFilter().apply {
                    addAction(ACT_SEND)
                    addAction(ACT_DELETE)
                }
                if (android.os.Build.VERSION.SDK_INT >= 33)
                    app.registerReceiver(cmdReceiver, f,
                        Context.RECEIVER_EXPORTED)
                else app.registerReceiver(cmdReceiver, f)
                XposedBridge.log("$TAG cmd receiver registered")
            }
        } catch (t: Throwable) {
            XposedBridge.log("$TAG receiver fail: $t")
        }
    }

    /** Registered inside the Doubao process: receives com.islandbridge.SEND /
     *  .DELETE broadcasts from our app and replays them through the Omni SDK.
     *  The result goes back over the normal ACT_EVENT channel as
     *  {"t":"send.result", ok, err}. */
    private val cmdReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(ctx: Context, i: Intent) {
            val text = i.getStringExtra("text") ?: ""
            val cid = i.getStringExtra("cid")
                ?.ifEmpty { null } ?: MessageSender.lastCid
            val botId = i.getStringExtra("botId")
                ?.ifEmpty { null } ?: MessageSender.lastBotId
            Thread {
                // Doubao runs com.larus.nova and com.larus.nova:push as
                // separate processes and this receiver exists in each. Only the
                // MAIN process can send (it owns the chat UI + the send
                // template); answer SEND/DELETE there and stay silent elsewhere
                // so :push cannot race a duplicate or claim "no ids".
                val mainProc = currentProcessName() == PKG_DOUBAO
                if (!mainProc) {
                    XposedBridge.log("$TAG skip ${i.action} in " +
                        "${currentProcessName()}")
                    return@Thread
                }
                val err = when (i.action) {
                    ACT_SEND -> if (text.isEmpty()) "空文本"
                        else MessageSender.send(text, cid)
                    ACT_DELETE -> MessageSender.delete(cid, botId)
                    else -> "未知动作"
                }
                val ev = JSONObject().put("t", "send.result")
                    .put("ok", err == null)
                    .put("err", err ?: "")
                    .put("act", i.action)
                sendTo(ctx, ACT_EVENT, RC_EVENT, ev)
            }.start()
        }
    }

    override fun handleLoadPackage(lpparam: XC_LoadPackage.LoadPackageParam) {
        try {
            when (lpparam.packageName) {
                "com.larus.nova" -> hookNova(lpparam)
                // upstream LSPosed names system_server "android"; the
                // JingMatrix fork on this device passes "system" — accept both
                "android", "system" -> hookSystem(lpparam)
            }
        } catch (t: Throwable) {
            XposedBridge.log("$TAG init fail: $t")
        }
    }

    // ---------- com.larus.nova ----------
    private fun hookNova(lpparam: XC_LoadPackage.LoadPackageParam) {
        val cl = lpparam.classLoader

        // Capture the Application context. Doubao's UI-launch path creates the
        // Application WITHOUT going through Instrumentation.callApplicationOnCreate
        // (in the main process that hook never fires — logs only ever show it
        // for :push), which left appCtx null and silently dropped every event.
        // Application.attach(Context) is `final` — every creation path (manual
        // newApplication+attach+onCreate included) passes through it.
        XposedHelpers.findAndHookMethod(
            "android.app.Application", cl, "attach", Context::class.java,
            object : XC_MethodHook() {
                override fun afterHookedMethod(p: MethodHookParam) {
                    onAppCtx(p.thisObject as? Application)
                }
            })
        XposedHelpers.findAndHookMethod(
            "android.app.Instrumentation", cl,
            "callApplicationOnCreate", Application::class.java,
            object : XC_MethodHook() {
                override fun afterHookedMethod(p: MethodHookParam) {
                    onAppCtx(p.args[0] as? Application)
                }
            })

        // reply-injection path: capture + replay OmniMessageService calls
        MessageSender.init(cl)

        // all SSE stream bytes — hook every overload by name
        hookStreamMethods(cl,
            "com.larus.im.internal.jni.dependency.OmniHttpCallByNative")

        // primary capture: streaming replies arrive as OmniMessage objects
        // through the message dispatcher (native IM channel), not writeChunkData
        hookMessageDispatcher(cl,
            "com.larus.im.internal.jni.observer.OmniMessageDispatcher")

        // downstream dispatchers: log-only taps so field layout can be
        // refined from the LSPosed log without touching native code
        for (dn in arrayOf(
            "com.larus.im.internal.jni.observer.OmniConversationDispatcher",
            "com.larus.im.internal.jni.observer.OmniAIJobDispatcher")) {
            logAllMethods(cl, dn)
        }
    }

    // Both capture paths (SSE chunks + OmniMessage objects) can describe the
    // same reply with different chunking. The SSE stream is the primary
    // protocol (matches the desktop feed); OmniMessage is the fallback for
    // replies delivered while Doubao is backgrounded (push channel). Once
    // SSE produces events for a mid, omni events for it are dropped.
    private val sseMids = HashSet<String>()

    private fun emitShared(src: String, ev: JSONObject) {
        val t = ev.optString("t")
        val mid = ev.optString("mid")
        // track the live conversation id for MessageSender replays
        ev.optString("cid").let { if (it.isNotEmpty()) MessageSender.lastCid = it }
        if (t.startsWith("chat.")) MessageSender.sawChatTraffic = true
        synchronized(sseMids) {
            when {
                src == "sse" && (t == "chat.start" || t == "chat.delta") ->
                    sseMids.add(mid)
                src == "omni" && mid in sseMids -> return
                t == "chat.end" -> sseMids.remove(mid)
            }
        }
        XposedBridge.log("$TAG ev[$src] " + ev.toString().take(160))
        sendTo(ensureCtx(), ACT_EVENT, RC_EVENT, ev)
    }

    private val omniParser = MobileFeedParser { ev -> emitShared("omni", ev) }

    private fun hookMessageDispatcher(cl: ClassLoader, clsName: String) {
        val cls = try {
            XposedHelpers.findClass(clsName, cl)
        } catch (t: Throwable) {
            XposedBridge.log("$TAG no $clsName"); return
        }
        var n = 0
        for (m in cls.declaredMethods) {
            val hasMsg = m.parameterTypes.any {
                it.name == "com.larus.im.internal.jni.bean.OmniMessage" }
            val isEnd = m.name.contains("ReceiveEnd") ||
                m.name.contains("MessageEnd") || m.name.contains("Finish")
            if (!hasMsg && !isEnd) continue
            try {
                XposedBridge.hookMethod(m, object : XC_MethodHook() {
                    override fun afterHookedMethod(p: MethodHookParam) {
                        try {
                            // onStreamingMessage carries (name, new, old, ...):
                            // feeding every OmniMessage arg double-counts —
                            // take only the first (newest snapshot).
                            val msg = p.args?.firstOrNull {
                                it?.javaClass?.name ==
                                    "com.larus.im.internal.jni.bean.OmniMessage"
                            } ?: return
                            handleOmni(msg)
                            if (isEnd) omniParser.finishOmni()
                        } catch (t: Throwable) {
                            XposedBridge.log("$TAG msg fail: $t")
                        }
                    }
                })
                XposedBridge.log("$TAG hooked ${cls.simpleName}.${m.name}")
                if (++n > 30) break
            } catch (_: Throwable) {}
        }
    }

    private fun handleOmni(m: Any) {
        fun f(name: String) = runCatching {
            XposedHelpers.getObjectField(m, name) as? String }.getOrNull() ?: ""
        // bot replies always carry replyId (the user message they answer);
        // user echoes have it empty — skip them so typed text isn't shown
        if (f("replyId").isEmpty()) return
        omniParser.feedOmniMessage(f("messageId"), f("conversationId"),
            f("brief"), f("content"))
    }

    private fun hookStreamMethods(cl: ClassLoader, clsName: String) {
        val parsers = HashMap<Any, MobileFeedParser>()
        val cls = try {
            XposedHelpers.findClass(clsName, cl)
        } catch (t: Throwable) {
            XposedBridge.log("$TAG no $clsName"); return
        }
        for (m in cls.declaredMethods) {
            if (m.name != "writeMetaInfo" && m.name != "writeChunkData")
                continue
            try {
                XposedBridge.hookMethod(m, object : XC_MethodHook() {
                    private var calls = 0
                    override fun afterHookedMethod(p: MethodHookParam) {
                        try {
                            // visibility probe: log first calls with arg shapes
                            if (calls++ < 5 || calls % 500 == 0) {
                                val sig = p.args?.joinToString(",") {
                                    when (it) {
                                        is ByteArray -> "ByteArray(${it.size})"
                                        is String -> "Str(${it.length}):'${it.take(40)}'"
                                        else -> "${it?.javaClass?.simpleName}"
                                    }
                                } ?: ""
                                XposedBridge.log("$TAG call ${m.name}($sig)")
                            }
                            // key by REQUEST, not call object — concurrent
                            // completions share one OmniHttpCallByNative and
                            // would otherwise pour both SSE streams into one
                            // parser (observed: two essays braided together).
                            // args carry a 36-char request uuid and/or a
                            // native call handle; thisObject is the fallback.
                            var key: Any = p.thisObject
                            for (a in p.args ?: emptyArray()) {
                                if (a is String && a.length == 36 &&
                                    a.count { it == '-' } == 4) { key = a; break }
                                if (a is Long) { key = a; break }
                            }
                            val parser = synchronized(parsers) {
                                parsers.getOrPut(key) {
                                    XposedBridge.log("$TAG new parser " +
                                        "key=$key obj=${System.identityHashCode(p.thisObject)}")
                                    MobileFeedParser { ev -> emitShared("sse", ev) }
                                }
                            }
                            for (a in p.args ?: return) when (a) {
                                is ByteArray -> parser.feedBytes(a)
                                is String -> {
                                    // writeChunkData hands us the raw SSE byte
                                    // stream split into arbitrary pieces —
                                    // 'id:'/'event:'/blank lines included, so
                                    // feed everything or frame boundaries are
                                    // lost. Meta calls carry a bare uuid that
                                    // would poison the buffer; skip those.
                                    val isUuid = a.length == 36 &&
                                        a.count { it == '-' } == 4
                                    if (!isUuid) parser.feed(a)
                                }
                            }
                        } catch (t: Throwable) {
                            XposedBridge.log("$TAG parse fail: $t")
                        }
                    }
                })
                XposedBridge.log("$TAG hooked ${m.name}(${m.parameterTypes
                    .joinToString { it.simpleName }})")
            } catch (t: Throwable) {
                XposedBridge.log("$TAG hook ${m.name} fail: $t")
            }
        }
    }

    private fun logAllMethods(cl: ClassLoader, clsName: String) {
        val cls = try {
            XposedHelpers.findClass(clsName, cl)
        } catch (t: Throwable) { return }
        var n = 0
        for (m in cls.declaredMethods) {
            try {
                XposedBridge.hookMethod(m, object : XC_MethodHook() {
                    private var dumps = 0
                    override fun afterHookedMethod(p: MethodHookParam) {
                        // hot dispatchers fire constantly — cap log lines per
                        // method or they flush everything else out of logcat
                        if (dumps >= 6) return
                        dumps++
                        val sig = p.args?.joinToString(",") {
                            it?.javaClass?.simpleName ?: "null" } ?: ""
                        XposedBridge.log("$TAG dsp ${cls.simpleName}." +
                            "${m.name}($sig)")
                        // dump message-object fields a few times so we can
                        // see where reply text lives
                        if (dumps <= 3) for (a in p.args ?: return) {
                            if (a == null || a.javaClass.name.let {
                                    it.startsWith("java.") ||
                                    it.startsWith("kotlin.") }) continue
                            XposedBridge.log("$TAG field ${a.javaClass.name} " +
                                "= ${dumpObj(a).take(600)}")
                            // JNI wrappers hold a native ptr — the text is in
                            // zero-arg getters / toString, not fields
                            XposedBridge.log("$TAG str ${a.javaClass.name} " +
                                "toString=${runCatching { a.toString() }
                                    .getOrNull()?.take(200)} " +
                                "getters=${probeGetters(a).take(600)}")
                        }
                    }
                })
                if (++n > 40) break          // safety bound
            } catch (_: Throwable) {}
        }
    }

    /** Shallow field dump of an opaque SDK object (all fields, incl. super). */
    private fun dumpObj(o: Any, depth: Int = 0): String {
        if (depth > 2) return "…"
        val sb = StringBuilder()
        var k: Class<*>? = o.javaClass
        while (k != null && k != Any::class.java) {
            for (f in k.declaredFields) {
                try {
                    f.isAccessible = true
                    val v = f.get(o)
                    sb.append(f.name).append('=').append(
                        when (v) {
                            null -> "null"
                            is String -> "'${v.take(80)}'"
                            is ByteArray -> "B[${v.size}]"
                            is Number, is Boolean -> v.toString()
                            else -> if (depth < 1 && !v.javaClass.name
                                    .startsWith("java."))
                                "{${dumpObj(v, depth + 1).take(200)}}"
                            else v.javaClass.simpleName
                        }).append(' ')
                } catch (_: Throwable) {}
            }
            k = k.superclass
        }
        return sb.toString()
    }

    /** Invoke zero-arg methods returning String/CharSequence to find the
     *  content accessor on opaque JNI wrapper objects. */
    private fun probeGetters(o: Any): String {
        val sb = StringBuilder()
        for (m in o.javaClass.declaredMethods) {
            if (m.parameterCount != 0) continue
            if (m.returnType != String::class.java &&
                !CharSequence::class.java.isAssignableFrom(m.returnType) &&
                m.returnType != Long::class.javaPrimitiveType &&
                m.returnType != Int::class.javaPrimitiveType) continue
            try {
                m.isAccessible = true
                val v = m.invoke(o) ?: continue
                val s = v.toString()
                if (s.isEmpty() || s == "0") continue
                sb.append(m.name).append("='").append(s.take(100))
                    .append("' ")
            } catch (_: Throwable) {}
        }
        return sb.toString()
    }

    // ---------- android (system_server) ----------
    private fun hookSystem(lpparam: XC_LoadPackage.LoadPackageParam) {
        XposedBridge.log("$TAG loaded in system_server (${lpparam.packageName})")
        // Modules are injected DURING SystemServer.run() — any hook we put
        // on run() is installed too late to fire this boot. Skip the hook
        // and arm directly: poll until the system context materializes
        // (it is created inside run(), so it isn't ready here either).
        Thread {
            var ctx: Context? = null
            for (i in 0..120) {
                try {
                    ctx = systemContext(i % 6 == 0)
                    if (ctx != null) break
                    Thread.sleep(5_000)
                } catch (t: Throwable) {
                    XposedBridge.log("$TAG ctx poll die: $t")
                    return@Thread
                }
            }
            if (ctx == null) {
                XposedBridge.log("$TAG system ctx timeout")
                return@Thread
            }
            startPinger(ctx, SYS_PING_MS, SRC_SYSTEM)
            // besides pinging our own app, the system-side loop revives
            // Doubao itself so its IM push channel (and our in-process
            // hooks) stay alive in background
            startDoubaoWaker(ctx, SYS_PING_MS)
            // the AM binder may not be up yet this early in boot — retry
            // the relay registration until it sticks
            for (i in 0..60) {
                if (startEventRelay(ctx)) break
                Thread.sleep(5_000)
            }
            XposedBridge.log("$TAG system pinger armed")
        }.start()
    }

    /** Services that bring com.larus.nova's process + push/IM channel up.
     *  system_server (uid 1000) may start them regardless of background
     *  restrictions and exported flags. */
    private val DOUBAO_WAKE = arrayOf(
        "com.ss.android.message.NotifyService",
        "com.bytedance.mira.stub.p0.StubService1",
        "com.bytedance.mira.stub.p0.StubService2",
        "com.bytedance.mira.stub.p1.StubService1")

    /** The process this module is currently loaded into, e.g. "com.larus.nova"
     *  or "com.larus.nova:push". Read from ActivityThread so it works from any
     *  thread and needs no context. */
    private fun currentProcessName(): String? = runCatching {
        val at = XposedHelpers.findClass("android.app.ActivityThread", null)
        val th = XposedHelpers.callStaticMethod(at, "currentActivityThread")
        XposedHelpers.callMethod(th, "getProcessName") as? String
    }.getOrNull()

    private fun wakeDoubao(ctx: Context) {
        // already running — nothing to do
        try {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE)
                as android.app.ActivityManager
            @Suppress("DEPRECATION")
            if (am.runningAppProcesses?.any {
                    it.processName == PKG_DOUBAO } == true) return
        } catch (_: Throwable) {}
        for (cls in DOUBAO_WAKE) {
            try {
                ctx.startService(Intent().setComponent(
                    ComponentName(PKG_DOUBAO, cls)))
                XposedBridge.log("$TAG woke doubao via $cls")
                return
            } catch (t: Throwable) {
                XposedBridge.log("$TAG wake $cls fail: " +
                    "${t.javaClass.simpleName}")
            }
        }
        // NOTE: intentionally no activity-launch fallback — popping Doubao to
        // the foreground would be worse than a missed capture. If every
        // service rejects, the log shows which ones were tried.
    }

    private fun startDoubaoWaker(ctx: Context, periodMs: Long) {
        val h = Handler(Looper.getMainLooper())
        val r = object : Runnable {
            override fun run() {
                try { wakeDoubao(ctx) } catch (_: Throwable) {}
                h.postDelayed(this, periodMs)
            }
        }
        h.postDelayed(r, 20_000)   // first kick shortly after boot
    }

    /** system_server-side relay: a broadcast target that is frozen gets its
     *  queue DEFER_BY_OPLUS'd and the queue is NOT flushed on a later thaw,
     *  so the uid-1000 re-broadcast was never enough on its own. Re-deliver
     *  over Binder instead — that transaction is what actually unfreezes the
     *  app (UNFREEZE_REASON_BINDER_TXNS). Kept as a receiver so anything
     *  still emitting the legacy relay action keeps working. */
    private fun startEventRelay(ctx: Context): Boolean {
        try {
            val rcv = object : android.content.BroadcastReceiver() {
                override fun onReceive(c: Context, i: Intent) {
                    val ev = i.getStringExtra("ev") ?: return
                    relayToApp(c, ev)
                }
            }
            ctx.registerReceiver(rcv,
                android.content.IntentFilter(ACT_EVENT_RELAY),
                Context.RECEIVER_EXPORTED)
            XposedBridge.log("$TAG event relay registered")
            return true
        } catch (t: Throwable) {
            XposedBridge.log("$TAG relay fail: ${t.javaClass.simpleName} ${t.message}")
            return false
        }
    }

    /** Deliver one raw JSON event to the bridge app. Binder first (thaws a
     *  frozen target), broadcast only as a fallback. */
    private fun relayToApp(ctx: Context, evJson: String) {
        try {
            val o = JSONObject(evJson)
            if (callProvider(ctx, o)) {
                XposedBridge.log("$TAG relayed event to app (binder)")
                return
            }
        } catch (_: Throwable) {}
        try {
            ctx.sendBroadcast(Intent(ACT_EVENT)
                .setComponent(ComponentName(PKG_SELF, RC_EVENT))
                .addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES)
                .putExtra("v", 1).putExtra("ev", evJson))
            XposedBridge.log("$TAG relayed event to app (bcast fallback)")
        } catch (_: Throwable) {}
    }

    private fun systemContext(logErr: Boolean = false): Context? = try {
        val at = XposedHelpers.findClass("android.app.ActivityThread", null)
        val th = XposedHelpers.callStaticMethod(at, "currentActivityThread")
        XposedHelpers.callMethod(th, "getSystemContext") as? Context
    } catch (t: Throwable) {
        if (logErr) XposedBridge.log(
            "$TAG ctx err: ${t.javaClass.simpleName} ${t.message}")
        null
    }

    /** Keep-alive ping. `src` tells the app WHERE this ping came from: the
     *  copy that runs inside Doubao is proof the module is actually injected
     *  (the system_server copy keeps running even when Doubao is dead or the
     *  scope is unchecked), so the two must not be conflated. */
    private fun startPinger(ctx: Context, periodMs: Long, src: String) {
        val h = Handler(Looper.getMainLooper())
        val r = object : Runnable {
            override fun run() {
                sendTo(ctx, ACT_KEEPALIVE, RC_KEEPALIVE, src = src)
                h.postDelayed(this, periodMs)
            }
        }
        h.post(r)
    }
}
