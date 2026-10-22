import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/media_control.dart';
import '../data/models.dart';
import '../data/spotify_launch.dart';
import '../data/tone_preview.dart';

/// Create / edit an alarm. All challenge + tone configuration lives here —
/// the ring screen itself has no configuration surface on purpose: it is a
/// locked environment with exactly two exits (finish math / finish scan).
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.existing});

  final BangunAlarm? existing;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final TextEditingController _labelCtrl;
  late int _hour;
  late int _minute;
  late RepeatMode _repeatMode;
  late Set<int> _days;
  late ChallengeKind _kind;
  late int _problems;
  late Set<String> _targets;
  String _query = '';
  late ToneKind _toneKind;
  late BuiltInTone _tone;
  late String? _filePath;
  late String? _fileLabel;
  late String? _spotifyUrl;
  late final TextEditingController _spotifyCtrl;
  late double _volume;

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _labelCtrl = TextEditingController(text: a?.label ?? (a == null ? 'Wake up' : ''));
    _spotifyUrl = a?.spotifyUrl;
    _spotifyCtrl = TextEditingController(text: _spotifyUrl ?? '');
    _hour = a?.hour ?? 7;
    _minute = a?.minute ?? 0;
    _repeatMode = a?.repeatMode ?? RepeatMode.once;
    _days = a == null ? {1, 2, 3, 4, 5, 6, 7} : a.days.toSet();
    _kind = a?.challengeKind ?? ChallengeKind.math;
    _problems = a?.mathProblems ?? 4;
    _targets = a?.scanTargets.toSet() ?? {'cup'};
    _toneKind = a?.toneKind ?? ToneKind.builtin;
    _tone = a?.tone ?? BuiltInTone.morningBricks;
    _filePath = a?.filePath;
    _fileLabel = a?.fileLabel;
    _spotifyUrl = a?.spotifyUrl;
    _volume = a?.volume ?? 0.8;
  }

  @override
  void dispose() {
    unawaited(TonePreview.stop());
    _labelCtrl.dispose();
    _spotifyCtrl.dispose();
    super.dispose();
  }

  // ---- Local state helpers -----------------------------------------------

  void _stepHour(int delta) {
    setState(() {
      _hour = (_hour + delta) % 24;
      if (_hour < 0) _hour += 24;
    });
    HapticFeedback.selectionClick();
  }

  void _stepMinute(int delta) {
    setState(() {
      _minute = (_minute + delta) % 60;
      if (_minute < 0) _minute += 60;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: true,
      );
      final picked = result?.files.firstOrNull;
      if (picked == null) return;
      // Copy into the app's documents directory: system cache copies get
      // evicted and SAF read grants expire, which is exactly how a "custom
      // file" alarm ends up silent (or default-toned) after a while.
      final ext = (picked.extension ?? 'audio').toLowerCase();
      final docs = await getApplicationDocumentsDirectory();
      final durable = File(
        '${docs.path}/tone_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      final bytes = picked.bytes ?? await File(picked.path!).readAsBytes();
      await durable.writeAsBytes(bytes);
      setState(() {
        _filePath = durable.path;
        _fileLabel = picked.name;
        _toneKind = ToneKind.file;
      });
    } on Exception catch (e) {
      debugPrint('pick audio file failed: $e');
    }
  }

  bool get _canSave {
    if (_kind == ChallengeKind.scan && _targets.isEmpty) return false;
    if (_toneKind == ToneKind.file && (_filePath == null || _filePath!.isEmpty)) {
      return false;
    }
    if (_toneKind == ToneKind.spotify &&
        _spotifyCtrl.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// Asks for the one Android permission that lets Bangun press play inside
  /// Spotify. Returns true only when access is already granted, so callers
  /// simply stop when the user goes to Settings to flip it.
  Future<bool> _promptSpotifyAccess() async {
    if (await MediaControl.hasNotificationAccess()) return true;
    if (!mounted) return false;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Bg.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Text(
          'Let Bangun start Spotify',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: const Text(
          'Android only lets Bangun press play inside Spotify when '
          'notification access is on. It is a one-time switch, used only for '
          'your alarm link.\n\nWithout it Spotify opens paused, so you only '
          'hear the backup chime.',
          style: TextStyle(color: Bg.sub, fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now', style: TextStyle(color: Bg.sub)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Bg.ctaA),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await MediaControl.openNotificationAccessSettings();
    }
    return false;
  }

  Future<void> _selectSpotify() async {
    setState(() {
      _toneKind = ToneKind.spotify;
      _spotifyUrl ??= '';
    });
    await _promptSpotifyAccess();
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    setState(() => _saving = true);
    final repo = context.read<AlarmRepository>();
    final label = _labelCtrl.text.trim().isEmpty ? 'Alarm' : _labelCtrl.text.trim();
    final mode = _repeatMode == RepeatMode.weekly && _days.isEmpty
        ? RepeatMode.once
        : _repeatMode;
    final alarm = BangunAlarm(
      id: widget.existing?.id ??
          DateTime.now().millisecondsSinceEpoch % 2147483000,
      label: label,
      hour: _hour,
      minute: _minute,
      repeatMode: mode,
      days: _days.toList()..sort(),
      enabled: widget.existing?.enabled ?? true,
      challengeKind: _kind,
      mathProblems: _problems,
      scanTargets: _targets.toList(),
      toneKind: _toneKind,
      tone: _tone,
      filePath: _filePath,
      fileLabel: _fileLabel,
      spotifyUrl: _toneKind == ToneKind.spotify
          ? (_spotifyCtrl.text.trim().isEmpty
                ? null
                : _spotifyCtrl.text.trim())
          : _spotifyUrl?.trim(),
      volume: _volume,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    if (_isEditing) {
      await repo.update(alarm);
    } else {
      await repo.create(alarm);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    unawaited(TonePreview.stop());
  }

  /// Plays the sound exactly as the alarm engine will at ring time: the
  /// chosen built-in tone, the picked file, or the Spotify start sequence
  /// (open the item + press play through the media-session bridge). Second
  /// tap stops a local preview.
  Future<void> _testSound() async {
    if (TonePreview.playing.value) {
      await TonePreview.stop();
      return;
    }
    if (_toneKind == ToneKind.spotify && !await _promptSpotifyAccess()) return;
    final alarm = BangunAlarm(
      id: widget.existing?.id ?? 0,
      label: _labelCtrl.text.trim().isEmpty
          ? 'Preview'
          : _labelCtrl.text.trim(),
      hour: _hour,
      minute: _minute,
      repeatMode: _repeatMode,
      days: _days.toList()..sort(),
      challengeKind: _kind,
      mathProblems: _problems,
      scanTargets: _targets.toList(),
      toneKind: _toneKind,
      tone: _tone,
      filePath: _filePath,
      fileLabel: _fileLabel,
      spotifyUrl: _spotifyCtrl.text.trim(),
      volume: _volume,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
    final result = await TonePreview.test(alarm);
    if (!mounted) return;
    setState(() {});
    if (result == null) return;
    final message = switch (result) {
      SpotifyStart.playing => 'Spotify is playing your link now.',
      SpotifyStart.opened =>
        'Spotify opened, but it needs notification access before Bangun '
            'can press play by itself. Enable it below.',
      SpotifyStart.unavailable =>
        'Spotify is not installed on this device — no link can play here.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Bg.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: const Text(
          'Delete this alarm?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          widget.existing?.label ?? 'Alarm',
          style: const TextStyle(color: Bg.sub, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: Bg.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Bg.danger, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok != true) return;
    await context.read<AlarmRepository>().remove(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Bg.bg,
      body: SafeArea(
        child: Column(
          children: [
            _EditorHeader(isEditing: _isEditing, onDelete: _isEditing ? _delete : null),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                children: [
                  _TimeCard(
                    hour: _hour,
                    minute: _minute,
                    onStepHour: _stepHour,
                    onStepMinute: _stepMinute,
                    onPickTime: _pickTime,
                  ),
                  const SizedBox(height: 16),
                  _RepeatCard(
                    mode: _repeatMode,
                    days: _days,
                    onMode: (m) => setState(() => _repeatMode = m),
                    onToggleDay: (d) {
                      setState(() {
                        if (_days.contains(d)) {
                          if (_days.length > 1) _days.remove(d);
                        } else {
                          _days.add(d);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _ChallengeCard(
                    kind: _kind,
                    problems: _problems,
                    targets: _targets,
                    query: _query,
                    onKind: (k) => setState(() => _kind = k),
                    onProblems: (n) => setState(() => _problems = n),
                    onQuery: (q) => setState(() => _query = q),
                    onToggleTarget: (t) {
                      setState(() {
                        if (_targets.contains(t)) {
                          _targets.remove(t);
                        } else {
                          _targets.add(t);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _SoundCard(
                    toneKind: _toneKind,
                    tone: _tone,
                    fileLabel: _fileLabel,
                    filePath: _filePath,
                    spotifyCtrl: _spotifyCtrl,
                    volume: _volume,
                    onTone: (t) => setState(() {
                      _tone = t;
                      _toneKind = ToneKind.builtin;
                    }),
                    onFile: _pickFile,
                    onSpotifySelected: _selectSpotify,
                    onChanged: () => setState(() {
                      _spotifyUrl = _spotifyCtrl.text;
                    }),
                    onVolume: (v) => setState(() => _volume = v),
                    onTest: _testSound,
                  ),
                  const SizedBox(height: 26),
                  CtaPill(
                    icon: '💾',
                    label: _isEditing ? 'Save changes' : 'Create alarm',
                    onTap: _canSave ? _save : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorHeader extends StatelessWidget {
  const _EditorHeader({required this.isEditing, required this.onDelete});

  final bool isEditing;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Bg.ink),
          ),
          Expanded(
            child: Text(
              isEditing ? 'Edit alarm' : 'New alarm',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Bg.ink,
              ),
            ),
          ),
          if (isEditing)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, color: Bg.danger),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.hour,
    required this.minute,
    required this.onStepHour,
    required this.onStepMinute,
    required this.onPickTime,
  });

  final int hour;
  final int minute;
  final ValueChanged<int> onStepHour;
  final ValueChanged<int> onStepMinute;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    return BgCard(
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onPickTime,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GradientText(
                    text: hhmm(hour, minute),
                    style: const TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Text('⌚', style: TextStyle(fontSize: 18)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StepperRow(
                  label: 'Hour',
                  value: two(hour),
                  onLess: () => onStepHour(-1),
                  onMore: () => onStepHour(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StepperRow(
                  label: 'Minute',
                  value: two(minute),
                  onLess: () => onStepMinute(-5),
                  onMore: () => onStepMinute(5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onLess,
    required this.onMore,
  });

  final String label;
  final String value;
  final VoidCallback onLess;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Bg.cardSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          _RoundBtn(icon: '−', onTap: onLess),
          Expanded(
            child: Column(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19,
                    color: Bg.ink,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10.5, color: Bg.sub),
                ),
              ],
            ),
          ),
          _RoundBtn(icon: '＋', onTap: onMore),
        ],
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(color: Bg.card, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          icon,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Bg.ink),
        ),
      ),
    );
  }
}

class _RepeatCard extends StatelessWidget {
  const _RepeatCard({
    required this.mode,
    required this.days,
    required this.onMode,
    required this.onToggleDay,
  });

  final RepeatMode mode;
  final Set<int> days;
  final ValueChanged<RepeatMode> onMode;
  final ValueChanged<int> onToggleDay;

  @override
  Widget build(BuildContext context) {
    return BgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Repeat', icon: '🔁'),
          Row(
            children: [
              for (final m in RepeatMode.values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onMode(m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: mode == m ? Bg.ink : Bg.cardSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        switch (m) {
                          RepeatMode.once => 'Once',
                          RepeatMode.daily => 'Every day',
                          RepeatMode.weekly => 'Pick days',
                        },
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: mode == m ? Colors.white : Bg.sub,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: mode == RepeatMode.weekly
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Row(
                      children: [
                        for (var i = 1; i <= 7; i++)
                          Expanded(
                            child: GestureDetector(
                              onTap: () => onToggleDay(i),
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                height: 42,
                                decoration: BoxDecoration(
                                  color: days.contains(i) ? Bg.ink : Bg.cardSoft,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  kWeekdayLetters[i - 1],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: days.contains(i)
                                        ? Colors.white
                                        : Bg.subFaint,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.kind,
    required this.problems,
    required this.targets,
    required this.query,
    required this.onKind,
    required this.onProblems,
    required this.onQuery,
    required this.onToggleTarget,
  });

  final ChallengeKind kind;
  final int problems;
  final Set<String> targets;
  final String query;
  final ValueChanged<ChallengeKind> onKind;
  final ValueChanged<int> onProblems;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onToggleTarget;

  static const _kinds = [
    (ChallengeKind.math, '🧮', 'Math grind', 'Solve arithmetic at 6 a.m.'),
    (ChallengeKind.scan, '📷', 'Object scan', 'Point the camera at real things'),
    (ChallengeKind.mix, '🔀', 'Pick at ring', 'Both options when it rings'),
  ];

  @override
  Widget build(BuildContext context) {
    return BgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Challenge to unlock', icon: '🔒'),
          for (final k in _kinds)
            GestureDetector(
              onTap: () => onKind(k.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: kind == k.$1 ? Bg.cardSoft : Bg.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: kind == k.$1 ? Bg.plum : Bg.hairline,
                    width: 1.6,
                  ),
                ),
                child: Row(
                  children: [
                    Text(k.$2, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            k.$3,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: Bg.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            k.$4,
                            style: const TextStyle(fontSize: 11.5, color: Bg.sub),
                          ),
                        ],
                      ),
                    ),
                    if (kind == k.$1)
                      const Text('✅', style: TextStyle(fontSize: 15)),
                  ],
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: kind == ChallengeKind.math
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Problems to solve',
                          style: TextStyle(fontSize: 12, color: Bg.sub),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final n in const [3, 5, 7])
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: EmojiChip(
                                  label: '$n',
                                  selected: problems == n,
                                  color: Bg.sky,
                                  onTap: () => onProblems(n),
                                ),
                              ),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                'No stopping mid-grind — finish to silence.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: Bg.subFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : kind == ChallengeKind.scan
                ? _TargetPicker(
                    selected: targets,
                    query: query,
                    onQuery: onQuery,
                    onToggle: onToggleTarget,
                  )
                : const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'When it rings you choose: solve math or scan the object. '
                      'Either one ends the ring.',
                      style: TextStyle(fontSize: 11.5, color: Bg.subFaint),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TargetPicker extends StatelessWidget {
  const _TargetPicker({
    required this.selected,
    required this.query,
    required this.onQuery,
    required this.onToggle,
  });

  final Set<String> selected;
  final String query;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final pool = kPickableTargets
        .where((t) => selected.contains(t))
        .followedBy(
          kPickableTargets.where(
            (t) =>
                !selected.contains(t) &&
                (query.isEmpty ||
                    t.toLowerCase().contains(query.toLowerCase())),
          ),
        )
        .toList();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: onQuery,
            decoration: const InputDecoration(
              hintText: '🔍  search objects…',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in pool.take(28))
                EmojiChip(
                  emoji: targetEmoji(t),
                  label: t,
                  selected: selected.contains(t),
                  color: Bg.mint,
                  onTap: () => onToggle(t),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            selected.isEmpty
                ? 'Pick at least one target!'
                : selected.every(kEasyScanTargets.contains)
                ? 'Easy targets cover most scenes — hard ones optional.'
                : 'Easy objects are asked first; hard ones only as fallback.',
            style: TextStyle(
              fontSize: 11,
              color: selected.isEmpty ? Bg.danger : Bg.subFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundCard extends StatelessWidget {
  const _SoundCard({
    required this.toneKind,
    required this.tone,
    required this.fileLabel,
    required this.filePath,
    required this.spotifyCtrl,
    required this.volume,
    required this.onTone,
    required this.onFile,
    required this.onSpotifySelected,
    required this.onChanged,
    required this.onVolume,
    required this.onTest,
  });

  final ToneKind toneKind;
  final BuiltInTone tone;
  final String? fileLabel;
  final String? filePath;
  final TextEditingController spotifyCtrl;
  final double volume;
  final ValueChanged<BuiltInTone> onTone;
  final VoidCallback onFile;
  final VoidCallback onSpotifySelected;
  final VoidCallback onChanged;
  final ValueChanged<double> onVolume;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: Bg.toneGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Bg.toneBlueDeep.withValues(alpha: .28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SoundTitle(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in BuiltInTone.values)
                _SoundChip(
                  emoji: t.emoji,
                  label: t.title,
                  selected: toneKind == ToneKind.builtin && tone == t,
                  onTap: () => onTone(t),
                ),
              _SoundChip(
                emoji: '📂',
                label: fileLabel != null ? 'File: $fileLabel' : 'Own file',
                selected: toneKind == ToneKind.file,
                onTap: onFile,
              ),
              _SoundChip(
                emoji: '🎧',
                label: 'Spotify',
                selected: toneKind == ToneKind.spotify,
                onTap: onSpotifySelected,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _SoundTestButton(
            kind: toneKind,
            canPlay: switch (toneKind) {
              ToneKind.builtin => true,
              ToneKind.file => filePath != null && filePath!.isNotEmpty,
              ToneKind.spotify => true,
            },
            onToggle: onTest,
          ),
          if (toneKind == ToneKind.file && fileLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                fileLabel!,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: .85),
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: toneKind == ToneKind.spotify
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: spotifyCtrl,
                          onChanged: (_) => onChanged(),
                          style: const TextStyle(
                            color: Bg.toneBlueDeep,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            hintText: 'Paste a Spotify track / playlist link',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const _SpotifyAccessCard(),
                        const SizedBox(height: 8),
                        Text(
                          'At ring time Bangun opens your link and presses '
                          'play in Spotify. The twin-chime backup rings '
                          'underneath until the gate is cleared - no siren.',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white.withValues(alpha: .85),
                          ),
                        ),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: spotifyCtrl,
                          builder: (context, value, _) {
                            final url = value.text.trim();
                            if (url.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await launchSpotify(url, autoplay: true);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      const Text('🎧', style: TextStyle(fontSize: 14)),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                          'Open this link in Spotify — the '
                                          'handoff test at ring time',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('🔈', style: TextStyle(fontSize: 15)),
              Expanded(
                child: Slider(
                  value: volume,
                  min: 0.35,
                  max: 1,
                  activeColor: Colors.white,
                  inactiveColor: Colors.white.withValues(alpha: .30),
                  onChanged: onVolume,
                ),
              ),
              const Text('🔊', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                '${(volume * 100).round()}%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: .95),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Minimum enforced volume is 35% — a locked alarm is always audible.',
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: .70),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sound-card heading with a looping bell that rocks gently — the section
/// that wakes you up should feel alive.
class _SoundTitle extends StatelessWidget {
  const _SoundTitle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          const _WiggleBell(),
          const SizedBox(width: 7),
          const Text(
            'Ring sound',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
          const Spacer(),
          const _EqBars(),
        ],
      ),
    );
  }
}

class _WiggleBell extends StatefulWidget {
  const _WiggleBell();

  @override
  State<_WiggleBell> createState() => _WiggleBellState();
}

class _WiggleBellState extends State<_WiggleBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.rotate(
        // One smooth swing per cycle keeps it fun without wobbling the text.
        angle: math.sin(_c.value * 2 * math.pi) * 0.16,
        child: child,
      ),
      child: const Text('🔔', style: TextStyle(fontSize: 15)),
    );
  }
}

/// Little dancing equalizer bars for the sound card header — white on blue,
/// bounce faster while a preview is actually playing.
class _EqBars extends StatefulWidget {
  const _EqBars();

  @override
  State<_EqBars> createState() => _EqBarsState();
}

class _EqBarsState extends State<_EqBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TonePreview.playing,
      builder: (context, playing, _) {
        return AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final speed = playing ? 1.9 : 1.0;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final i in [0, 1, 2, 3])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      width: 3.5,
                      height: 7 +
                          8 *
                              (0.5 +
                              0.5 *
                                  math.sin((_c.value * 2 * math.pi + i * 1.7) *
                                      speed)).abs(),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .9),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Blue-white tone chip for the sound card: idle = frosted white on blue,
/// selected = solid white with deep-blue ink (plus the playful pop).
class _SoundChip extends StatelessWidget {
  const _SoundChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? Colors.transparent
              : Colors.white.withValues(alpha: .45),
          width: 1.4,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (emoji != null) ...[
                Text(emoji!, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Bg.toneBlueDeep : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-time setup row for Spotify mode: without notification access Bangun
/// cannot press play inside Spotify, and the link would open paused. The card
/// re-checks whenever the app resumes from the settings screen.
class _SpotifyAccessCard extends StatefulWidget {
  const _SpotifyAccessCard();

  @override
  State<_SpotifyAccessCard> createState() => _SpotifyAccessCardState();
}

class _SpotifyAccessCardState extends State<_SpotifyAccessCard>
    with WidgetsBindingObserver {
  bool? _hasAccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final access = await MediaControl.hasNotificationAccess();
    if (mounted) setState(() => _hasAccess = access);
  }

  @override
  Widget build(BuildContext context) {
    final access = _hasAccess;
    if (access == null) return const SizedBox.shrink();
    if (access) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle_rounded,
                size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Auto-play armed — Bangun presses play in Spotify for you at '
                'ring time.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  color: Colors.white.withValues(alpha: .92),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.touch_app_rounded,
                  size: 16, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Allow notification access once, and Bangun will press play '
                  'inside Spotify by itself — no siren, no manual tap.',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    color: Colors.white.withValues(alpha: .92),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                await MediaControl.openNotificationAccessSettings();
                // The user may come straight back; re-check on resume too.
                await Future<void>.delayed(const Duration(seconds: 1));
                await _refresh();
              },
              child: const Text(
                'Enable auto-play',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Blue-white "test what will wake me" pill. Reuses the shared preview so
/// built-in tones, picked files, and the Spotify start path all behave the
/// same way; taps toggle play/stop and the pill pulses while audible.
class _SoundTestButton extends StatefulWidget {
  const _SoundTestButton({
    required this.kind,
    required this.canPlay,
    required this.onToggle,
  });

  final ToneKind kind;
  final bool canPlay;
  final VoidCallback onToggle;

  @override
  State<_SoundTestButton> createState() => _SoundTestButtonState();
}

class _SoundTestButtonState extends State<_SoundTestButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  String _label(bool playing) => switch (widget.kind) {
        ToneKind.builtin => playing ? 'Stop preview' : 'Test this tone',
        ToneKind.file => playing
            ? 'Stop preview'
            : widget.canPlay
                ? 'Test my file'
                : 'Pick a file first',
        ToneKind.spotify => 'Open Spotify and play it',
      };

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: TonePreview.playing,
      builder: (context, playing, _) {
        if (playing) {
          _pulse.repeat(reverse: true);
        } else {
          _pulse.stop();
        }
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final active = widget.canPlay || playing;
            return Transform.scale(
              scale: playing ? 1 + _pulse.value * 0.05 : 1.0,
              child: Opacity(
                opacity: active ? 1 : 0.55,
                child: Material(
                  color: Colors.transparent,
                  child: Ink(
                    height: 44,
                    decoration: BoxDecoration(
                      color: playing ? Bg.toneBlueDeep : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: playing
                            ? Colors.white
                            : Colors.white.withValues(alpha: .0),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Bg.toneBlueDeep.withValues(alpha: .35),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: widget.onToggle,
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            playing
                                ? Transform.scale(
                                    scale: 1 + _pulse.value * 0.35,
                                    child: const Icon(
                                      Icons.stop_rounded,
                                      size: 19,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 19,
                                    color: Bg.toneBlueDeep,
                                  ),
                            const SizedBox(width: 8),
                            Text(
                              _label(playing),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: playing
                                    ? Colors.white
                                    : Bg.toneBlueDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
