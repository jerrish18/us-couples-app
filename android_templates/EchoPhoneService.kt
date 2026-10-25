package com.jerrish18.us

import android.Manifest
import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/** User-started foreground readiness. Never launched silently after reboot. */
class EchoPhoneService : Service() {
    companion object { @Volatile var running=false }
    private val handler=android.os.Handler(android.os.Looper.getMainLooper())
    private val renew=object:Runnable{override fun run(){if(running){if(wake?.isHeld==true)wake?.release();wake?.acquire(2*60*60*1000L);handler.postDelayed(this,90*60*1000L)}}}
    private var wake:PowerManager.WakeLock?=null
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action=="us.echo.stop") { stopSelf(); return START_NOT_STICKY }
        if(running){EchoPhoneNative.current?.emit(mapOf("event" to "ready","running" to true));return START_NOT_STICKY}
        try {
            val manager=getSystemService(NotificationManager::class.java)
            if(Build.VERSION.SDK_INT>=26)manager.createNotificationChannel(NotificationChannel("us_echo_ready","ECHO on this phone",NotificationManager.IMPORTANCE_LOW))
            val open=PendingIntent.getActivity(this,170,Intent(this,MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val stop=PendingIntent.getService(this,171,Intent(this,EchoPhoneService::class.java).setAction("us.echo.stop"),PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val notification=NotificationCompat.Builder(this,"us_echo_ready").setSmallIcon(resources.getIdentifier("us_notification","drawable",packageName))
                .setContentTitle("ECHO is ready on this phone").setContentText("Phone AI ready · tap to open Us")
                .setContentIntent(open).addAction(android.R.drawable.ic_menu_close_clear_cancel,"Stop ECHO",stop)
                .setOngoing(true).setSilent(true).build()
            ServiceCompat.startForeground(this,170,notification,if(Build.VERSION.SDK_INT>=30)ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0)
            running=true
            // Keep the existing engine and signaling responsive while the screen locks.
            wake=(getSystemService(POWER_SERVICE) as PowerManager).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"Us:ECHO").apply{acquire(2*60*60*1000L)}
            handler.postDelayed(renew,90*60*1000L)
            EchoPhoneNative.current?.emit(mapOf("event" to "ready","running" to true))
        } catch(_:Exception) { running=false;stopSelf() }
        return START_NOT_STICKY
    }
    override fun onDestroy() {
        running=false
        handler.removeCallbacks(renew)
        if(wake?.isHeld==true)wake?.release()
        wake=null;stopForeground(STOP_FOREGROUND_REMOVE)
        EchoPhoneNative.current?.emit(mapOf("event" to "ready","running" to false))
        super.onDestroy()
    }
}
