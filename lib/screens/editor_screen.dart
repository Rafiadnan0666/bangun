import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/models.dart';

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
      const group = XTypeGroup(
        label: 'Audio',
        extensions: ['mp3', 'wav', 'm4a', 'ogg', 'flac', 'aac', 'opus'],
      );
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      setState(() {
        _filePath = file.path;
        _fileLabel = file.name;
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
        _spotifyUrl != null &&
        _spotifyUrl!.trim().isEmpty) {
      return false;
    }
    return true;
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
      spotifyUrl: _spotifyUrl?.trim(),
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
                    spotifyCtrl: _spotifyCtrl,
                    volume: _volume,
                    onTone: (t) => setState(() {
                      _tone = t;
                      _toneKind = ToneKind.builtin;
                    }),
                    onFile: _pickFile,
                    onSpotifySelected: () => setState(() {
                      _toneKind = ToneKind.spotify;
                      _spotifyUrl ??= '';
                    }),
                    onChanged: () => setState(() {
                      _spotifyUrl = _spotifyCtrl.text;
                    }),
                    onVolume: (v) => setState(() => _volume = v),
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
                : 'Pick ${selected.length} — any of them will stop the alarm.',
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
    required this.spotifyCtrl,
    required this.volume,
    required this.onTone,
    required this.onFile,
    required this.onSpotifySelected,
    required this.onChanged,
    required this.onVolume,
  });

  final ToneKind toneKind;
  final BuiltInTone tone;
  final String? fileLabel;
  final TextEditingController spotifyCtrl;
  final double volume;
  final ValueChanged<BuiltInTone> onTone;
  final VoidCallback onFile;
  final VoidCallback onSpotifySelected;
  final VoidCallback onChanged;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    return BgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Ring sound', icon: '🔔'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in BuiltInTone.values)
                EmojiChip(
                  emoji: t.emoji,
                  label: t.title,
                  selected: toneKind == ToneKind.builtin && tone == t,
                  color: Bg.lemon,
                  onTap: () => onTone(t),
                ),
              EmojiChip(
                emoji: '📂',
                label: fileLabel != null ? 'File: $fileLabel' : 'Own file',
                selected: toneKind == ToneKind.file,
                color: Bg.peach,
                onTap: onFile,
              ),
              EmojiChip(
                emoji: '🎧',
                label: 'Spotify',
                selected: toneKind == ToneKind.spotify,
                color: Bg.mint,
                onTap: onSpotifySelected,
              ),
            ],
          ),
          if (toneKind == ToneKind.file && fileLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Text(
                fileLabel!,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: Bg.sub),
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
                          decoration: const InputDecoration(
                            hintText: 'Paste a Spotify track / playlist link',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The siren tone keeps ringing until you open your '
                          'Spotify queue — Bangun never relies on the cloud to '
                          'louden the alarm.',
                          style: TextStyle(fontSize: 10.5, color: Bg.subFaint),
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
                  onChanged: onVolume,
                ),
              ),
              const Text('🔊', style: TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                '${(volume * 100).round()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Bg.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Minimum enforced volume is 35% — a locked alarm is always audible.',
            style: TextStyle(fontSize: 10.5, color: Bg.subFaint),
          ),
        ],
      ),
    );
  }
}
