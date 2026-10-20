package com.jerrish18.us

import android.app.Service
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

class UsCallService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val video = intent?.getBooleanExtra("video", false) == true
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("us_active_call", "Active calls", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 160, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val hangup = PendingIntent.getActivity(this, 161, Intent(this, MainActivity::class.java).setAction("us.end_call").addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(this, "us_active_call")
            .setSmallIcon(resources.getIdentifier("us_notification", "drawable", packageName))
            .setContentTitle(if (video) "Us video call" else "Us voice call")
            .setContentText("Tap to return to your call")
            .setContentIntent(open).addAction(android.R.drawable.ic_menu_close_clear_cancel, "End call", hangup).setOngoing(true).setCategory(NotificationCompat.CATEGORY_CALL).setSilent(true).build()
        val type = if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or (if(video) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0) else 0
        ServiceCompat.startForeground(this, 160, notification, type)
        return START_NOT_STICKY
    }
    override fun onDestroy() { stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy() }
}
