import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/models.dart';
import 'editor_screen.dart';
import 'math_challenge_screen.dart';
import 'scan_challenge_screen.dart';

/// Dashboard — next alarm hero, quick tiles, alarm list. Trial challenges
/// launch straight into the gate screens so you can test the grind.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = 'all'; // all | on | off

  List<BangunAlarm> get _visible {
    final repo = context.watch<AlarmRepository>();
    return repo.alarms.where((a) {
      return switch (_filter) {
        'on' => a.enabled,
        'off' => !a.enabled,
        _ => true,
      };
    }).toList();
  }

  BangunAlarm _trial(ChallengeKind kind) => BangunAlarm(
    id: trialAlarmId,
    label: 'Trial run',
    hour: DateTime.now().hour,
    minute: (DateTime.now().minute + 1) % 60,
    challengeKind: kind,
    mathProblems: 4,
    scanTargets: const ['cup'],
    createdAt: DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AlarmRepository>();
    final (nextAlarm, nextAt) = repo.nextOnAlarm;
    final stats = repo.stats;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            const _Header(),
            const SizedBox(height: 18),
            _HeroNextAlarm(alarm: nextAlarm, nextAt: nextAt),
            const SizedBox(height: 14),
            _StatusCard(alarm: nextAlarm, nextAt: nextAt, stats: stats),
            const SizedBox(height: 16),
            _QuickTiles(
              onNewAlarm: _openEditor,
              onTestScan: () =>
                  _launchChallenge(context, _trial(ChallengeKind.scan)),
              onTestMath: () =>
                  _launchChallenge(context, _trial(ChallengeKind.math)),
              onStats: _showStatsSheet,
            ),
            const SizedBox(height: 22),
            _FilterTabs(current: _filter, onChange: (v) => setState(() => _filter = v)),
            const SizedBox(height: 12),
            if (_visible.isEmpty) const _EmptyState() else ...[
              for (final a in _visible) _AlarmRow(alarm: a),
            ],
            const SizedBox(height: 20),
            CtaPill(icon: '＋', label: 'New alarm', onTap: _openEditor),
            const SizedBox(height: 18),
            const Text(
              'COCO-SSD · MobileNet · fully on-device · alarms you stop by '
              'scanning or grinding math',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Bg.subFaint),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _openEditor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EditorScreen()),
    );
  }

  void _showStatsSheet() {
    final repo = context.read<AlarmRepository>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _StatsSheet(stats: repo.stats),
    );
  }
}

void _launchChallenge(BuildContext context, BangunAlarm alarm) {
  if (alarm.challengeKind == ChallengeKind.scan) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanChallengeScreen(alarm: alarm),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MathChallengeScreen(alarm: alarm),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final streak = context.watch<AlarmRepository>().stats.currentStreak;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: Bg.lemon,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text('👋', style: TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bangun.',
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w900,
                color: Bg.ink,
                height: 1.05,
              ),
            ),
            Text(
              'wake smart · stop by scan or math',
              style: TextStyle(fontSize: 12, color: Bg.sub),
            ),
          ],
        ),
        const Spacer(),
        if (streak > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Bg.card,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '🔥 $streak',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Bg.ink,
              ),
            ),
          ),
      ],
    );
  }
}

class _HeroNextAlarm extends StatelessWidget {
  const _HeroNextAlarm({required this.alarm, required this.nextAt});

  final BangunAlarm? alarm;
  final DateTime? nextAt;

  @override
  Widget build(BuildContext context) {
    final label = alarm == null
        ? 'Nothing scheduled yet'
        : '${hhmm(alarm!.hour, alarm!.minute)} · ${alarm!.label}';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: Bg.cta,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5E9C).withValues(alpha: 0.30),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text('◔ next alarm', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
          ),
          const SizedBox(height: 10),
          GradientText(
            text: nextAt == null ? '--:--' : hhmm(nextAt!.hour, nextAt!.minute),
            style: const TextStyle(
              fontSize: 54,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  countdownText(nextAt),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const Spacer(),
              const Text('☀️', style: TextStyle(fontSize: 26)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.alarm,
    required this.nextAt,
    required this.stats,
  });

  final BangunAlarm? alarm;
  final DateTime? nextAt;
  final WakeStats stats;

  @override
  Widget build(BuildContext context) {
    return BgCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusRow(
            leading: 'Alarm',
            value: alarm == null
                ? '— none enabled'
                : alarm!.label,
          ),
          const Divider(),
          StatusRow(
            leading: 'Challenge',
            value: alarm?.challengeLabel() ?? '—',
          ),
          const Divider(),
          StatusRow(
            leading: 'Sound',
            value: alarm == null ? '—' : alarm!.toneName(),
          ),
          const Divider(),
          StatusRow(
            leading: 'Repeat',
            value: alarm == null
                ? '—'
                : alarm!.repeatMode == RepeatMode.weekly
                    ? repeatLabel(daily: false, days: alarm!.days)
                    : repeatLabel(
                        daily: alarm!.repeatMode == RepeatMode.daily,
                        days: alarm!.repeatMode == RepeatMode.daily
                            ? const [1, 2, 3, 4, 5, 6, 7]
                            : const [],
                      ),
          ),
          if (stats.totalWins > 0) ...[
            const Divider(),
            StatusRow(
              leading: 'Wins',
              value:
                  '${stats.totalWins} wake-ups · streak ${stats.currentStreak} '
                  '(best ${stats.bestStreak})',
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickTiles extends StatelessWidget {
  const _QuickTiles({
    required this.onNewAlarm,
    required this.onTestScan,
    required this.onTestMath,
    required this.onStats,
  });

  final VoidCallback onNewAlarm;
  final VoidCallback onTestScan;
  final VoidCallback onTestMath;
  final VoidCallback onStats;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('＋', Bg.coral, 'Add alarm', onNewAlarm),
      ('📷', Bg.mint, 'Test scan', onTestScan),
      ('🧮', Bg.sky, 'Test math', onTestMath),
      ('🔥', Bg.lemon, 'Streaks', onStats),
    ];
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 14),
          Expanded(
            child: PastelTile(
              emoji: tiles[i].$1,
              color: tiles[i].$2,
              label: tiles[i].$3,
              onTap: tiles[i].$4,
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.current, required this.onChange});

  final String current;
  final ValueChanged<String> onChange;

  @override
  Widget build(BuildContext context) {
    final tabs = [('all', 'All alarms'), ('on', 'On'), ('off', 'Off')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Bg.cardSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChange(t.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: current == t.$1 ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    t.$2,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: current == t.$1 ? Bg.ink : Bg.sub,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlarmRow extends StatelessWidget {
  const _AlarmRow({required this.alarm});

  final BangunAlarm alarm;

  static Color _colorFor(int id) =>
      Bg.tileColors[(id.clamp(0, 999)) % Bg.tileColors.length];

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AlarmRepository>();
    final dimmed = !alarm.enabled;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: BgCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => EditorScreen(existing: alarm),
              ),
            );
          },
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _colorFor(alarm.id),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Text(
                  switch (alarm.challengeKind) {
                    ChallengeKind.math => '🧮',
                    ChallengeKind.scan => '📷',
                    ChallengeKind.mix => '🔀',
                  },
                  style: const TextStyle(fontSize: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: dimmed ? 0.45 : 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hhmm(alarm.hour, alarm.minute),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Bg.ink,
                              height: 1.05,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            alarm.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Bg.sub,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                alarm.challengeLabel(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Bg.plum,
                                ),
                              ),
                              if (alarm.repeatMode == RepeatMode.weekly) ...[
                                const SizedBox(width: 10),
                                Text(
                                  repeatLabel(daily: false, days: alarm.days),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Bg.subFaint,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Transform.scale(
                    scale: 1.05,
                    child: ValueSwitch(value: alarm.enabled, onChanged: (_) => repo.toggle(alarm.id)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    alarm.enabled
                        ? countdownText(alarm.nextOccurrence())
                        : 'paused',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Bg.subFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cute mini switch wrapper.
class ValueSwitch extends StatelessWidget {
  const ValueSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 28,
      child: Transform.scale(
        scale: 0.8,
        child: Switch(value: value, onChanged: onChanged),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return BgCard(
      color: Bg.cardSoft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      child: Column(
        children: [
          const Text('😴', style: TextStyle(fontSize: 44)),
          const SizedBox(height: 10),
          const Text(
            'No alarms here',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: Bg.ink,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set one and see if you can beat the gate tomorrow morning.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Bg.sub),
          ),
        ],
      ),
    );
  }
}

class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.stats});

  final WakeStats stats;

  @override
  Widget build(BuildContext context) {
    // Last-7-days dots.
    final now = DateTime.now();
    final cells = <Widget>[];
    for (var i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final wins = stats.winsByDay[todayKey(d)] ?? 0;
      cells.add(
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: wins > 0 ? Bg.mint : Bg.cardSoft,
                shape: BoxShape.circle,
                boxShadow: wins > 0
                    ? [
                        BoxShadow(
                          color: Bg.mint.withValues(alpha: 0.4),
                          blurRadius: 10,
                        ),
                      ]
                    : const [],
              ),
              child: wins > 0
                  ? const Center(
                      child: Text(
                        '☀',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              kWeekdayLetters[d.weekday - 1],
              style: const TextStyle(fontSize: 11, color: Bg.sub),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Bg.card,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '🔥 Wake streaks',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Bg.ink,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Bg.sub),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: cells),
          const SizedBox(height: 20),
          StatusRow(
            leading: 'Current streak',
            value: '${stats.currentStreak} day(s)',
          ),
          const Divider(),
          StatusRow(leading: 'Best streak', value: '${stats.bestStreak} day(s)'),
          const Divider(),
          StatusRow(leading: 'Total wins', value: '${stats.totalWins}'),
          const Divider(),
          StatusRow(
            leading: 'Math wins',
            value: '${stats.mathWins} · Scan wins: ${stats.scanWins}',
          ),
          const SizedBox(height: 8),
          const Text(
            'A win is counted each time you finish a challenge to stop a ring. '
            'Streaks span all alarms.',
            style: TextStyle(fontSize: 11.5, color: Bg.subFaint),
          ),
        ],
      ),
    );
  }
}
