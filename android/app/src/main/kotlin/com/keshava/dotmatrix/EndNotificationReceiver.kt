package com.keshava.dotmatrix

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat

object EndNotificationChannels {
    const val ID = "dot_matrix_timer_end_v4"

    private val legacyIds = listOf(
        "dot_matrix_timer_end",
        "dot_matrix_timer_end_v2",
        "dot_matrix_timer_end_v3",
    )

    fun soundUri(context: Context): Uri {
        // Referencing R.raw.end keeps it from being stripped by shrinkResources.
        // The URI stays name-based because notification channels persist it.
        val name = context.resources.getResourceEntryName(R.raw.end)
        return Uri.parse("android.resource://${context.packageName}/raw/$name")
    }

    fun ensure(context: Context, soundUri: Uri) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        cleanupLegacy(nm)

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val channel = NotificationChannel(
            ID,
            "Timer",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            setSound(soundUri, audioAttributes)
            enableVibration(true)
        }

        nm.createNotificationChannel(channel)
    }

    fun cleanupLegacy(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        cleanupLegacy(
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager,
        )
    }

    private fun cleanupLegacy(nm: NotificationManager) {
        legacyIds.forEach { nm.deleteNotificationChannel(it) }
    }
}

class EndNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Remove any stale ongoing timer notification left from backgrounding.
        nm.cancel(1001)

        // The foreground Flutter UI already plays the end chime; avoid double playback.
        if (MainActivity.isForeground) return

        val soundUri = EndNotificationChannels.soundUri(context)
        EndNotificationChannels.ensure(context, soundUri)

        val contentIntent = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, EndNotificationChannels.ID)
            .setSmallIcon(R.drawable.ic_stat_dot_timer)
            .setColor(0xFF1B7F0E.toInt())
            .setContentTitle("Dot Matrix")
            .setContentText("Timer finished")
            .setSound(soundUri)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()

        nm.notify(1002, notification)
    }
}
