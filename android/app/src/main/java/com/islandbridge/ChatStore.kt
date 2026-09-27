package com.islandbridge

import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject

/** Accumulates reply text per message and fans events out to the reply page. */
class ChatStore {
    private val main = Handler(Looper.getMainLooper())
    private val texts = LinkedHashMap<String, StringBuilder>()
    var listener: ((JSONObject) -> Unit)? = null   // MainActivity sets this

    fun handle(o: JSONObject) {
        when (o.optString("t")) {
            "chat.start" -> {
                texts[o.optString("mid")] = StringBuilder()
            }
            "chat.delta" -> {
                if (o.optString("kind") == "text")
                    texts[o.optString("mid")]?.append(o.optString("text"))
                forward(o)
            }
            "chat.reply" -> {
                val mid = o.optString("mid")
                val full = o.optString("text")
                    .ifBlank { texts[mid]?.toString() ?: "" }
                val evt = JSONObject(o.toString())
                evt.put("text", full)
                forward(evt)
                if (texts.size > 20) texts.remove(texts.keys.first())
            }
            else -> forward(o)
        }
    }

    private fun forward(o: JSONObject) {
        main.post { listener?.invoke(o) }
    }

    fun log(msg: String) {
        Log.i("IslandBridge", msg)
        try {
            forward(JSONObject().put("t", "sys.log").put("text", msg))
        } catch (e: Exception) { }
    }

    fun fullText(mid: String): String = texts[mid]?.toString() ?: ""
}
