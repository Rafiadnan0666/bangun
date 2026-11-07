# Security

## On-device only

All detection runs on-device via TensorFlow Lite. No frames are uploaded.

## No frame storage

Frames are processed in memory and discarded after detection.

## Permissions

- **Camera**: required for real-time object detection
- **Notification**: required to display full-screen alarm intent
- **Exact alarm**: required for准时 alarm delivery (Android 12+)

## Spotify integration

Notification access allows Spotify playback control when the alarm fires.
