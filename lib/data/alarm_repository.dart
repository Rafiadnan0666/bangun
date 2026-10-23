/// Alarm state + scheduling glue.
///
/// Owns the local [BangunAlarm] list, syncs every enabled alarm into the
/// native `alarm` plugin (exact next occurrence), tracks the ringing alarm id,
/// and records wake statistics.
///
/// "Cannot be closed" engineering:
///  * the ring notification has no stop button and is re-posted when swiped
///    (`androidStopAlarmOnDismiss: false`),
///  * `androidStopAlarmOnTermination: false` keeps the alarm audible through
///    process death — killing the app does not silence an active ring,
///  * the only in-app surface that stops a ring is challenge completion.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math show max;

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/format.dart';
import 'coco_detector.dart';
import 'models.dart';
import 'tone_files.dart';

/// Sentinel alarm id for "test challenge" runs (no native scheduling).
const int trialAlarmId = 0;

class AlarmRepository extends ChangeNotifier {
  static const _prefsKey = 'bangun.alarms.v2';
  static const _statsKey = 'bangun.stats.v2';

  SharedPreferences? _prefs;

  List<BangunAlarm> _alarms = const [];
  List<BangunAlarm> get alarms => List.unmodifiable(_alarms);

  WakeStats stats = WakeStats();

  int? _ringingId;
  int? get ringingId => _ringingId;
  BangunAlarm? get ringing {
    final id = _ringingId;
    return id == null ? null : byId(id);
  }

  BangunAlarm? byId(int id) =>
      id == trialAlarmId ? null : _alarms.where((a) => a.id == id).firstOrNull;

  /// Nearest enabled alarm and when it next rings.
  (BangunAlarm?, DateTime?) get nextOnAlarm {
    BangunAlarm? best;
    DateTime? bestAt;
    for (final a in _alarms) {
      if (!a.enabled) continue;
      final at = a.nextOccurrence();
      if (bestAt == null || at.isBefore(bestAt)) {
        bestAt = at;
        best = a;
      }
    }
    return (best, bestAt);
  }

  /// Loads state, asks for runtime permissions, re-syncs everything into the
  /// plugin, and warms the detector. Called once after `Alarm.init()`.
  Future<void> boot() async {
    // Start the model warm-up before touching preferences or the alarm plugin.
    // A storage/plugin failure must not leave the scan gate unable to load.
    unawaited(_warmDetector());
    _prefs = await SharedPreferences.getInstance();
    _load();

    // A one-shot whose slot passed while the app was dead must not be
    // re-armed for tomorrow. The native layer already tried (and may have
    // dropped it); retire it before syncing.
    final now = DateTime.now();
    var retired = false;
    for (final a in _alarms) {
      if (a.missedOneShot(now)) {
        a.enabled = false;
        retired = true;
      }
    }
    if (retired) {
      try {
        await _persist();
      } on Object catch (e) {
        debugPrint('persist retired one-shots failed: $e');
      }
    }

    // Never stack permission dialogs over a ring screen. A launch caused by
    // an alarm goes straight to the gate; the reliability card handles setup
    // on normal launches.
    final ringing = Alarm.ringing.value.alarms.isNotEmpty;
    if (!ringing) unawaited(_requestRuntimePermissions());
    await _syncAllToPlugin();
    unawaited(ToneFiles.sweepOrphans([for (final a in _alarms) a.filePath]));
    notifyListeners();
  }

  Future<void> _warmDetector() async {
    try {
      await CocoDetector.I.load();
    } on Object catch (e) {
      // The scan screen shows a retry card; boot must keep going.
      debugPrint('detector warm-up failed: $e');
    }
  }

  Future<void> _requestRuntimePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final notif = await Permission.notification.status;
      if (!notif.isGranted) await Permission.notification.request();
    } on Exception {
      // Older Androids don't expose this permission — fine.
    }
    try {
      if (await Permission.scheduleExactAlarm.isDenied) {
        await Permission.scheduleExactAlarm.request();
      }
    } on Exception {
      // Some OEM builds block the dialog; AlarmManager fallback still applies.
    }
  }

  void _load() {
    final prefs = _prefs;
    if (prefs == null) return;
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => BangunAlarm.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _alarms = list;
      } on Object {
        // Corrupt or outdated payload — one bad entry must never kill boot
        // (cast errors are Error, not Exception, so catch everything).
        _alarms = const [];
      }
    }
    final statsRaw = prefs.getString(_statsKey);
    if (statsRaw != null && statsRaw.isNotEmpty) {
      try {
        stats = WakeStats.fromJson(
          Map<String, dynamic>.from(jsonDecode(statsRaw) as Map),
        );
      } on Object {
        // Corrupt or outdated statistics must never block app boot. Cast
        // errors are Error, not Exception, so catch everything.
        stats = WakeStats();
      }
    }
    stats.recompute();
  }

  Future<void> _persist() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      _prefsKey,
      jsonEncode(_alarms.map((a) => a.toJson()).toList()),
    );
    await prefs.setString(_statsKey, jsonEncode(stats.toJson()));
  }

  // ---- CRUD -----------------------------------------------

  Future<void> create(BangunAlarm alarm) async {
    var id = alarm.id;
    while (_alarms.any((x) => x.id == id)) {
      id = (id + 1) % 2147483000;
    }
    final a = alarm.copyWithId(id);
    _alarms = [..._alarms, a]
      ..sort(
        (x, y) => (x.hour * 60 + x.minute).compareTo(y.hour * 60 + y.minute),
      );
    await _persist();
    if (a.enabled) await _syncToPlugin(a);
    notifyListeners();
  }

  Future<void> update(BangunAlarm alarm) async {
    final old = byId(alarm.id);
    _alarms = [for (final a in _alarms) a.id == alarm.id ? alarm : a];
    await _persist();
    if (alarm.enabled) {
      await _syncToPlugin(alarm);
    } else {
      await _stopQuietly(alarm.id);
    }
    if (old != null && old.filePath != alarm.filePath) {
      await ToneFiles.deleteIfUnreferenced(
        old.filePath,
        _alarms.map((a) => a.filePath),
      );
    }
    notifyListeners();
  }

  Future<void> toggle(int id) async {
    final i = _alarms.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final a = _alarms[i];
    a.enabled = !a.enabled;
    await _persist();
    if (a.enabled) {
      await _syncToPlugin(a);
    } else {
      await _stopQuietly(id);
    }
    notifyListeners();
  }

  Future<void> remove(int id) async {
    final removed = byId(id);
    _alarms = [
      for (final a in _alarms)
        if (a.id != id) a,
    ];
    await _persist();
    await _stopQuietly(id);
    if (removed != null) {
      await ToneFiles.deleteIfUnreferenced(
        removed.filePath,
        _alarms.map((a) => a.filePath),
      );
    }
    notifyListeners();
  }

  Future<void> duplicate(int id) async {
    final src = byId(id);
    if (src == null) return;
    await create(src.copyWith(label: '${src.label} copy', enabled: false));
  }

  // ---- Plugin sync ---------------------------------------

  /// Re-arms every enabled alarm (boot path) and drops native alarms we no
  /// longer track (orphans after reinstall / clear-data).
  Future<void> _syncAllToPlugin() async {
    try {
      final native = await Alarm.getAlarms();
      for (final s in native) {
        if (_alarms.every((a) => a.id != s.id)) {
          await _stopQuietly(s.id);
        }
      }
    } on Object {
      // Reconciliation continues with fresh arming below.
    }
    for (final a in _alarms) {
      if (a.enabled) await _syncToPlugin(a);
    }
  }

  Future<void> _stopQuietly(int id) async {
    try {
      await Alarm.stop(id);
    } on Object catch (e) {
      // Stopping an already-stopped or missing alarm must not block CRUD or
      // the end of a ring.
      debugPrint('Alarm.stop($id) failed: $e');
    }
  }

  /// Schedules the alarm's next occurrence with the native plugin.
  Future<bool> _syncToPlugin(BangunAlarm a) async {
    final when = a.nextOccurrence();
    try {
      return await Alarm.set(alarmSettings: _settingsFor(a, when));
    } on Object catch (e) {
      debugPrint('Scheduling ${a.id} failed: $e');
      return false;
    }
  }

  /// Builds native settings. Key honesty detail: volume never drops below
  /// 0.35, so a "cannot be closed" alarm is always audible.
  AlarmSettings _settingsFor(BangunAlarm a, DateTime when) {
    final asset = switch (a.toneKind) {
      ToneKind.builtin => a.tone.assetPath,
      // The editor copies picked files into app documents, but a file can
      // still disappear (storage cleaner, backup restore, manual delete).
      // Fall back to the built-in tone instead of failing to schedule at all.
      ToneKind.file =>
        ToneFiles.exists(a.filePath) ? a.filePath! : a.tone.assetPath,
      // Spotify alarms must never blast the siren: Bangun opens Spotify and
      // presses play, while a gentle twin chime keeps the ring alive until
      // the gate is cleared (or if Spotify is unavailable).
      ToneKind.spotify => BuiltInTone.twinChime.assetPath,
    };
    if (a.toneKind == ToneKind.file && !ToneFiles.exists(a.filePath)) {
      debugPrint('Tone file missing for ${a.id}; using ${a.tone.title}');
    }
    return AlarmSettings(
      id: a.id,
      dateTime: DateTime(
        when.year,
        when.month,
        when.day,
        when.hour,
        when.minute,
      ),
      assetAudioPath: asset,
      loopAudio: true,
      vibrate: true,
      volumeSettings: VolumeSettings.fixed(
        volume: math.max(0.35, a.volume),
        volumeEnforced: true,
      ),
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      allowAlarmOverlap: false,
      androidAlarmClock: true,
      payload: '${a.id}',
      notificationSettings: NotificationSettings(
        title: '⏰ Bangun — ${hhmm(a.hour, a.minute)}',
        body: '${a.label} · beat the challenge to stop',
        stopButton: null,
        androidSnoozeButton: null,
        androidStopAlarmOnDismiss: false,
      ),
    );
  }

  // ---- Ringing -------------------------------------------

  /// Called from the `Alarm.ringing` stream (cold-start rings included:
  /// BehaviorSubject replays current ringing state to new listeners).
  void onRingEvent(AlarmSet set) {
    final ids = set.alarms.map((a) => a.id).toList();
    if (ids.isEmpty) {
      _ringingId = null;
    } else {
      _ringingId = ids.first;
    }
    notifyListeners();
  }

  /// Clears ringing state when the host stops an alarm outside the app.
  void onAlarmStopped(int id) {
    if (_ringingId == id) {
      _ringingId = null;
      notifyListeners();
    }
  }

  /// Challenge completed then stop, record, re-arm the next occurrence.
  /// Trial runs use [trialAlarmId] and deliberately do not touch wake stats:
  /// a demo is not a real morning.
  Future<void> completeRing(int id, ChallengeKind kind) async {
    if (id != trialAlarmId) {
      await _stopQuietly(id);
      final a = byId(id);
      if (a != null) {
        stats.record(kind);
        if (a.repeatMode == RepeatMode.once) {
          a.enabled = false; // one-shot alarms fire once
        } else {
          unawaited(_syncToPlugin(a));
        }
      }
      try {
        await _persist();
      } on Object catch (e) {
        // The ring must still end even if storage is full or read-only.
        debugPrint('persist after ring failed: $e');
      }
    }
    _ringingId = null;
    notifyListeners();
  }

  /// Re-arms one alarm after host-side changes (boot dropout etc.). A missed
  /// one-shot is retired instead of being pushed to the next day.
  Future<void> rearm(int id) async {
    final a = byId(id);
    if (a == null || !a.enabled) return;
    if (a.missedOneShot()) {
      a.enabled = false;
      try {
        await _persist();
      } on Object catch (e) {
        debugPrint('persist retired one-shot failed: $e');
      }
      notifyListeners();
      return;
    }
    await _syncToPlugin(a);
  }

  bool get hasAnyAlarms => _alarms.isNotEmpty;

  static AlarmRepository of(BuildContext context) =>
      Provider.of<AlarmRepository>(context, listen: false);
}
