package com.example.dot_matrix_timer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.media.AudioAttributes
import android.os.Build
import androidx.core.app.NotificationCompat

class EndNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val channelId = "dot_matrix_timer_end_v3"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Remove any stale ongoing timer notification left from backgrounding.
        nm.cancel(1001)
        val soundUri = Uri.parse("android.resource://${context.packageName}/raw/end")
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Timer", NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(soundUri, audioAttributes)
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_dot_timer)
            .setColor(0xFF1B7F0E.toInt())
            .setContentTitle("Dot Matrix")
            .setContentText("Timer finished")
            .setSound(soundUri)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        nm.notify(1002, notification)
    }
}
