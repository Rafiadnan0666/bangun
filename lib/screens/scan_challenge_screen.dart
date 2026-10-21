import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/palette.dart';
import '../core/widgets.dart';
import '../data/alarm_repository.dart';
import '../data/coco_detector.dart';
import '../data/models.dart';
import 'success_screen.dart';

/// The scan gate: point the camera at the target object and hold it in frame.
/// Detection runs on-device (COCO-SSD MobileNet); the ring ends only when the
/// object has been held long enough to prove it's really there.
class ScanChallengeScreen extends StatefulWidget {
  const ScanChallengeScreen({
    super.key,
    required this.alarm,
    this.chosenKind,
  });

  final BangunAlarm alarm;
  final ChallengeKind? chosenKind;

  @override
  State<ScanChallengeScreen> createState() => _ScanChallengeScreenState();
}

class _ScanChallengeScreenState extends State<ScanChallengeScreen> {
  static const _holdMs = 3000;

  CameraController? _controller;
  String? _error;
  bool _permissionDenied = false;
  List<Detection> _detections = const [];
  String? _matchedLabel;
  double _progress = 0;
  DateTime _lastFrameAt = DateTime.now();
  DateTime? _lastGateAt;
  bool _busy = false;
  bool _finishing = false;

  late final List<String> _targets;
  late final String _target;

  bool get _isTrial => widget.alarm.id == trialAlarmId;

  @override
  void initState() {
    super.initState();
    final pool = widget.alarm.scanTargets.isNotEmpty
        ? widget.alarm.scanTargets
        : const ['cup'];
    _targets = pool;
    _target = pool[math.Random().nextInt(pool.length)];
    _bootstrap();
  }

  @override
  void dispose() {
    _busy = true; // stop frame callbacks before disposing
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        final asked = await Permission.camera.request();
        if (!asked.isGranted) {
          setState(() => _permissionDenied = true);
          return;
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      CameraDescription pick = cameras.first;
      for (final c in cameras) {
        if (c.lensDirection == CameraLensDirection.back) pick = c;
      }
      final controller = CameraController(
        pick,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      _controller = controller;
      await controller.startImageStream(_onFrame);
      setState(() => _error = null);
    } on Exception catch (e) {
      debugPrint('camera bootstrap failed: $e');
      setState(() => _error = 'Camera failed to start. Reopen and retry.');
    }
  }

  void _onFrame(CameraImage image) {
    if (!mounted || _finishing || _busy) return;
    final now = DateTime.now();
    if (now.difference(_lastFrameAt).inMilliseconds < 110) return;
    _lastFrameAt = now;
    _busy = true;

    final det = CocoDetector.I;
    if (!det.isReady || _controller == null) {
      _busy = false;
      return;
    }
    try {
      final rgb = yuvToSquareRgb(
        image,
        sensorOrientation: _controller!.description.sensorOrientation,
        outSize: det.inputSize,
      );
      final dets = det.detect(rgb);
      _detections = dets;

      final hit = dets
          .where((d) => _targets.contains(d.label))
          .fold<Detection?>(null, (best, d) => best ?? d);

      // Temporal gate delta — clamp so a background pause doesn't grant a
      // giant free chunk of presence time.
      final dt = _lastGateAt == null
          ? 84
          : now.difference(_lastGateAt!).inMilliseconds.clamp(0, 400);
      _lastGateAt = now;
      _applySession(hit != null, hit?.label, hit?.score ?? 0, dt);

      if (_progress >= 1 && !_finishing) {
        _finish(hit?.label ?? _matchedLabel);
      }
      if (mounted) setState(() {});
    } on Exception catch (e) {
      debugPrint('detect failed: $e');
    } finally {
      _busy = false;
    }
  }

  // Temporal gate: matched frames accrue presence time (capped at _holdMs),
  // misses decay at double speed, so merely waving the camera around fails.
  void _applySession(bool matched, String? label, double score, int dtMs) {
    if (matched) {
      _matchedLabel = label;
      _progress = math.min(
        1.0,
        _progress + (dtMs / _holdMs) * math.min(1.0, 0.4 + score),
      );
    } else {
      _progress = math.max(0.0, _progress - (dtMs / _holdMs) * 2);
    }
  }

  Future<void> _finish(String? label) async {
    setState(() => _finishing = true);
    final kind = widget.chosenKind ??
        (widget.alarm.challengeKind == ChallengeKind.scan
            ? ChallengeKind.scan
            : ChallengeKind.math);
    final repo = context.read<AlarmRepository>();
    await repo.completeRing(widget.alarm.id, kind);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SuccessScreen(
          kind: kind,
          scannedLabel: label,
          streak: repo.stats.currentStreak,
          totalWins: repo.stats.totalWins,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _controller != null && _controller!.value.isInitialized
        ? ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
          )
        : Container(color: Bg.ink);

    return PopScope(
      canPop: _isTrial,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) HapticFeedback.vibrate();
      },
      child: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            preview,
            if (_permissionDenied)
              _MessageCard(
                icon: '📷',
                title: 'Camera permission needed',
                body:
                    'The scan gate runs on-device and needs the camera. Your '
                    'frame is processed locally — nothing is uploaded.',
                actionLabel: 'Grant camera access',
                onAction: () async {
                  await Permission.camera.request();
                  setState(() => _permissionDenied = false);
                  await _bootstrap();
                },
              )
            else if (_error != null)
              _MessageCard(
                icon: '⚠️',
                title: 'Camera unavailable',
                body: _error!,
                actionLabel: 'Try again',
                onAction: () {
                  controllerRetry();
                },
              )
            else ...[_ScanHud(
              target: _target,
              progress: _progress,
              detections: _detections,
              matchedLabel: _matchedLabel,
              targets: _targets,
              holdMs: _holdMs,
              isTrial: _isTrial,
            )],
          ],
        ),
      ),
    );
  }

  void controllerRetry() {
    setState(() => _error = null);
    _bootstrap();
  }
}

class _ScanHud extends StatelessWidget {
  const _ScanHud({
    required this.target,
    required this.progress,
    required this.detections,
    required this.matchedLabel,
    required this.targets,
    required this.holdMs,
    required this.isTrial,
  });

  final String target;
  final double progress;
  final List<Detection> detections;
  final String? matchedLabel;
  final List<String> targets;
  final int holdMs;
  final bool isTrial;

  @override
  Widget build(BuildContext context) {
    final chips = detections.take(3).toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Bg.card.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Row(
                children: [
                  Text(targetEmoji(target), style: const TextStyle(fontSize: 30)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SHOW ME',
                          style: TextStyle(
                            fontSize: 10.5,
                            letterSpacing: 2.5,
                            color: Bg.sub,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          target,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: Bg.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    isTrial ? 'trial 🧪' : '🔒 gate',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Bg.sub,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Column(
              children: [
                SizedBox(
                  width: 132,
                  height: 132,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 9,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white30,
                          valueColor: AlwaysStoppedAnimation(
                            progress >= 1 ? Bg.success : Bg.ctaB,
                          ),
                        ),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                          shadows: [Shadow(blurRadius: 12, color: Bg.ink)],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  progress >= 1
                      ? 'got it!'
                      : matchedLabel == null
                      ? 'Find and hold it in frame for ${holdMs / 1000}s'
                      : 'Hold still… keep it centered',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    shadows: [Shadow(blurRadius: 10, color: Bg.ink.withValues(alpha: 0.7))],
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (chips.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final d in chips)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: targets.contains(d.label)
                              ? Bg.mint
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            targetEmoji(d.label),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${d.label} ${(d.score * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Bg.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (!isTrial)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  '🔒 locked — finishing the scan is the only exit',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final String icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Bg.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: BgCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 17,
                color: Bg.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Bg.sub),
            ),
            const SizedBox(height: 16),
            InkPill(icon: '⚡', label: actionLabel, onTap: onAction),
          ],
        ),
      ),
    );
  }
}
