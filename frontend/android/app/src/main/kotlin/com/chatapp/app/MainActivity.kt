package com.chatapp.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val MEDIA_CHANNEL = "com.chatapp.app/media_projection"
    private val RINGTONE_CHANNEL = "com.chatapp.app/ringtone"
    private var systemRingtone: Ringtone? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "chat_messages",
                "Chat Messages",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Direct chat and encrypted messages"
                enableVibration(true)
                enableLights(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, MediaProjectionService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopService" -> {
                    val intent = Intent(this, MediaProjectionService::class.java)
                    stopService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RINGTONE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "playRingtone" -> {
                    try {
                        systemRingtone?.stop()
                        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                        systemRingtone = RingtoneManager.getRingtone(applicationContext, uri)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            systemRingtone?.isLooping = true
                        }
                        systemRingtone?.play()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERROR", e.localizedMessage, null)
                    }
                }
                "stopRingtone" -> {
                    try {
                        systemRingtone?.stop()
                        systemRingtone = null
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RINGTONE_ERROR", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

