package com.example.dot_matrix_timer

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.AssetFileDescriptor
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.SoundPool
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

    private var startPlayer: MediaPlayer? = null
    private var endPlayer: MediaPlayer? = null
    private var soundPool: SoundPool? = null
    private var startSoundId: Int = 0
    private var soundsLoaded: Boolean = false

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
                        val endMs = call.argument<Number>("endMs")?.toLong()
                        showTimerNotification(content, total, progress, endMs)
                        result.success(null)
                    }
                    "cancelTimerNotification" -> {
                        cancelTimerNotification()
                        result.success(null)
                    }
                    "playSound" -> {
                        val sfx = call.argument<String>("sfx") ?: ""
                        playSound(sfx)
                        result.success(null)
                    }
                    "stopSound" -> {
                        stopSoundFade()
                        result.success(null)
                    }
                    "preloadSounds" -> {
                        preloadSounds()
                        result.success(null)
                    }
                    "scheduleEndNotification" -> {
                        val endMs = call.argument<Number>("endMs")?.toLong()
                        if (endMs != null) scheduleEndNotification(endMs)
                        result.success(null)
                    }
                    "cancelEndNotification" -> {
                        cancelEndNotification()
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

    private fun showTimerNotification(content: String, total: Int? = null, progress: Int? = null, endMs: Long? = null) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                pendingNotificationContent = content
                pendingTotal = total
                pendingProgress = progress
                pendingEndMs = endMs
                ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                return
            }
        }
        postTimerNotification(content, total, progress, endMs)
    }

    private var pendingTotal: Int? = null
    private var pendingProgress: Int? = null
    private var pendingEndMs: Long? = null

    private fun postTimerNotification(content: String, total: Int? = null, progress: Int? = null, endMs: Long? = null) {
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
            .setSmallIcon(R.drawable.ic_stat_dot_timer)
            .setColor(0xFF1B7F0E.toInt())
            .setContentTitle("Dot Matrix")
            .setContentText(content)
            .setContentIntent(pi)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (endMs != null) {
            builder.setWhen(endMs)
                .setUsesChronometer(true)
            try {
                builder.setChronometerCountDown(true)
            } catch (_: Exception) {
                // Older platform/compat variants may not support countdown.
            }
        }
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
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                pendingNotificationContent?.let { content ->
                    postTimerNotification(content, pendingTotal, pendingProgress, pendingEndMs)
                    pendingNotificationContent = null
                    pendingTotal = null
                    pendingProgress = null
                    pendingEndMs = null
                }
            }
            notifyDartPermissionResult(granted)
        }

        if (requestCode == 2001) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            notifyDartPermissionResult(granted)
        }
    }

    private fun soundEnabled(): Boolean {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        return am.ringerMode == AudioManager.RINGER_MODE_NORMAL
    }

    private fun preparePlayer(assetName: String): MediaPlayer? {
        return try {
            val resName = assetName.substringBeforeLast(".")
            val resId = resources.getIdentifier(resName, "raw", packageName)
            val afd: AssetFileDescriptor = if (resId != 0) {
                resources.openRawResourceFd(resId)
            } else {
                assets.openFd("flutter_assets/assets/sounds/$assetName")
            }
            val mp = MediaPlayer()
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
            )
            mp.prepare()
            mp
        } catch (e: Exception) {
            android.util.Log.e("DotMatrixTimerAudio", "preparePlayer failed for $assetName", e)
            null
        }
    }

    private fun playSound(sfx: String) {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (!soundEnabled()) {
            android.util.Log.w("DotMatrixTimerAudio", "playSound skipped: ringer not normal")
            return
        }
        try {
            if (sfx == "start") {
                if (startPlayer == null) startPlayer = preparePlayer("start.ogg")
                val p = startPlayer ?: return
                p.seekTo(0)
                p.start()
            } else if (sfx == "end") {
                if (endPlayer == null) endPlayer = preparePlayer("end.ogg")
                val p = endPlayer ?: return
                p.seekTo(0)
                p.start()
            }
        } catch (_: Exception) {}
    }

    private fun preloadSounds() {
        if (soundPool != null) return
        try {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            soundPool = SoundPool.Builder().setMaxStreams(4).setAudioAttributes(attrs).build()
            soundPool?.setOnLoadCompleteListener { _, sampleId, status ->
                if (status == 0) {
                    startSoundId = sampleId
                    soundsLoaded = true
                    android.util.Log.d("DotMatrixTimerAudio", "SoundPool loaded $sampleId")
                }
            }
            val afd = try {
                resources.openRawResourceFd(R.raw.start)
            } catch (_: Exception) {
                assets.openFd("flutter_assets/assets/sounds/start.ogg")
            }
            startSoundId = soundPool?.load(afd, 1) ?: 0
            afd.close()
        } catch (e: Exception) {
            android.util.Log.e("DotMatrixTimerAudio", "preloadSounds failed", e)
        }
    }

    private fun stopSoundFade() {
        try {
            val p = endPlayer ?: return
            if (!p.isPlaying) return
            Thread {
                try {
                    for (i in 3 downTo 0) {
                        p.setVolume(i / 4f, i / 4f)
                        Thread.sleep(25)
                    }
                    p.stop()
                    p.setVolume(1f, 1f)
                } catch (_: Exception) {}
            }.start()
        } catch (_: Exception) {}
    }

    private fun scheduleEndNotification(endMs: Long) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, EndNotificationReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (am.canScheduleExactAlarms()) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endMs, pi)
                } else {
                    am.set(AlarmManager.RTC_WAKEUP, endMs, pi)
                }
            } else {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endMs, pi)
            }
        } catch (_: Exception) {
            try { am.set(AlarmManager.RTC_WAKEUP, endMs, pi) } catch (_: Exception) {}
        }
    }

    private fun cancelEndNotification() {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, EndNotificationReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            this, 0, intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        )
        if (pi != null) am.cancel(pi)
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .cancel(1002)
    }
}
