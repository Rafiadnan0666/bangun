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
    _prefs = await SharedPreferences.getInstance();
    _load();

    unawaited(_requestRuntimePermissions());
    await _syncAllToPlugin();
    unawaited(CocoDetector.I.load());
    notifyListeners();
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
      } on FormatException {
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
    _alarms = [for (final a in _alarms) a.id == alarm.id ? alarm : a];
    await _persist();
    if (alarm.enabled) {
      await _syncToPlugin(alarm);
    } else {
      await Alarm.stop(alarm.id);
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
      await Alarm.stop(id);
    }
    notifyListeners();
  }

  Future<void> remove(int id) async {
    _alarms = [
      for (final a in _alarms)
        if (a.id != id) a,
    ];
    await _persist();
    await Alarm.stop(id);
    notifyListeners();
  }

  Future<void> duplicate(int id) async {
    final src = byId(id);
    if (src == null) return;
    await create(
      src.copyWith(
        label: '${src.label} copy',
        enabled: false,
      ),
    );
  }

  // ---- Plugin sync ---------------------------------------

  /// Re-arms every enabled alarm (boot path) and drops native alarms we no
  /// longer track (orphans after reinstall / clear-data).
  Future<void> _syncAllToPlugin() async {
    try {
      final native = await Alarm.getAlarms();
      for (final s in native) {
        if (_alarms.every((a) => a.id != s.id)) {
          await Alarm.stop(s.id);
        }
      }
    } on Exception {
      // Reconciliation continues with fresh arming below.
    }
    for (final a in _alarms) {
      if (a.enabled) await _syncToPlugin(a);
    }
  }

  /// Schedules the alarm's next occurrence with the native plugin.
  Future<bool> _syncToPlugin(BangunAlarm a) async {
    final when = a.nextOccurrence();
    try {
      return await Alarm.set(alarmSettings: _settingsFor(a, when));
    } on Exception catch (e) {
      debugPrint('Scheduling ${a.id} failed: $e');
      return false;
    }
  }

  /// Builds native settings. Key honesty detail: volume never drops below
  /// 0.35, so a "cannot be closed" alarm is always audible.
  AlarmSettings _settingsFor(BangunAlarm a, DateTime when) {
    final asset = switch (a.toneKind) {
      ToneKind.builtin => a.tone.assetPath,
      ToneKind.file => a.filePath!,
      ToneKind.spotify => BuiltInTone.sirenRush.assetPath,
    };
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

  /// Challenge completed → stop, record, re-arm the next occurrence.
  Future<void> completeRing(int id, ChallengeKind kind) async {
    if (id != trialAlarmId) {
      try {
        await Alarm.stop(id);
      } on Exception {
        // Stopping an already-stopped alarm is fine.
      }
      final a = byId(id);
      if (a != null) {
        stats.record(kind);
        if (a.repeatMode == RepeatMode.once) {
          a.enabled = false; // one-shot alarms fire once
        } else {
          unawaited(_syncToPlugin(a));
        }
      }
    } else {
      stats.record(kind);
    }
    _ringingId = null;
    await _persist();
    notifyListeners();
  }

  /// Re-arms one alarm after host-side changes (boot dropout etc.).
  Future<void> rearm(int id) async {
    final a = byId(id);
    if (a != null && a.enabled) await _syncToPlugin(a);
  }

  bool get hasAnyAlarms => _alarms.isNotEmpty;

  static AlarmRepository of(BuildContext context) =>
      Provider.of<AlarmRepository>(context, listen: false);
}
