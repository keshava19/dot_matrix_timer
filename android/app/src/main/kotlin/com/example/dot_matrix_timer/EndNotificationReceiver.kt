package com.example.dot_matrix_timer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

class EndNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val channelId = "dot_matrix_timer_end_v2"
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Remove any stale ongoing timer notification left from backgrounding.
        nm.cancel(1001)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Timer", NotificationManager.IMPORTANCE_DEFAULT)
            nm.createNotificationChannel(channel)
        }
        val soundUri = Uri.parse("android.resource://${context.packageName}/raw/end")
        val notification = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_dot_matrix)
            .setContentTitle("Dot Matrix Timer")
            .setContentText("Timer finished")
            .setSound(soundUri)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        nm.notify(1002, notification)
    }
}
