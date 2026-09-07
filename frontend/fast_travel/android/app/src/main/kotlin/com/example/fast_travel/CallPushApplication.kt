package com.example.fast_travel

import android.app.Application
import android.os.Bundle
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitEventCallback
import com.hiennv.flutter_callkit_incoming.FlutterCallkitIncomingPlugin
import org.json.JSONObject
import java.util.UUID

class CallPushApplication : Application(), CallkitEventCallback {
    override fun onCreate() {
        super.onCreate()
        // Application exists even when a notification action launches no Activity.
        FlutterCallkitIncomingPlugin.registerEventCallback(this)
    }

    override fun onCallEvent(event: CallkitEventCallback.CallEvent, callData: Bundle) {
        val raw = callData.getString(CallkitConstants.EXTRA_CALLKIT_ID) ?: return
        val id = try { UUID.fromString(raw).toString() } catch (_: Exception) { return }
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        if (!flutterPrefs.getBoolean("flutter.call_push_enabled", false) ||
            flutterPrefs.getBoolean("flutter.call_push_suppressed_$id", false)) return
        val action = if (event == CallkitEventCallback.CallEvent.ACCEPT) "accept" else "decline"
        synchronized(this) {
            val prefs = getSharedPreferences("call_push", MODE_PRIVATE)
            val events = JSONObject(prefs.getString("events", "{}") ?: "{}")
            val key = "$id:$action"
            events.put(key, JSONObject().put("key", key).put("id", id).put("action", action))
            // Synchronous disk write: Android may terminate us after the receiver returns.
            prefs.edit().putString("events", events.toString()).commit()
        }
    }

    @Synchronized
    fun pendingEvents(): List<Map<String, String>> {
        val prefs = getSharedPreferences("call_push", MODE_PRIVATE)
        val events = JSONObject(prefs.getString("events", "{}") ?: "{}")
        return events.keys().asSequence().map { key ->
            val value = events.getJSONObject(key)
            mapOf("key" to key, "id" to value.getString("id"), "action" to value.getString("action"))
        }.toList()
    }

    @Synchronized
    fun ackEvent(key: String) {
        val prefs = getSharedPreferences("call_push", MODE_PRIVATE)
        val events = JSONObject(prefs.getString("events", "{}") ?: "{}")
        events.remove(key)
        prefs.edit().putString("events", events.toString()).commit()
    }

    @Synchronized
    fun clearEvents() {
        getSharedPreferences("call_push", MODE_PRIVATE).edit().remove("events").commit()
    }
}
