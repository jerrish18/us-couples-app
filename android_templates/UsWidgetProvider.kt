package com.jerrish18.us

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class UsWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, data: SharedPreferences) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(java.util.Date())
        val format = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        val since = data.getString("together_since", "") ?: ""
        val days = try { ((format.parse(today)!!.time - format.parse(since)!!.time) / 86400000).coerceAtLeast(0) } catch (_: Exception) { null }
        val mood = if (data.getString("mood_date", "") == today) data.getString("partner_mood", "") else ""
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.us_widget)
            views.setTextViewText(R.id.us_widget_days, if (days == null) "Us ♥" else "$days days together ♥")
            views.setTextViewText(R.id.us_widget_mood, if (mood.isNullOrEmpty()) "Open Us to check in" else "Your person feels $mood")
            val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            views.setOnClickPendingIntent(R.id.us_widget_root, PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            manager.updateAppWidget(id, views)
        }
    }
}
