package com.islandbridge.xposed

import de.robv.android.xposed.XC_MethodHook
import de.robv.android.xposed.XposedBridge
import de.robv.android.xposed.XposedHelpers
import android.app.AndroidAppHelper
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.lang.reflect.Method
import java.lang.reflect.Modifier
import java.lang.reflect.Proxy
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Sends a user message (and stop-generation) from inside com.larus.nova via
 *  Doubao's own IM stack.
 *
 *  Three tiers, best first:
 *   1. BEAN clone — hook MessageServiceImpl.sendMessageV2 (bean level,
 *      com.larus.im.internal.core.message) captures a real MessageRequestV2;
 *      replay clones it via Kotlin copy() with a rebuilt requestMessages list
 *      (fresh localMessageId + swapped TextBlock text) and the target cid in
 *      clientMeta. senderId/botId/userType come straight from the template —
 *      nothing to guess.
 *   2. NATIVE replay — the original OmniMessageService.sendMessageV2
 *      (NativeSendMessageRequestInternalV2) capture + JSON surgery. Kept as
 *      fallback because it was verified end-to-end on device.
 *   3. SCRATCH — no template at all: ConversationServiceImpl.getConversation
 *      (or getMainConversation) + OmniMessageService.getLatestMessage for the
 *      sender uid → construct MessageRequestV2 from no-arg ctors + field sets.
 *
 *  Verified dex layout (v15.x):
 *    MessageServiceImpl().sendMessageV2(MessageRequestV2, IIMCallback)
 *    ConversationServiceImpl().getConversation(String,Z,IIMCallback,String,Map)
 *    IIMCallback { mustInMain()Z; onSuccess(Object); onFailure(IIMError) }
 *    beans: com.larus.im.bean.message.{MessageRequestV2, RequestMessage,
 *      ClientMeta, ChatQueryOption, block.BlockContent, block.TextBlock}
 */
object MessageSender {
    private const val TAG = "IslandBridge"
    private const val REQ_CLS =
        "com.larus.im.internal.legacy.NativeSendMessageRequestInternalV2"
    private const val SVC_CLS =
        "com.larus.im.internal.jni.service.OmniMessageService"
    private const val CB_CLS =
        "com.larus.im.internal.jni.callback.OmniIMCallback"
    private const val BEAN_REQ_CLS = "com.larus.im.bean.message.MessageRequestV2"
    private const val MSG_SVC_CLS =
        "com.larus.im.internal.core.message.MessageServiceImpl"
    private const val CONV_SVC_CLS =
        "com.larus.im.internal.core.conversation.ConversationServiceImpl"
    private const val IIMCB_CLS = "com.larus.im.callback.IIMCallback"
    private const val OMNI_MSG_CLS =
        "com.larus.im.internal.jni.bean.OmniMessage"
    // delete: the REAL conversation service lives in the legacy impl; the
    // ConversationServiceImpl bodies for deleteConversation/getConversation are
    // no-op stubs (dex-verified: 11 / 6 code units).
    private const val CONV_COMPANION_CLS = "$CONV_SVC_CLS\$Companion"
    private const val DELETE_MODE_CLS =
        "com.larus.im.bean.conversation.ConversationDeleteMode"
    private const val OMNI_SDK_HELPER_CLS =
        "com.larus.im.internal.jni.OmniSDKHelper"
    private const val NATIVE_MSG_SVC_CLS =
        "com.larus.im.internal.legacy.NativeMessageServiceImpl"
    private const val FUNCTION1_CLS = "kotlin.jvm.functions.Function1"

    // captured send templates
    @Volatile private var sendMethod: Method? = null
    @Volatile private var sendThis: Any? = null
    @Volatile private var sendArgs: Array<Any?>? = null
    @Volatile private var lastReq: Any? = null          // native request
    @Volatile private var beanReq: Any? = null          // MessageRequestV2
    @Volatile private var beanSvc: Any? = null          // NativeMessageServiceImpl

    /** Doubao runs com.larus.nova and com.larus.nova:push as SEPARATE processes,
     *  and our dynamic receiver exists in both. The SEND is answered by
     *  whichever process holds the send template, but the STOP broadcast can
     *  land in the other one — which never sent anything and therefore has no
     *  ids, producing "无发送消息 id" even though the send succeeded. Both
     *  processes share a uid, so the ids are mirrored to a file and read back
     *  when the in-memory copy is empty. */
    private val idFile: File?
        get() = runCatching {
            val app = AndroidAppHelper.currentApplication() ?: return null
            File(app.filesDir, "ib_sendids")
        }.getOrNull()

    private fun persistIds() {
        runCatching {
            idFile?.writeText("$sentLocalMsgId\n$sentServerMsgId")
        }
    }

    /** Reflection handles cached after init(). */
    /** localMessageId we generated for the last outbound message. */
    @Volatile var sentLocalMsgId: String = ""
    /** server-side messageId of that same outbound message, learned from the
     *  send callback / outbound chat event when available. */
    @Volatile var sentServerMsgId: String = ""
    /** botId of the current conversation, for deleteConversation. */
    @Volatile var lastBotId: String = ""

    /** Latest conversation id seen by the feed parser (emitShared stamps it). */
    @Volatile var lastCid: String = ""
    /** cid baked into the captured send template. */
    @Volatile private var templateCid: String = ""
    /** any chat.* event seen in THIS process — gates the scratch path so a
     *  process without live IM traffic doesn't race a duplicate send. */
    @Volatile var sawChatTraffic = false

    private var dumped = false
    /** Thread-local marker set while WE are calling the send entry, so our own
     *  outbound call is not mistaken for a human send template.
     *
     *  BUG THIS FIXES (live-proven): the capture hook on
     *  NativeMessageServiceImpl.v(...) fires for every caller, ours included.
     *  On a process that had not seen a human send, the first bridge SEND fell
     *  through to the hand-built scratch path, whose request the server rejects
     *  with "message list empty / error_stage=send_validate". That rejected
     *  bean was then captured as the template, so every later send cloned the
     *  same invalid request and failed identically — one bad send poisoned all
     *  subsequent ones. Thread-local (not a plain flag) so a genuine human send
     *  racing on the UI thread is still captured. */
    private val selfSend = ThreadLocal.withInitial { false }

    /** Run our own outbound send without letting the capture hooks see it. */
    private inline fun <T> asSelfSend(block: () -> T): T {
        selfSend.set(true)
        try { return block() } finally { selfSend.set(false) }
    }

    private var cbClass: Class<*>? = null
    private var iimCbClass: Class<*>? = null
    private var hookCl: ClassLoader? = null

    /** Install capture hooks; call once from DoubaoHookEntry.hookNova. */
    fun init(cl: ClassLoader) {
        hookCl = cl
        cbClass = runCatching { XposedHelpers.findClass(CB_CLS, cl) }
            .getOrNull()
        iimCbClass = runCatching { XposedHelpers.findClass(IIMCB_CLS, cl) }
            .getOrNull()

        // bean-level capture: the real send entry used by the chat UI.
        // NOTE: internal.core.MessageServiceImpl is a pure stub facade — its
        // sendMessageV2 body is only `checkNotNullParameter` + `return-void`
        // (dex 494574) and NOTHING in the dex calls it. The live object is
        // internal.legacy.NativeMessageServiceImpl, reachable through
        // MessageServiceImpl.a() / .instance_delegate$lambda$2, and its real
        // sendMethodV2 is `v(MessageRequestV2, IIMCallback)` (dex 5d8ca8),
        // which calls OmniSDKHelper.getOmniSDK(r()).withMessageService(..).
        runCatching { XposedHelpers.findClass(MSG_SVC_CLS, cl) }
            .getOrNull()?.let { svc ->
                for (m in svc.declaredMethods) {
                    if (m.name != "sendMessageV2" && m.name != "addMessageV2" &&
                        m.name != "regenMessageV2") continue
                    try {
                        XposedBridge.hookMethod(m, captureHook { p ->
                            if (selfSend.get()) return@captureHook
                            val bean = p.args?.firstOrNull {
                                it?.javaClass?.name == BEAN_REQ_CLS }
                            if (bean != null && m.name == "sendMessageV2") {
                                beanReq = bean
                                beanSvc = realMessageService(cl) ?: p.thisObject
                                templateCid = prop(bean, "clientMeta")
                                    ?.let { prop(it, "conversationId") }
                                    as? String ?: templateCid
                                if (!dumped) {
                                    dumped = true
                                    XposedBridge.log("$TAG bean req " +
                                        runCatching { bean.toString() }
                                            .getOrNull()?.take(500))
                                }
                            }
                        })
                        XposedBridge.log("$TAG hooked bean ${m.name}")
                    } catch (t: Throwable) {
                        XposedBridge.log("$TAG bean hook ${m.name} fail: $t")
                    }
                }
            }

        // THE capture that actually fires: hook the LIVE service's real beans
        // entry `v(MessageRequestV2, IIMCallback)`. The facade's sendMessageV2
        // above is dead code (nothing in the dex calls it), so without this the
        // template was NEVER populated and every send fell through to the
        // hand-built scratch path — which the server rejects with
        // "message list empty / error_stage=send_validate".
        runCatching {
            XposedHelpers.findClass(NATIVE_MSG_SVC_CLS, cl)
        }.getOrNull()?.let { real ->
            for (m in real.declaredMethods) {
                if (m.name != "v" || m.parameterCount != 2) continue
                runCatching {
                    XposedBridge.hookMethod(m, captureHook { p ->
                        if (selfSend.get()) return@captureHook
                        val bean = p.args?.firstOrNull {
                            it?.javaClass?.name == BEAN_REQ_CLS }
                        if (bean != null) {
                            beanReq = bean
                            beanSvc = p.thisObject
                            templateCid = prop(bean, "clientMeta")
                                ?.let { prop(it, "conversationId") }
                                as? String ?: templateCid
                            if (!dumped) {
                                dumped = true
                                XposedBridge.log("$TAG REAL bean req " +
                                    runCatching { bean.toString() }
                                        .getOrNull()?.take(500))
                            }
                        }
                    })
                    XposedBridge.log("$TAG hooked REAL send v(" +
                        m.parameterTypes.joinToString { it.simpleName } + ")")
                }.onFailure { XposedBridge.log("$TAG real hook fail: $it") }
            }
        }

        // native-level capture (fallback path)
        val svc = try {
            XposedHelpers.findClass(SVC_CLS, cl)
        } catch (t: Throwable) {
            XposedBridge.log("$TAG no $SVC_CLS"); return
        }
        for (m in svc.declaredMethods) {
            try {
                when (m.name) {
                    "sendMessageV2", "regenMessage", "addMessageV2" -> {
                        XposedBridge.hookMethod(m, captureHook { p ->
                            if (selfSend.get()) return@captureHook
                            sendMethod = m
                            sendThis = p.thisObject
                            sendArgs = p.args?.copyOf()
                            lastReq = p.args?.firstOrNull {
                                it?.javaClass?.name == REQ_CLS }
                            if (templateCid.isEmpty()) templateCid = lastCid
                        })
                        XposedBridge.log("$TAG hooked ${m.name}(" +
                            m.parameterTypes.joinToString { it.simpleName } + ")")
                    }
                    "interruptMessage" -> {
                        // No bridge feature calls this any more (Doubao has no
                        // stop button in its UI, so "stop a live reply" was
                        // never a real operation — see STOP_DELETE_FIX.md).
                        // The hook is kept purely as a diagnostic tap so we can
                        // see the ids the app itself would pass if it ever
                        // interrupts a reply internally.
                        XposedBridge.hookMethod(m, captureHook { p ->
                            XposedBridge.log("$TAG interrupt args: " +
                                (p.args?.joinToString { a ->
                                    when (a) {
                                        is String -> "'${a.take(40)}'"
                                        null -> "null"
                                        else -> a.javaClass.simpleName
                                    }
                                } ?: ""))
                        })
                        XposedBridge.log("$TAG hooked interruptMessage (diag)")
                    }
                }
            } catch (t: Throwable) {
                XposedBridge.log("$TAG hook ${m.name} fail: $t")
            }
        }
    }

    private fun captureHook(body: (XC_MethodHook.MethodHookParam) -> Unit) =
        object : XC_MethodHook() {
            override fun beforeHookedMethod(p: MethodHookParam) {
                try { body(p) } catch (t: Throwable) {
                    XposedBridge.log("$TAG capture fail: $t")
                }
            }
        }

    // ---------- send ----------

    /** True when this process captured a send template. Doubao runs several
     *  processes (main + :push); the cmd receiver exists in all of them, so
     *  processes without a template stay silent and let the one that has it
     *  answer — otherwise a "无发送模板" from :push races the real send. */
    fun hasTemplate() = lastReq != null || beanReq != null

    /** Scratch sends are only attempted in the process that actually sees IM
     *  traffic — keeps a second process from firing a duplicate message. */
    fun canScratch() = sawChatTraffic

    /** Send `text` into conversation `cid` ("" keeps the template's / latest).
     *  Returns null on success, else an error message. */
    fun send(text: String, cid: String): String? {
        // a new turn invalidates the previous turn's server id; the stop target
        // must be the message we are about to send, not the one before it
        sentServerMsgId = ""
        var err: String? = null
        beanReq?.let { bean ->
            // null = sent; on error fall through to the next tier
            cloneBeanSend(bean, text, cid)?.let { err = it } ?: return null
        }
        lastReq?.let { req ->
            nativeSend(req, text, cid)?.let { err = "$err; $it" }
                ?: return null
        }
        scratchSend(text, cid.ifEmpty { lastCid })?.let {
            err = "$err; $it" } ?: return null
        return err
    }

    /** Delete a conversation. Previously this was a UI-only dismiss — the IM
     *  stack was never touched, so the conversation stayed in Doubao.
     *
     *  TRAP (dex-verified): ConversationServiceImpl.deleteConversation is an
     *  11-code-unit no-op stub (two checkNotNullParameter + return-void). The
     *  real body is NativeConversationServiceImpl.deleteConversation, which
     *  builds OmniDeleteConversationRequest(cid, CONVERSATION_TYPE_UNKNOWN,
     *  deleteMode.value, botId) and calls OmniConversationService.
     *
     *  Route A (preferred): Companion.get().deleteConversation(cid, mode,
     *  botId, cb) — reuses Doubao's own request assembly.
     *  Route B: build OmniDeleteConversationRequest ourselves.
     */
    fun delete(cid: String, botId: String): String? {
        if (cid.isEmpty()) return "无会话id"
        val cl = hookCl ?: return "无 classloader"
        val modeCls = runCatching {
            XposedHelpers.findClass(DELETE_MODE_CLS, cl) }.getOrNull()
            ?: return "无 ConversationDeleteMode 类"
        val mode = try {
            XposedHelpers.getStaticObjectField(modeCls, "DeleteMode_RealDelete")
        } catch (t: Throwable) { return "取删除模式失败: ${t.message}" }

        // Route A — the legacy impl does the request building for us
        conversationService(cl)?.let { svc ->
            val m = svc.javaClass.methods.firstOrNull {
                it.name == "deleteConversation" && it.parameterCount == 4 }
            if (m != null) {
                return try {
                    m.invoke(svc, cid, mode, botId, newIimCallback())
                    XposedBridge.log("$TAG delete ok (high) cid=$cid")
                    null
                } catch (t: Throwable) {
                    val msg = t.cause?.message ?: t.message ?: "$t"
                    XposedBridge.log("$TAG delete high fail: $msg — 兜底")
                    deleteNative(cl, cid, mode, botId)?.let { return it }
                    null
                }
            }
        }
        return deleteNative(cl, cid, mode, botId)
    }

    /** Route B: assemble OmniDeleteConversationRequest ourselves. */
    private fun deleteNative(cl: ClassLoader, cid: String, mode: Any,
                             botId: String): String? {
        val reqCls = runCatching { XposedHelpers.findClass(
            "com.larus.im.internal.jni.bean.OmniDeleteConversationRequest", cl) }
            .getOrNull() ?: return "无 OmniDeleteConversationRequest 类"
        val typeCls = runCatching { XposedHelpers.findClass(
            "com.larus.im.internal.jni.bean.OmniConversationType", cl) }
            .getOrNull() ?: return "无 OmniConversationType 类"
        val cb = cbClass ?: return "无 OmniIMCallback 类"
        return try {
            val modeVal = prop(mode, "value") as? Int ?: 0
            val type = XposedHelpers.getStaticObjectField(typeCls,
                "CONVERSATION_TYPE_UNKNOWN")
            val req = reqCls.getConstructor(String::class.java, typeCls,
                Int::class.javaPrimitiveType, String::class.java)
                .newInstance(cid, type, modeVal, botId)
            val svcCls = runCatching { XposedHelpers.findClass(
                "com.larus.im.internal.jni.service.OmniConversationService", cl) }
                .getOrNull() ?: return "无 OmniConversationService 类"
            val svc = liveConversationService(cl)
                ?: return "无 OmniConversationService 实例"
            val m = svcCls.getDeclaredMethod("deleteConversation", reqCls, cb)
            m.isAccessible = true
            m.invoke(svc, req, newCallback())
            XposedBridge.log("$TAG delete ok (native) cid=$cid mode=$modeVal")
            null
        } catch (t: Throwable) {
            "delete 失败: ${t.cause?.message ?: t.message ?: t}"
        }
    }

    // ---------- service handles ----------

    /** ConversationServiceImpl.Companion.get() -> NativeConversationServiceImpl
     *  (the real impl). Dex: Companion.get is PUBLIC and the legacy
     *  deleteConversation/tryInterrupt/getConversation bodies are the real
     *  ones (74 / 25 / 126 code units). */
    private fun conversationService(cl: ClassLoader): Any? = runCatching {
        val compCls = XposedHelpers.findClass(CONV_COMPANION_CLS, cl)
        // getStaticObjectField throws when absent, so probe each name
        var inst: Any? = null
        for (n in arrayOf("INSTANCE", "Companion", "a")) {
            inst = runCatching {
                XposedHelpers.getStaticObjectField(compCls, n) }.getOrNull()
            if (inst != null) break
        }
        if (inst == null)
            inst = compCls.getDeclaredConstructor().also { it.isAccessible = true }
                .newInstance()
        inst.javaClass.methods.firstOrNull {
            it.name == "get" && it.parameterCount == 0 }?.invoke(inst)
    }.getOrNull()

    /** The REAL bean-level message service.
     *
     *  internal.core.MessageServiceImpl is a stub facade: its sendMessageV2 is
     *  `checkNotNullParameter` + `return-void` (dex 494574), getLatestMessage
     *  likewise (494118), and no dex code calls either. The live object is
     *  NativeMessageServiceImpl, exposed by the PUBLIC STATIC accessor
     *  MessageServiceImpl.a() (dex 493e24 -> instance_delegate$lambda$2), and
     *  IT declares the genuine beans API:
     *      v(MessageRequestV2, IIMCallback)            = sendMessageV2 (5d8ca8)
     *      e(Message, RegenDirection, IIMCallback)     = changeRegenMessage
     *      c(Z, MessageRequestV2, IIMCallback)         = addMessageV2
     *      l/m(String, IIMCallback)                    = getLatestMessage
     *  v() in turn calls OmniSDKHelper.getOmniSDK(NativeMessageServiceImpl.r())
     *  .withMessageService(legacy/a4) (5da834) — the true network entry. */
    private fun realMessageService(cl: ClassLoader? = null): Any? {
        beanSvc?.let { if (it.javaClass.name == NATIVE_MSG_SVC_CLS) return it }
        return runCatching {
            val facade = XposedHelpers.findClass(MSG_SVC_CLS, cl ?: hookCl)
            val inst = facade.methods.firstOrNull {
                it.name == "a" && it.parameterCount == 0 &&
                    Modifier.isStatic(it.modifiers) }?.invoke(null)
            if (inst != null) beanSvc = inst
            inst
        }.getOrNull()
    }

    private fun liveConversationService(cl: ClassLoader): Any? = runCatching {
        val sdk = omniSdk(cl) ?: return@runCatching null
        var out: Any? = null
        val f1 = function1 { args -> out = args.firstOrNull() }
        val m = sdk.javaClass.methods.firstOrNull {
            it.name == "withConversationServiceSync" && it.parameterCount == 1 }
            ?: sdk.javaClass.methods.firstOrNull {
                it.name == "withConversationService" && it.parameterCount == 1 }
            ?: return@runCatching null
        m.invoke(sdk, f1)
        out
    }.getOrNull()

    private fun omniSdk(cl: ClassLoader): Any? = runCatching {
        val helperCls = XposedHelpers.findClass(OMNI_SDK_HELPER_CLS, cl)
        val helper = XposedHelpers.getStaticObjectField(helperCls, "INSTANCE")
        val userId = runCatching {
            XposedHelpers.callStaticMethod(
                XposedHelpers.findClass(NATIVE_MSG_SVC_CLS, cl), "r")
        }.getOrNull() as? String ?: ""
        helperCls.methods.firstOrNull {
            it.name == "getOmniSDK" && it.parameterCount == 2 }
            ?.invoke(helper, userId, false)
    }.getOrNull()

    /** Dynamic proxy implementing kotlin.jvm.functions.Function1. */
    private fun function1(sink: (List<Any?>) -> Unit): Any {
        val cls = XposedHelpers.findClass(FUNCTION1_CLS, hookCl)
        return Proxy.newProxyInstance(cls.classLoader, arrayOf(cls)) { _, m, a ->
            when (m.name) {
                "invoke" -> { sink(a?.toList() ?: emptyList()); null }
                "getArity" -> 1
                else -> if (m.returnType ==
                        Boolean::class.javaPrimitiveType) false else null
            }
        }
    }

    // ---------- tier 1: bean clone ----------

    private fun cloneBeanSend(bean: Any, text: String, cid: String): String? {
        return try {
            val meta = prop(bean, "clientMeta")
            val newMeta = if (meta != null && cid.isNotEmpty())
                copyBean(meta, mapOf("conversationId" to cid,
                                     "localConversationId" to cid)) else meta
            val msgs = (prop(bean, "requestMessages") as? List<*>)
                ?.filterNotNull()?.map { cloneRequestMessage(it, text) }
                ?: listOf(buildRequestMessage(text, ""))
            val tc = prop(bean, "trackContext")
            val newTc = if (tc != null) copyBean(tc,
                mapOf("businessSendStartTimestamp" to
                    System.currentTimeMillis())) else null
            val newBean = copyBean(bean, mapOf(
                "clientMeta" to newMeta,
                "requestMessages" to msgs,
                "trackContext" to newTc))
            val svc = realMessageService()
                ?: return "NativeMessageServiceImpl 不可用"
            // the real beans-API send is v(MessageRequestV2, IIMCallback)
            val m = svc.javaClass.methods.firstOrNull {
                it.name == "v" && it.parameterCount == 2 }
                ?: svc.javaClass.methods.firstOrNull {
                    it.name == "sendMessageV2" && it.parameterCount == 2 }
                ?: return "sendMessageV2 不可用"
            asSelfSend { m.invoke(svc, newBean, newIimCallback()) }
            XposedBridge.log("$TAG bean send ok")
            null
        } catch (t: Throwable) {
            "bean 发送失败: ${t.cause?.message ?: t.message ?: t}"
        }
    }

    /** Clone a captured RequestMessage: fresh local id, same sender/blocks,
     *  text swapped inside the (single) TextBlock of each BlockContent. */
    private fun cloneRequestMessage(msg: Any, text: String): Any {
        val blocks = (prop(msg, "contentBlock") as? List<*>)?.map { b ->
            if (b == null) return@map null
            val tb = prop(b, "textBlock") ?: return@map b
            copyBean(b, mapOf("textBlock" to
                copyBean(tb, mapOf("text" to text))))
        }
        val localId = UUID.randomUUID().toString()
        // interruptMessage wants the local id of the message we sent (dex:
        // group/f.c = $lastSendLocalMsgId) — remember the one we just minted.
        sentLocalMsgId = localId
        sentServerMsgId = ""
        persistIds()
        return copyBean(msg, mapOf(
            "localMessageId" to localId,
            "brief" to text.take(100),
            "contentBlock" to blocks))
    }

    // ---------- tier 2: native template replay ----------

    private fun nativeSend(req: Any, text: String, cid: String): String? {
        val m = sendMethod ?: return "sendMessageV2 未捕获"
        return try {
            val newReq = cloneReq(req, text, cid)
            val args = (sendArgs ?: return "无参数模板").copyOf()
            val idx = args.indexOfFirst { it?.javaClass?.name == REQ_CLS }
            if (idx >= 0) args[idx] = newReq
            // swap the captured OmniIMCallback for a fresh proxy so the ack
            // doesn't get delivered to a stale UI handler
            for (i in args.indices) if (args[i] != null &&
                cbClass?.isInstance(args[i]) == true) {
                args[i] = newCallback()
            }
            m.isAccessible = true
            val r = asSelfSend { m.invoke(sendThis, *args) }
            XposedBridge.log("$TAG send ok ret=$r")
            null
        } catch (t: Throwable) {
            "调用失败: ${t.message ?: t}"
        }
    }

    // ---------- tier 3: build from scratch (会话→构造请求) ----------

    /** No template: resolve the conversation first (as the UI does), pull the
     *  sender uid off the latest message, then construct MessageRequestV2. */
    private fun scratchSend(text: String, cid: String): String? {
        val cl = hookCl ?: return "无 classloader"
        if (cid.isEmpty()) return "无会话id"
        return try {
            val conv = fetchConversation(cl, cid)
            val botId = conv?.let { findStringDeep(it,
                setOf("botId", "bot_id"), 3) } ?: ""
            if (botId.isNotEmpty()) lastBotId = botId
            val senderId = fetchSenderId(cl, cid) ?: ""
            XposedBridge.log("$TAG scratch conv=${
                conv?.javaClass?.simpleName} bot=$botId sender=$senderId")

            val meta = newInstance("com.larus.im.bean.message.ClientMeta")
                ?: return "ClientMeta 构造失败"
            setF(meta, "conversationId", cid)
            setF(meta, "localConversationId", cid)
            if (botId.isNotEmpty()) setF(meta, "botId", botId)

            val opt = newInstance("com.larus.im.bean.message.ChatQueryOption")
            opt?.let {
                setF(it, "uniqueKey", UUID.randomUUID().toString())
                setF(it, "createTimeMs", System.currentTimeMillis())
            }
            val msg = buildRequestMessage(text, senderId)
            val scene = runCatching {
                XposedHelpers.getStaticObjectField(
                    XposedHelpers.findClass(
                        "com.larus.im.bean.message.MessageRequestType", cl),
                    "SEND_TEXT") }.getOrNull()
            val track = newInstance(
                "com.larus.im.bean.message.MessageTrackContext")?.also {
                setF(it, "businessSendStartTimestamp",
                    System.currentTimeMillis())
                setF(it, "commonTags", HashMap<Any, Any>())
            }

            val reqCls = XposedHelpers.findClass(BEAN_REQ_CLS, cl)
            val req = reqCls.getDeclaredConstructor(
                XposedHelpers.findClass(
                    "com.larus.im.bean.message.MessageRequestType", cl),
                XposedHelpers.findClass(
                    "com.larus.im.bean.message.ClientMeta", cl),
                List::class.java,
                XposedHelpers.findClass(
                    "com.larus.im.bean.message.ChatQueryOption", cl),
                XposedHelpers.findClass(
                    "com.larus.im.bean.message.ChatAbility", cl),
                Map::class.java, List::class.java, List::class.java,
                XposedHelpers.findClass(
                    "com.larus.im.bean.message.MessageTrackContext", cl))
                .newInstance(scene, meta, listOf(msg), opt, null,
                    HashMap<Any, Any>(), ArrayList<Any>(), ArrayList<Any>(),
                    track)

            val svc = realMessageService()
                ?: return "NativeMessageServiceImpl 不可用"
            val vm = svc.javaClass.methods.firstOrNull {
                it.name == "v" && it.parameterCount == 2 }
                ?: svc.javaClass.methods.firstOrNull {
                    it.name == "sendMessageV2" && it.parameterCount == 2 }
                ?: return "sendMessageV2 不可用"
            asSelfSend { vm.invoke(svc, req, newIimCallback()) }
            XposedBridge.log("$TAG scratch send ok")
            null
        } catch (t: Throwable) {
            "无模板构造发送失败: ${t.cause?.message ?: t.message ?: t}"
        }
    }

    /** getConversation on the REAL conversation service (Companion.get() ->
     *  NativeConversationServiceImpl, 126 code units) — the old version called
     *  ConversationServiceImpl.getConversation, which is a 6-code-unit no-op
     *  stub, so the latch always ran out its full 2500 ms timeout.
     *  Synchronous wait on the IIMCallback (we're already off-main). */
    private fun fetchConversation(cl: ClassLoader, cid: String): Any? {
        val latch = CountDownLatch(1)
        val out = arrayOfNulls<Any>(1)
        val cb = newIimCallback { o -> out[0] = o; latch.countDown() }
        val svc = conversationService(cl) ?: newInstance(CONV_SVC_CLS)
            ?: return null
        val m = svc.javaClass.methods.firstOrNull {
            it.name == "getConversation" && it.parameterCount == 5 }
            ?: return null
        runCatching { m.invoke(svc, cid, false, cb, null, null) }
        latch.await(2500, TimeUnit.MILLISECONDS)
        return out[0]
    }

    /** sender uid := senderId of the user's latest message in this conv. */
    private fun fetchSenderId(cl: ClassLoader, cid: String): String? {
        val latch = CountDownLatch(1)
        val out = arrayOfNulls<Any>(1)
        val cb = newIimCallback { o -> out[0] = o; latch.countDown() }
        val svc = realMessageService(cl) ?: return null
        val m = svc.javaClass.methods.firstOrNull {
            it.name == "getLatestMessage" && it.parameterCount == 2 }
            ?: svc.javaClass.methods.firstOrNull {
                (it.name == "l" || it.name == "m") && it.parameterCount == 2 }
            ?: return null
        runCatching { m.invoke(svc, cid, cb) }
        latch.await(2500, TimeUnit.MILLISECONDS)
        // onSuccess may hand us OmniMessage or a wrapper — dig for senderId
        return out[0]?.let { findStringDeep(it, setOf("senderId"), 3) }
    }

    private fun buildRequestMessage(text: String, senderId: String): Any {
        val tb = newInstance("com.larus.im.bean.message.block.TextBlock")
            ?: throw IllegalStateException("TextBlock 构造失败")
        setF(tb, "text", text)
        val bc = newInstance("com.larus.im.bean.message.block.BlockContent")
            ?: throw IllegalStateException("BlockContent 构造失败")
        setF(bc, "textBlock", tb)
        val msg = newInstance("com.larus.im.bean.message.RequestMessage")
            ?: throw IllegalStateException("RequestMessage 构造失败")
        val localId = UUID.randomUUID().toString()
        sentLocalMsgId = localId
        sentServerMsgId = ""
        persistIds()
        setF(msg, "localMessageId", localId)
        setF(msg, "contentBlock", listOf(bc))
        setF(msg, "brief", text.take(100))
        if (senderId.isNotEmpty()) setF(msg, "senderId", senderId)
        setF(msg, "bizContentType", "text")
        return msg
    }

    // ---------- bean helpers ----------

    /** Kotlin data-class copy() with named-property replacements.
     *  componentN() order == copy() param order; each property name is matched
     *  to its component index by comparing the getter value against
     *  componentN() values. */
    private fun copyBean(obj: Any, repl: Map<String, Any?>): Any {
        val cls = obj.javaClass
        val copy = cls.declaredMethods.first {
            it.name == "copy" && !Modifier.isStatic(it.modifiers) }
        val n = copy.parameterCount
        val comps = Array(n) { i ->
            cls.getMethod("component${i + 1}").invoke(obj) }
        val idxOf = HashMap<String, Int>()
        for (m in cls.methods) {
            if (m.parameterCount != 0) continue
            val name = m.name
            val prop = when {
                name.startsWith("get") && name.length > 3 ->
                    name[3].lowercase() + name.substring(4)
                name.startsWith("is") && name.length > 2 ->
                    name[2].lowercase() + name.substring(3)
                else -> continue
            }
            val v = try { m.invoke(obj) } catch (_: Throwable) { continue }
            for (i in 0 until n) if (comps[i] == v && prop !in idxOf) {
                idxOf[prop] = i; break }
        }
        val vals = comps.copyOf()
        for ((k, v) in repl) idxOf[k]?.let { vals[it] = v }
        copy.isAccessible = true
        return copy.invoke(obj, *vals)
    }

    /** Read a Kotlin property via its getter, null-safe. */
    private fun prop(obj: Any, name: String): Any? {
        val cap = name[0].uppercase() + name.substring(1)
        for (n in arrayOf("get$cap", "is$cap")) {
            val m = runCatching { obj.javaClass.getMethod(n) }.getOrNull()
                ?: continue
            if (m.parameterCount == 0)
                return runCatching { m.invoke(obj) }.getOrNull()
        }
        // last resort: direct field
        return runCatching {
            val f = obj.javaClass.getDeclaredField(name)
            f.isAccessible = true; f.get(obj)
        }.getOrNull()
    }

    private fun setF(obj: Any, name: String, v: Any?) {
        var k: Class<*>? = obj.javaClass
        while (k != null && k != Any::class.java) {
            try {
                val f = k.getDeclaredField(name)
                f.isAccessible = true
                f.set(obj, v)
                return
            } catch (_: NoSuchFieldException) {
                k = k.superclass
            }
        }
        XposedBridge.log("$TAG setF $name miss on ${obj.javaClass.simpleName}")
    }

    private fun newInstance(clsName: String): Any? = runCatching {
        XposedHelpers.findClass(clsName, hookCl)
            .getDeclaredConstructor().apply { isAccessible = true }
            .newInstance()
    }.getOrNull()

    /** BFS over fields/getters looking for a String property by name. */
    private fun findStringDeep(o: Any, names: Set<String>, depth: Int): String? {
        if (depth < 0) return null
        for (n in names) (prop(o, n) as? String)?.let {
            if (it.isNotEmpty()) return it }
        if (depth == 0) return null
        var k: Class<*>? = o.javaClass
        while (k != null && k != Any::class.java) {
            for (f in k.declaredFields) {
                try {
                    f.isAccessible = true
                    val v = f.get(o) ?: continue
                    if (v.javaClass.name.startsWith("java.") ||
                        v.javaClass.name.startsWith("kotlin.")) continue
                    findStringDeep(v, names, depth - 1)?.let { return it }
                } catch (_: Throwable) {}
            }
            k = k.superclass
        }
        return null
    }

    // ---------- native request clone (tier 2 machinery) ----------

    /** Kotlin data-class copy(): param order == componentN() order, which is
     *  NOT the declaredFields order (isResendScene sits mid-declaration) — the
     *  earlier positional mismatch came from that. Read values via
     *  componentN(), edit each String component as a JSON payload, then call
     *  copy(...). Only requestMessagesJsonStr gets the body-text swap. */
    private fun cloneReq(req: Any, text: String, cid: String): Any {
        val cls = req.javaClass
        val copy = cls.declaredMethods.first {
            it.name == "copy" && !Modifier.isStatic(it.modifiers) }
        val n = copy.parameterCount
        val vals = arrayOfNulls<Any>(n)
        for (i in 0 until n)
            vals[i] = cls.getMethod("component${i + 1}").invoke(req)

        // the message-body field, matched by identity against its component
        val msgFieldVal = cls.declaredFields
            .firstOrNull { it.name == "requestMessagesJsonStr" }
            ?.let { it.isAccessible = true; it.get(req) }

        for (i in 0 until n) {
            val v = vals[i]
            if (v is String)
                vals[i] = editJsonPayload(v, v === msgFieldVal, text, cid)
        }
        copy.isAccessible = true
        return copy.invoke(req, *vals)
    }

    /** Edit one *JsonStr payload: inside JSON, keys that hold conversation ids
     *  get `cid`, uuid-ish ids are regenerated, and (only when editText) the
     *  content/text/query string leaves become `text`. Non-JSON values are
     *  left alone except a bare string equal to the template cid. */
    private fun editJsonPayload(v: String, editText: Boolean,
                                text: String, cid: String): String {
        if (v == templateCid && cid.isNotEmpty() && templateCid.length > 5)
            return cid
        val node: Any = try {
            if (v.startsWith("[")) JSONArray(v)
            else if (v.startsWith("{")) JSONObject(v)
            else return v
        } catch (e: Exception) { return v }
        editNode(node, if (editText) text else null, cid)
        return node.toString()
    }

    private val CID_KEYS = Regex("(?i)^(conversation_id|local_conversation_id|" +
        "chat_id|conv_id|conversationId)$")
    private val ID_KEYS = Regex("(?i)(message_id|msg_id|local_message_id|" +
        "client_message_id|uuid|trace_id|request_id|log_id|^_id$|^id$|^key$)")
    private val TEXT_KEYS = Regex("(?i)^(text|content|query|send_content|" +
        "plain_text|input)$")
    private val UUID_RE = Regex("^[0-9a-fA-F-]{32,36}$")

    private fun editNode(n: Any, text: String?, cid: String) {
        when (n) {
            is JSONObject -> {
                for (k in n.keys().asSequence().toList()) {
                    val v = n.opt(k)
                    when {
                        // conversation id slots
                        cid.isNotEmpty() && CID_KEYS.matches(k) &&
                            v is String && v.isNotEmpty() -> n.put(k, cid)
                        v is String && v == templateCid &&
                            templateCid.length > 5 && cid.isNotEmpty() ->
                            n.put(k, cid)
                        // fresh client ids
                        v is String && ID_KEYS.matches(k) &&
                            UUID_RE.matches(v) ->
                            n.put(k, UUID.randomUUID().toString())
                        // message body: the value may itself be a JSON string
                        // of content blocks — recurse into it
                        TEXT_KEYS.matches(k) && v is String &&
                            text != null -> {
                            val inner = tryInnerJson(v, text, cid)
                            n.put(k, inner ?: text)
                        }
                        v is JSONObject || v is JSONArray -> editNode(v, text, cid)
                    }
                }
            }
            is JSONArray -> for (i in 0 until n.length()) {
                val v = n.opt(i)
                if (v is JSONObject || v is JSONArray) editNode(v, text, cid)
            }
        }
    }

    /** If `s` is itself JSON containing text-ish leaves, edit those and
     *  return the re-serialized string; null when it isn't JSON. */
    private fun tryInnerJson(s: String, text: String?, cid: String): String? {
        val node: Any = try {
            if (s.startsWith("[")) JSONArray(s)
            else if (s.startsWith("{")) JSONObject(s) else return null
        } catch (e: Exception) { return null }
        editNode(node, text, cid)
        return node.toString()
    }

    // ---------- callbacks ----------

    /** Learn the server-side messageId of the message we just sent — the
     *  native interruptMessage wants it as `lastSendSuccessMsgId`
     *  (dex: group/f.b). Only accepted when the payload's localMessageId
     *  matches the id we minted, so an unrelated callback cannot poison it. */
    private fun recordServerId(o: Any?) {
        if (o == null) return
        try {
            val local = findStringDeep(o, setOf("localMessageId"), 3)
            if (!sentLocalMsgId.isNullOrEmpty() && local != null &&
                local != sentLocalMsgId) return
            val server = findStringDeep(o, setOf("messageId"), 3)
            if (!server.isNullOrEmpty() && server != sentLocalMsgId) {
                sentServerMsgId = server
                persistIds()
            }
        } catch (_: Throwable) {}
    }

    private fun newCallback(): Any? {
        val cb = cbClass ?: return null
        return try {
            Proxy.newProxyInstance(cb.classLoader, arrayOf(cb)) { _, m, a ->
                if (m.name == "onSuccess" || m.name == "onLocalFinish")
                    recordServerId(a?.firstOrNull())
                XposedBridge.log("$TAG cb ${m.name} " +
                    (a?.joinToString { it.toString().take(80) } ?: ""))
                if (m.returnType == Boolean::class.javaPrimitiveType) false
                else null
            }
        } catch (t: Throwable) {
            XposedBridge.log("$TAG cb proxy fail: $t"); null
        }
    }

    /** IIMCallback proxy for the bean-level API: mustInMain→false so the ack
     *  lands on the calling thread; onSuccess feeds the optional latch. */
    private fun newIimCallback(onOk: ((Any?) -> Unit)? = null): Any? {
        val cb = iimCbClass ?: return null
        return try {
            Proxy.newProxyInstance(cb.classLoader, arrayOf(cb)) { _, m, a ->
                when (m.name) {
                    "mustInMain" -> false
                    "onSuccess" -> {
                        XposedBridge.log("$TAG iim ok " +
                            (a?.firstOrNull()?.toString()?.take(120) ?: ""))
                        recordServerId(a?.firstOrNull())
                        runCatching { onOk?.invoke(a?.firstOrNull()) }
                        null
                    }
                    "onFailure" -> {
                        XposedBridge.log("$TAG iim fail " +
                            (a?.firstOrNull()?.toString()?.take(160) ?: ""))
                        runCatching { onOk?.invoke(null) }
                        null
                    }
                    else -> if (m.returnType ==
                            Boolean::class.javaPrimitiveType) false else null
                }
            }
        } catch (t: Throwable) {
            XposedBridge.log("$TAG iim proxy fail: $t"); null
        }
    }
}
