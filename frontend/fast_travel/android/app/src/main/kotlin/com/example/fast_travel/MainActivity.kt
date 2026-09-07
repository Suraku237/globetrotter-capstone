package com.example.fast_travel

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "globetrotter/call_push")
            .setMethodCallHandler { call, result ->
                val journal = application as CallPushApplication
                when (call.method) {
                    "pendingEvents" -> result.success(journal.pendingEvents())
                    "ackEvent" -> {
                        journal.ackEvent(call.arguments as? String ?: "")
                        result.success(null)
                    }
                    "clearEvents" -> {
                        journal.clearEvents()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
