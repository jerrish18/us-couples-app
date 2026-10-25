package com.jerrish18.us

import android.os.Build
import android.content.Context
import io.flutter.embedding.engine.FlutterEngineCache
import android.content.Intent
import android.content.pm.PackageManager
import android.view.HapticFeedbackConstants
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    override fun shouldDestroyEngineWithHost(): Boolean = false
    override fun provideFlutterEngine(context: Context): FlutterEngine? = FlutterEngineCache.getInstance().get("us-main")
    private var presentation: MethodChannel? = null
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == "us.end_call") presentation?.invokeMethod("endCall", null)
    }
    private var nearbyResult: MethodChannel.Result? = null
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1606) { nearbyResult?.success(grantResults.all { it == PackageManager.PERMISSION_GRANTED }); nearbyResult = null }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("us-main",flutterEngine)
        if(EchoPhoneNative.current?.attachedTo(flutterEngine)!=true) EchoPhoneNative(applicationContext,flutterEngine)
        presentation = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "us/presentation")
        presentation!!.setMethodCallHandler { call, result ->
            if (call.method == "capabilities") {
                val seed = if (Build.VERSION.SDK_INT >= 31) getColor(android.R.color.system_accent1_500).toLong() and 0xffffffffL else null
                result.success(mapOf("sdk" to Build.VERSION.SDK_INT, "seed" to seed))
            } else if (call.method == "callPermissions") {
                val needed = mutableListOf<String>()
                if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission("android.permission.BLUETOOTH_CONNECT") != PackageManager.PERMISSION_GRANTED) needed.add("android.permission.BLUETOOTH_CONNECT")
                if (Build.VERSION.SDK_INT >= 37 && checkSelfPermission("android.permission.ACCESS_LOCAL_NETWORK") != PackageManager.PERMISSION_GRANTED) needed.add("android.permission.ACCESS_LOCAL_NETWORK")
                if (needed.isEmpty()) result.success(true)
                else if (nearbyResult != null) result.success(false)
                else { nearbyResult = result; requestPermissions(needed.toTypedArray(), 1606) }
            } else if (call.method == "haptic") {
                val kind = call.argument<String>("kind")
                val feedback = when {
                    kind == "confirm" && Build.VERSION.SDK_INT >= 30 -> HapticFeedbackConstants.CONFIRM
                    kind == "reject" && Build.VERSION.SDK_INT >= 30 -> HapticFeedbackConstants.REJECT
                    else -> HapticFeedbackConstants.CLOCK_TICK
                }
                result.success(window.decorView.performHapticFeedback(feedback))
            } else if (call.method == "startCall") {
                try {
                    ContextCompat.startForegroundService(this, Intent(this, UsCallService::class.java).putExtra("video", call.argument<Boolean>("video") == true))
                    result.success(true)
                } catch (e: Exception) { result.error("call_service", "Could not keep this call active in the background", null) }
            } else if (call.method == "stopCall") {
                stopService(Intent(this, UsCallService::class.java)); result.success(true)
            } else result.notImplemented()
        }
    }
}
