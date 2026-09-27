package com.islandbridge.xposed

import org.json.JSONArray
import org.json.JSONObject

/** Parses Doubao *Android* SSE chunks (captured inside com.larus.nova via
 *  OmniHttpCallByNative.writeChunkData) into the same normalized events the
 *  PC bridge emits: chat.start/delta/end/reply, plan.start/progress/end.
 *
 *  Field shapes per D:\aiwork\apk\REVERSE_NOTES:
 *    /text_block/text, /thinking_block/summary, /patch_value/content,
 *    /msg_finish_attr/brief, complex_task_block{thread_id,title,status},
 *    thread_info via /im/thread/info, /im/chain/thread_message.
 *
 *  The walker is deliberately defensive: it recursively scans every JSON
 *  node and reacts to known keys, so unknown envelope nesting is tolerated.
 */
class MobileFeedParser(private val emit: (JSONObject) -> Unit) {

    private var buf = StringBuilder()
    private var started = false
    private var mid = "m0"
    private var cid = ""                          // current conversation_id
    private val convNames = HashMap<String, String>()  // cid -> title
    private var text = StringBuilder()
    private var lastThink = ""
    private val threads = LinkedHashMap<String, JSONObject>()
    private var planStarted = false

    fun feedBytes(b: ByteArray) = feed(String(b, Charsets.UTF_8))

    // ---------- OmniMessage path ----------
    // Doubao Android delivers streaming replies through
    // OmniMessageDispatcher.onStreamingMessage(String, OmniMessage, ...)
    // rather than HTTP writeChunkData. OmniMessage.content is a cumulative
    // JSON array of content blocks ([{block_id, block_type, content:{...}}]),
    // the same schema the desktop SSE carries. We diff per block_id so
    // re-feeding a grown snapshot only emits the new tail.
    private val blockText = HashMap<String, String>()   // block_id -> emitted text

    fun feedOmniMessage(mid0: String, cid0: String,
                        brief: String, contentJson: String) {
        if (mid0.isNotEmpty()) mid = mid0
        if (cid0.isNotEmpty()) cid = cid0
        try {
            val arr = JSONArray(contentJson)
            for (i in 0 until arr.length()) {
                val b = arr.optJSONObject(i) ?: continue
                val bid = b.optString("block_id").ifEmpty { "#$i" }
                val inner = b.optJSONObject("content") ?: continue
                emitGrown(bid + ":t",
                    inner.optJSONObject("text_block")?.optString("text") ?: "",
                    "text")
                emitGrown(bid + ":k",
                    inner.optJSONObject("thinking_block")?.let {
                        it.optString("streaming_title").ifEmpty {
                            it.optString("summary") }.ifEmpty {
                            it.optString("title") } } ?: "", "think")
                inner.optJSONObject("complex_task_block")?.let { ctb ->
                    val tid = ctb.optString("thread_id")
                        .ifEmpty { ctb.optString("id") }
                    if (tid.isNotEmpty()) noteThread(tid, ctb)
                }
            }
        } catch (e: Exception) { }
        // brief is the accumulated plain text — backstop if blocks lack text
        if (brief.isNotEmpty() && text.isEmpty()) {
            val prev = blockText["#brief"] ?: ""
            if (brief != prev && brief.startsWith(prev)) {
                emitGrown("#brief", brief, "text")
            }
        }
    }

    private fun emitGrown(key: String, cur: String, kind: String) {
        if (cur.isEmpty()) return
        val prev = blockText[key] ?: ""
        if (cur == prev) return
        val delta = if (cur.startsWith(prev)) cur.substring(prev.length)
                    else cur                          // non-prefix: resend whole
        blockText[key] = cur
        if (delta.isEmpty()) return
        startChat()
        if (kind == "text") text.append(delta)
        emit(conv(JSONObject().put("t", "chat.delta").put("mid", mid)
            .put("kind", kind).put("text", delta)))
    }

    fun finishOmni(mid0: String = "") {
        if (mid0.isNotEmpty()) mid = mid0
        endChat()
    }

    fun feed(s: String) {
        buf.append(s)
        // split SSE frames on blank line
        var i: Int
        while (true) {
            i = buf.indexOf("\n\n")
            if (i < 0) break
            val frame = buf.substring(0, i)
            buf.delete(0, i + 2)
            handleFrame(frame)
        }
        // a whole JSON body may arrive without SSE framing — try whole buffer
        tryJson(buf.toString().trim())?.let { buf.setLength(0) }
    }

    // ---------- frames ----------
    private fun handleFrame(frame: String) {
        val data = StringBuilder()
        var eventName = ""
        for (line in frame.split("\n")) {
            when {
                line.startsWith("data:") ->
                    data.append(line.removePrefix("data:").trimStart())
                line.startsWith("event:") ->
                    eventName = line.removePrefix("event:").trim()
            }
        }
        if (eventName.contains("REPLY_END") || eventName.contains("END"))
            endChat()
        // FULL_MSG_NOTIFY echoes the just-sent USER message back — desktop
        // ignores it entirely; without this its text_block leaks to the island
        if (eventName == "FULL_MSG_NOTIFY") return
        // CHUNK_DELTA frames are bare {"text": ...} reply increments —
        // no envelope, no text_block wrapper. Handle directly; a generic
        // walk would double-count the "text" key inside other blocks.
        if (eventName.contains("CHUNK_DELTA")) {
            val s0 = data.toString()
            try {
                val t = JSONObject(s0).optString("text")
                if (t.isNotEmpty() && mid !in userMids) {
                    startChat()
                    text.append(t)
                    emit(conv(JSONObject().put("t", "chat.delta").put("mid", mid)
                        .put("kind", "text").put("text", t)))
                }
            } catch (e: Exception) { }
            return
        }
        val s = data.toString()
        if (s.isEmpty() || s == "[DONE]") { if (s == "[DONE]") endChat(); return }
        tryJson(s)
    }

    private fun tryJson(s: String): JSONObject? {
        if (s.isEmpty()) return null
        return try {
            val o = JSONObject(s)
            walk(o)
            o
        } catch (e: Exception) {
            try {
                val a = JSONArray(s)
                for (i in 0 until a.length()) walk(a.opt(i))
                JSONObject()
            } catch (e2: Exception) { null }
        }
    }

    // ---------- recursive walk ----------
    private fun walk(n: Any?) {
        when (n) {
            is JSONObject -> {
                react(n)
                val it = n.keys()
                while (it.hasNext()) walk(n.opt(it.next()))
            }
            is JSONArray -> for (i in 0 until n.length()) walk(n.opt(i))
        }
    }

    // ids of messages sent BY the user (meta.user_type==1) — the SSE feed
    // echoes them back (FULL_MSG_NOTIFY) and we must not show them as replies
    private val userMids = HashSet<String>()

    private fun react(o: JSONObject) {
        // message id hints
        for (k in arrayOf("message_id", "msg_id", "mid", "server_message_id")) {
            val v = o.optString(k)
            if (v.isNotEmpty()) mid = v
        }
        o.optJSONObject("meta")?.let { meta ->
            // claim the real message_id before children are walked, so the
            // first text_block isn't emitted under the previous reply's mid
            val mm = meta.optString("message_id")
            if (mm.isNotEmpty()) mid = mm
            if (meta.optInt("user_type") == 1 && mm.isNotEmpty())
                userMids.add(mm)
            meta.optString("local_conversation_id").let {
                if (it.length > 5 && it != "0" && cid.isEmpty()) cid = it
            }
            // conversation id: STREAM_MSG_NOTIFY.meta
            meta.optString("conversation_id").let {
                if (it.length > 5 && it != "0") cid = it
            }
        }
        val cv = o.optString("conversation_id")
        if (cv.length > 5 && cv != "0") cid = cv
        // title pairing: {conversation_id, name} — e.g. conversation_info
        val nm = o.optString("name").ifEmpty { o.optString("title") }
        if (cv.length > 5 && cv != "0" && nm.isNotEmpty()
                && convNames[cv] != nm) {
            convNames[cv] = nm
            emit(JSONObject().put("t", "chat.conv")
                .put("cid", cv).put("cname", nm))
        }
        // stream begin
        val s = o.toString()
        if (s.contains("STREAM_MSG_NOTIFY") || s.contains("reply_begin"))
            startChat()

        // text block -> lyric/chat text (skipped for user-echo messages)
        val isUser = mid in userMids
        o.optJSONObject("text_block")?.let { tb ->
            val t = tb.optString("text").ifEmpty { tb.optString("append") }
            if (t.isNotEmpty() && !isUser) {
                startChat()
                text.append(t)
                emit(conv(JSONObject().put("t", "chat.delta").put("mid", mid)
                    .put("kind", "text").put("text", t)))
            }
        }
        // thinking block -> lyric line
        o.optJSONObject("thinking_block")?.let { tb ->
            val t = tb.optString("streaming_title").ifEmpty {
                tb.optString("summary") }.ifEmpty { tb.optString("title") }
            if (t.isNotEmpty() && t != lastThink && !isUser) {
                lastThink = t
                startChat()
                emit(conv(JSONObject().put("t", "chat.delta").put("mid", mid)
                    .put("kind", "think").put("text", t)))
            }
        }
        // finish markers
        if (o.has("msg_finish_attr") || s.contains("SSE_REPLY_END") ||
            o.has("fin_reason")) endChat()
        if (o.optInt("status") == 2 && s.contains("async_job")) endChat()

        // plan: complex_task_block / thread entries
        o.optJSONObject("complex_task_block")?.let { ctb ->
            val tid = ctb.optString("thread_id")
                .ifEmpty { ctb.optString("id") }
            if (tid.isNotEmpty()) noteThread(tid, ctb)
        }
        o.optJSONObject("thread_info")?.let { scanThreads(it) }
        // a bare object with thread_id + status counts as a thread too
        val tid = o.optString("thread_id")
        if (tid.isNotEmpty() && (o.has("status") || o.has("thread_status")))
            noteThread(tid, o)
    }

    private fun scanThreads(ti: JSONObject) {
        for (key in arrayOf("threads", "thread_list", "items")) {
            ti.optJSONArray(key)?.let { arr ->
                for (i in 0 until arr.length()) {
                    val t = arr.optJSONObject(i) ?: continue
                    val id = t.optString("thread_id").ifEmpty {
                        t.optString("id") }
                    if (id.isNotEmpty()) noteThread(id, t)
                }
            }
        }
    }

    private fun noteThread(id: String, t: JSONObject) {
        threads[id] = t
        if (!planStarted) {
            planStarted = true
            emit(JSONObject().put("t", "plan.start").put("tid", id)
                .put("title", t.optString("title").ifEmpty {
                    t.optString("name") }))
        }
        val done = threads.values.count { isDone(it.optString("status")
            .ifEmpty { it.optString("thread_status") }) }
        val cur = t.optString("title").ifEmpty { t.optString("name") }
        emit(JSONObject().put("t", "plan.progress")
            .put("done", done).put("total", threads.size).put("name", cur))
        if (done == threads.size && threads.isNotEmpty()) {
            emit(JSONObject().put("t", "plan.end")
                .put("success", true).put("text", "全部子任务完成"))
            threads.clear(); planStarted = false
        }
    }

    private fun isDone(s: String) = s in setOf(
        "completed", "complete", "done", "finished", "success", "3", "4")

    // ---------- chat lifecycle ----------
    /** Attach conversation fields (cid + resolved title) to an event. */
    private fun conv(o: JSONObject): JSONObject {
        if (cid.isNotEmpty()) {
            o.put("cid", cid)
            convNames[cid]?.let { o.put("cname", it) }
        }
        return o
    }

    private fun startChat() {
        if (started) return
        started = true
        emit(conv(JSONObject().put("t", "chat.start").put("mid", mid)))
    }

    private fun endChat() {
        if (!started) return
        started = false
        emit(conv(JSONObject().put("t", "chat.end").put("mid", mid)))
        if (text.isNotEmpty()) {
            emit(conv(JSONObject().put("t", "chat.reply").put("mid", mid)
                .put("text", text.toString())))
            text.setLength(0)
        }
        lastThink = ""
    }
}
