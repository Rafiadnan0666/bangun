package com.example.bangun

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * "bangun/media" channel:
 *
 *  - canUseFullScreenIntent / openFullScreenIntentSettings
 *      Android 14+ silently drops full-screen intents (the alarm will not
 *      pop the ring screen) until the user allows "full screen
 *      notifications" for Bangun. These two calls let the app detect that
 *      and deep-link the user to the right settings page.
 *
 *  - hasNotificationAccess / openNotificationAccessSettings
 *      Notification access is what lets Bangun see Spotify's media session.
 *
 *  - spotifyPlay / spotifyIsPlaying
 *      Find Spotify's active MediaController and press play. This is what
 *      actually starts the playlist/song at ring time, instead of relying
 *      on Spotify honouring a deep-link autoplay switch.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "bangun/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(true)
                    }
                    "hasNotificationAccess" -> result.success(hasNotificationAccess())
                    "openNotificationAccessSettings" -> {
                        openNotificationAccessSettings()
                        result.success(true)
                    }
                    "spotifyPlay" -> result.success(spotifyPlay())
                    "spotifyIsPlaying" -> result.success(spotifyIsPlaying())
                    "spotifyPlayFromSearch" -> {
                        result.success(
                            spotifyPlayFromSearch(call.argument<String>("uri") ?: ""),
                        )
                    }
                    "bringToFront" -> {
                        bringToFront()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = getSystemService(NotificationManager::class.java) ?: return true
        return manager.canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.parse("package:$packageName")
                putExtra(Intent.EXTRA_PACKAGE_NAME, packageName)
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        } else {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
        }
        try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
            // Settings page unavailable on this OEM build; nothing else to do.
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        return flat.split(':').any { entry ->
            ComponentName.unflattenFromString(entry)?.packageName == packageName
        }
    }

    private fun openNotificationAccessSettings() {
        try {
            startActivity(
                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // Older OEMs may lack the screen; the user can enable it manually.
        }
    }

    private fun spotifyControllers(): List<MediaController> {
        if (!hasNotificationAccess()) return emptyList()
        return try {
            val manager = getSystemService(MediaSessionManager::class.java)
            val listener = ComponentName(this, MediaControlListenerService::class.java)
            manager.getActiveSessions(listener)
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun spotifyPlay(): Boolean {
        val controller = spotifyControllers().firstOrNull {
            it.packageName == "com.spotify.music"
        }
        if (controller != null) {
            try {
                controller.transportControls.play()
                return true
            } catch (_: Exception) {
                // Fall through to the notification action.
            }
        }
        return spotifyNotificationPlay()
    }

    /**
     * Presses the play/resume action inside Spotify's own media notification.
     * This is the same PendingIntent the user would tap; it works even when
     * Spotify exposes no MediaController (e.g. right after a cold launch).
     */
    private fun spotifyNotificationPlay(): Boolean {
        if (!hasNotificationAccess()) return false
        val manager = getSystemService(NotificationManager::class.java) ?: return false
        return try {
            for (sbn in manager.activeNotifications) {
                if (sbn.packageName != "com.spotify.music") continue
                val actions = sbn.notification.actions ?: continue
                for (action in actions) {
                    val title = action.title?.toString()?.lowercase() ?: ""
                    if (title.contains("play") || title.contains("resume")) {
                        try {
                            action.actionIntent.send()
                            return true
                        } catch (_: Exception) {
                            // Try the next action.
                        }
                    }
                }
            }
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Android's "play from search" intent, pointed at Spotify with the item
     * URI as data. This is a second native path that starts playback directly
     * on builds where the `:play` deep-link switch is ignored.
     */
    private fun spotifyPlayFromSearch(uri: String): Boolean {
        if (uri.isBlank()) return false
        return try {
            val intent = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH).apply {
                data = Uri.parse(uri)
                setPackage("com.spotify.music")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun spotifyIsPlaying(): Boolean {
        val controller = spotifyControllers().firstOrNull {
            it.packageName == "com.spotify.music"
        } ?: return false
        return controller.playbackState?.state ==
            android.media.session.PlaybackState.STATE_PLAYING
    }

    /**
     * Re-asserts the alarm screen over an external app (Spotify, Chrome).
     *
     * Once Bangun opens Spotify at ring time, Spotify owns the foreground and
     * the gate disappears behind it. Android blocks plain background activity
     * launches, but an active alarm app is allowed a full-screen intent; this
     * posts a silent, alarm-category notification with a full-screen intent
     * to MainActivity, which brings the ring/challenge screen right back on
     * top while Spotify keeps playing underneath.
     */
    private fun bringToFront() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_REORDER_TO_FRONT,
            )
        }
        val pending = PendingIntent.getActivity(
            this,
            BRING_BACK_REQUEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                BRING_BACK_CHANNEL,
                "Alarm gate",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(this, BRING_BACK_CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("Finish the gate")
            .setContentText("Your alarm is still ringing")
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setFullScreenIntent(pending, true)
            .setAutoCancel(true)
            .build()
        manager.notify(BRING_BACK_REQUEST, notification)
    }

    private companion object {
        const val BRING_BACK_REQUEST = 4242
        const val BRING_BACK_CHANNEL = "bangun_gate_return"
    }
}
