package com.jerrish18.us

import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "us/presentation").setMethodCallHandler { call, result ->
            if (call.method == "capabilities") {
                val seed = if (Build.VERSION.SDK_INT >= 31) getColor(android.R.color.system_accent1_500).toLong() and 0xffffffffL else null
                result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "seed" to seed))
            } else result.notImplemented()
        }
    }
}
