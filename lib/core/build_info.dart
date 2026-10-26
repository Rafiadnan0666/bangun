/// Build identity shown in the UI so a stale APK cannot be mistaken for the
/// current build during on-device testing.
///
/// Keep this in sync with `version:` in pubspec.yaml. Bump both together.
const String kAppVersion = '1.0.1';
const String kBuildStamp = 'v$kAppVersion build 2 - label fix';
