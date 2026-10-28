package com.example.dot_matrix_timer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import android.Manifest
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "dot_matrix_timer/screen"
    private val timerNotificationId = 1001
    private val timerNotificationChannel = "dot_matrix_timer_timer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "setLowRefresh" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        try {
                            val attrs = window.attributes
                            if (on) {
                                attrs.preferredRefreshRate = 1f
                            } else {
                                attrs.preferredRefreshRate = 0f
                            }
                            window.attributes = attrs
                        } catch (_: Exception) {
                            // Best effort; ignore unsupported cases.
                            try {
                                val attrs = window.attributes
                                attrs.preferredRefreshRate = 0f
                                window.attributes = attrs
                            } catch (_: Exception) {
                                // ignore
                            }
                        }
                        result.success(null)
                    }
                    "getScreenTimeout" -> {
                        val timeout = try {
                            Settings.System.getInt(
                                contentResolver,
                                Settings.System.SCREEN_OFF_TIMEOUT,
                                30000
                            )
                        } catch (_: Exception) {
                            30000
                        }
                        result.success(timeout)
                    }
                    "setDimmed" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        try {
                            val attrs = window.attributes
                            attrs.screenBrightness = if (on) 0.15f else WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = attrs
                        } catch (_: Exception) {
                            // best effort
                        }
                        result.success(null)
                    }
                    "showTimerNotification" -> {
                        val content = call.argument<String>("content") ?: ""
                        val total = call.argument<Int>("total")
                        val progress = call.argument<Int>("progress")
                        showTimerNotification(content, total, progress)
                        result.success(null)
                    }
                    "cancelTimerNotification" -> {
                        cancelTimerNotification()
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        val granted = requestNotificationPermission()
                        result.success(granted)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var pendingNotificationContent: String? = null

    private fun showTimerNotification(content: String, total: Int? = null, progress: Int? = null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                pendingNotificationContent = content
                pendingTotal = total
                pendingProgress = progress
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                return
            }
        }
        postTimerNotification(content, total, progress)
    }

    private var pendingTotal: Int? = null
    private var pendingProgress: Int? = null

    private fun postTimerNotification(content: String, total: Int? = null, progress: Int? = null) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                timerNotificationChannel,
                "Timer",
                NotificationManager.IMPORTANCE_LOW
            )
            nm.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = NotificationCompat.Builder(this, timerNotificationChannel)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Dot Matrix Timer")
            .setContentText(content)
            .setContentIntent(pi)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (total != null && progress != null && total > 0) {
            builder.setProgress(total, progress, false)
        }
        nm.notify(timerNotificationId, builder.build())
    }

    private fun cancelTimerNotification() {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(timerNotificationId)
        pendingNotificationContent = null
    }

    private fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return true
        }
        ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 2001)
        return false
    }

    private fun notifyDartPermissionResult(granted: Boolean) {
        flutterEngine?.let { engine ->
            MethodChannel(engine.dartExecutor.binaryMessenger, channelName).invokeMethod(
                "notificationPermissionResult", granted
            )
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001 && grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            pendingNotificationContent?.let { content ->
                postTimerNotification(content, pendingTotal, pendingProgress)
                pendingNotificationContent = null
                pendingTotal = null
                pendingProgress = null
            }
        }

        if (requestCode == 2001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            notifyDartPermissionResult(granted)
        }
    }
}
