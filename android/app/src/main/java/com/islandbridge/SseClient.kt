package com.islandbridge

import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** HTTP SSE client: subscribes http://host:port/events, dispatches each
 *  `data: <json>` frame to onLine. Reconnects with exponential backoff. */
class SseClient(private val onLine: (String) -> Unit) {
    var onState: ((String) -> Unit)? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        // server heartbeats every 15s — 45s silence means the socket is dead
        .readTimeout(45, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()
    private var call: okhttp3.Call? = null
    private val running = AtomicBoolean(false)
    private var host = ""; private var port = 8787
    private var attempt = 0
    private var gen = 0   // bumped on disconnect — stale retry threads die off

    fun connectTo(host: String, port: Int) {
        if (running.get() && this.host == host && this.port == port) return
        disconnect()
        this.host = host; this.port = port
        running.set(true)
        attempt = 0
        dial()
    }

    fun disconnect() {
        running.set(false)
        gen++
        call?.cancel()
        call = null
    }

    /** POST a reply to the PC daemon (POST /reply), which injects it into
     *  the Doubao desktop chat via CDP. cb gets (ok, detail). */
    fun postReply(text: String, cid: String, cb: (Boolean, String) -> Unit) {
        if (host.isEmpty()) { cb(false, "未配置电脑地址"); return }
        val url = "http://$host:$port/reply"
        Thread {
            try {
                val body = org.json.JSONObject().put("text", text)
                    .put("cid", cid).toString()
                    .toRequestBody("application/json".toMediaType())
                val req = Request.Builder().url(url).post(body).build()
                client.newCall(req).execute().use { resp ->
                    val o = org.json.JSONObject(resp.body?.string() ?: "{}")
                    cb(resp.isSuccessful && o.optBoolean("ok"),
                       o.optString("detail"))
                }
            } catch (e: Exception) {
                cb(false, e.message ?: "网络错误")
            }
        }.start()
    }

    private fun dial() {
        val g = gen
        if (!running.get()) return
        val url = "http://$host:$port/events"
        onState?.invoke("连接 $url …")
        Thread {
            try {
                val req = Request.Builder().url(url)
                    .header("Accept", "text/event-stream").build()
                val c = client.newCall(req)
                call = c
                c.execute().use { resp ->
                    if (!resp.isSuccessful) {
                        onState?.invoke("HTTP ${resp.code}")
                        return@Thread retry(g)
                    }
                    attempt = 0
                    onState?.invoke("已连接 $url")
                    val src = resp.body!!.source()
                    val data = StringBuilder()
                    while (running.get() && g == gen) {
                        val line = src.readUtf8Line() ?: break   // EOF
                        when {
                            line.isEmpty() -> {                 // frame end
                                if (data.isNotEmpty()) {
                                    onLine(data.toString())
                                    data.setLength(0)
                                }
                            }
                            line.startsWith(":") -> {}          // heartbeat
                            line.startsWith("data:") ->
                                data.append(line.removePrefix("data:").trimStart())
                        }
                    }
                }
            } catch (e: Exception) {
                if (running.get() && g == gen)
                    onState?.invoke("断开: ${e.message}")
            }
            retry(g)
        }.start()
    }

    private fun retry(g: Int) {
        if (!running.get() || g != gen) return
        val delay = minOf(15000, 1000 shl minOf(attempt++, 4)).toLong()
        onState?.invoke("${delay}ms 后重连")
        Thread {
            Thread.sleep(delay)
            if (g == gen) dial()
        }.start()
    }
}
