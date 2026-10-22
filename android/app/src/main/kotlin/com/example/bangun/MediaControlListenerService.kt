package com.example.bangun

import android.service.notification.NotificationListenerService

/**
 * Minimal notification-listener service.
 *
 * Android only hands out [android.media.session.MediaController]s (which let
 * Bangun press play on Spotify) to apps that own a notification listener.
 * The service itself does nothing with notifications; it exists so the
 * MediaSessionManager grants the bridge in MainActivity access to Spotify's
 * session. The user enables it once in Settings > Notification access.
 */
class MediaControlListenerService : NotificationListenerService()
