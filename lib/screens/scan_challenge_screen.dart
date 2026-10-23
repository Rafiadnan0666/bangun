import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
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
import '../data/scan_geometry.dart';
import 'success_screen.dart';

/// The scan gate: point the camera at the target object and hold it in frame.
/// Detection runs on-device (COCO-SSD MobileNet); the ring ends only when the
/// object has been held long enough to prove it's really there.
class ScanChallengeScreen extends StatefulWidget {
  const ScanChallengeScreen({super.key, required this.alarm, this.chosenKind});

  final BangunAlarm alarm;
  final ChallengeKind? chosenKind;

  @override
  State<ScanChallengeScreen> createState() => _ScanChallengeScreenState();
}

class _ScanChallengeScreenState extends State<ScanChallengeScreen>
    with WidgetsBindingObserver {
  static const _holdMs = 3000;

  CameraController? _controller;
  String? _error;
  bool _permissionDenied = false;
  bool _permissionPermanentlyDenied = false;
  List<Detection> _detections = const [];
  String? _matchedLabel;
  double _progress = 0;
  DateTime _lastFrameAt = DateTime.now();
  DateTime? _lastGateAt;
  bool _busy = false;
  bool _finishing = false;
  int _frameW = 0;
  int _frameH = 0;
  bool _detectorLoading = false;
  String? _detectorError;
  int _detectErrors = 0;

  late final Set<String> _accepted;
  late final String _target;

  bool get _isTrial => widget.alarm.id == trialAlarmId;

  /// Keep the overlay quiet without letting non-target boxes push a real hit
  /// out of view. Accepted labels always rank first, then confidence.
  List<Detection> get _displayDetections {
    final ranked = List<Detection>.of(_detections);
    ranked.sort((a, b) {
      final aHit = _accepted.contains(a.label);
      final bHit = _accepted.contains(b.label);
      if (aHit != bHit) return aHit ? -1 : 1;
      return b.score.compareTo(a.score);
    });
    return ranked.take(CocoDetector.maxDetections).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final pool = widget.alarm.scanTargets.isNotEmpty
        ? widget.alarm.scanTargets
        : kDefaultScanTargets;
    _target = pickScanTarget(pool, isTrial: _isTrial);
    // Accept shape-confusable labels for the chosen target only. The rest of
    // the configured pool is not silently accepted, or a broad default pool
    // would turn "show me a glass" into "show me anything in the room".
    _accepted = acceptedScanLabels(_target).toSet();
    if (kDebugMode) {
      debugPrint('SCAN target: $_target (pool=$pool)');
    }
    _bootstrap();
    unawaited(_ensureDetector());
  }

  /// Loads the on-device detector on demand. The alarm repository warms it at
  /// boot, but a cold start, a release-only plugin failure, or an interrupted
  /// first load must not leave the scan screen silently stuck at 0%.
  Future<void> _ensureDetector() async {
    if (CocoDetector.I.isReady) {
      if (mounted) {
        setState(() {
          _detectorLoading = false;
          _detectorError = null;
        });
      }
      return;
    }
    if (_detectorLoading) return;
    if (mounted) {
      setState(() {
        _detectorLoading = true;
        _detectorError = null;
      });
    }
    try {
      await CocoDetector.I.load();
    } on Object catch (e) {
      debugPrint('detector retry failed: $e');
    }
    if (!mounted) return;
    setState(() {
      _detectorLoading = false;
      _detectorError = CocoDetector.I.isReady
          ? null
          : CocoDetector.I.loadError?.toString() ??
                'The on-device model did not load.';
    });
  }

  Future<void> _retryDetector() async {
    if (CocoDetector.I.isReady) CocoDetector.I.dispose();
    _detectErrors = 0;
    await _ensureDetector();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _busy = true; // stop frame callbacks before disposing
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have granted camera access in system settings. Retry as
    // soon as they come back instead of leaving a dead screen.
    if (state == AppLifecycleState.resumed && _permissionDenied) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    try {
      final status = await Permission.camera.status;
      if (!mounted) return;
      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          setState(() {
            _permissionDenied = true;
            _permissionPermanentlyDenied = true;
          });
          return;
        }
        final asked = await Permission.camera.request();
        if (!mounted) return;
        if (!asked.isGranted) {
          setState(() {
            _permissionDenied = true;
            _permissionPermanentlyDenied = asked.isPermanentlyDenied;
          });
          return;
        }
      }
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera found on this device.');
        return;
      }
      CameraDescription pick = cameras.first;
      for (final c in cameras) {
        if (c.lensDirection == CameraLensDirection.back) pick = c;
      }
      final old = _controller;
      _controller = null;
      await old?.dispose();
      final controller = CameraController(
        pick,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _error = null;
        _permissionDenied = false;
        _permissionPermanentlyDenied = false;
      });
    } on Exception catch (e) {
      debugPrint('camera bootstrap failed: $e');
      if (!mounted) return;
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
      _frameW = image.width;
      _frameH = image.height;
      final rgb = yuvToSquareRgb(
        image,
        sensorOrientation: _controller!.description.sensorOrientation,
        outSize: det.inputSize,
      );
      final dets = det.detect(rgb);
      _detections = dets;
      _detectErrors = 0;

      final hit = dets
          .where((d) => _accepted.contains(d.label))
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
      _detectErrors++;
      if (_detectErrors >= 3 && mounted) {
        setState(() {
          _detectorError = 'Live detection failed repeatedly. Retry the AI.';
        });
      }
    } finally {
      _busy = false;
    }
  }

  // Temporal gate: matched frames accrue presence time (capped at _holdMs),
  // misses decay at 1.25x speed, so merely waving the camera around fails.
  void _applySession(bool matched, String? label, double score, int dtMs) {
    if (matched) {
      _matchedLabel = label;
      _progress = math.min(
        1.0,
        _progress + (dtMs / _holdMs) * math.min(1.0, 0.4 + score),
      );
    } else {
      _progress = math.max(0.0, _progress - (dtMs / _holdMs) * 1.25);
    }
  }

  Future<void> _finish(String? label) async {
    setState(() => _finishing = true);
    final kind =
        widget.chosenKind ??
        (widget.alarm.challengeKind == ChallengeKind.scan
            ? ChallengeKind.scan
            : ChallengeKind.math);
    final repo = context.read<AlarmRepository>();
    await repo.completeRing(widget.alarm.id, kind);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        settings: _isTrial ? null : const RouteSettings(name: '/gate-success'),
        builder: (_) => SuccessScreen(
          kind: kind,
          scannedLabel: label,
          streak: repo.stats.currentStreak,
          totalWins: repo.stats.totalWins,
          isTrial: _isTrial,
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
            if (_controller != null &&
                _controller!.value.isInitialized &&
                _detections.isNotEmpty &&
                _frameW > 0)
              Positioned.fill(
                child: _DetectionBoxes(
                  detections: _displayDetections,
                  accepted: _accepted,
                  frameWidth: _frameW,
                  frameHeight: _frameH,
                  sensorOrientation: _controller!.description.sensorOrientation,
                  squareSize: CocoDetector.I.inputSize,
                ),
              ),
            if (_permissionDenied)
              _MessageCard(
                icon: '📷',
                title: 'Camera permission needed',
                body: _permissionPermanentlyDenied
                    ? 'Camera access is blocked. Open Android Settings, choose '
                          'Permissions, then allow Camera for Bangun.'
                    : 'The scan gate runs on-device and needs the camera. Your '
                          'frame is processed locally, nothing is uploaded.',
                actionLabel: _permissionPermanentlyDenied
                    ? 'Open app settings'
                    : 'Grant camera access',
                onAction: () async {
                  if (_permissionPermanentlyDenied) {
                    await openAppSettings();
                    return;
                  }
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
            else if (_detectorError != null)
              _MessageCard(
                icon: 'AI',
                title: 'On-device AI failed',
                body: '${_detectorError!}\n\nRetry the object detector.',
                actionLabel: 'Retry AI',
                onAction: () {
                  unawaited(_retryDetector());
                },
              )
            else ...[
              _ScanHud(
                target: _target,
                progress: _progress,
                detections: _displayDetections,
                matchedLabel: _matchedLabel,
                accepted: _accepted,
                holdMs: _holdMs,
                isTrial: _isTrial,
                detectorLoading: _detectorLoading,
              ),
            ],
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
    required this.accepted,
    required this.holdMs,
    required this.isTrial,
    required this.detectorLoading,
  });

  final String target;
  final double progress;
  final List<Detection> detections;
  final String? matchedLabel;
  final Set<String> accepted;
  final int holdMs;
  final bool isTrial;
  final bool detectorLoading;

  @override
  Widget build(BuildContext context) {
    final chips = detections.take(2).toList(growable: false);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                  Text(
                    targetEmoji(target),
                    style: const TextStyle(fontSize: 30),
                  ),
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
                        if (accepted.length > 1)
                          Text(
                            'also counts: '
                            '${accepted.where((l) => l != target).join(', ')}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Bg.sub,
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress),
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) {
                            final meter = math
                                .min(132.0, constraints.maxHeight * 0.32)
                                .clamp(96.0, 132.0)
                                .toDouble();
                            return SizedBox(
                              width: meter,
                              height: meter,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox(
                                    width: meter,
                                    height: meter,
                                    child: CircularProgressIndicator(
                                      value: value,
                                      strokeWidth: 9,
                                      strokeCap: StrokeCap.round,
                                      backgroundColor: Colors.white30,
                                      valueColor: AlwaysStoppedAnimation(
                                        value >= 1 ? Bg.success : Bg.ctaB,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${(value * 100).round()}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 24,
                                      shadows: [
                                        Shadow(blurRadius: 12, color: Bg.ink),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          detectorLoading
                              ? 'Loading on-device AI...'
                              : progress >= 1
                              ? 'got it!'
                              : matchedLabel == null
                              ? 'Find the $target and hold it in frame'
                              : '⏳ hold it — '
                                    '${((1 - progress) * holdMs / 1000).toStringAsFixed(1)}s'
                                    ' to 100%',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            shadows: [
                              Shadow(
                                blurRadius: 10,
                                color: Bg.ink.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'the meter is hold time, not AI confidence — keep it in frame',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Bg.ink.withValues(alpha: 0.7),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
                          color: accepted.contains(d.label)
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
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(0.0, constraints.maxHeight - 56),
              ),
              child: Center(
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws each live detection as a named square: outline + "emoji label %"
/// tag, green when the label counts as a hit for the current target.
class _DetectionBoxes extends StatelessWidget {
  const _DetectionBoxes({
    required this.detections,
    required this.accepted,
    required this.frameWidth,
    required this.frameHeight,
    required this.sensorOrientation,
    required this.squareSize,
  });

  final List<Detection> detections;
  final Set<String> accepted;
  final int frameWidth;
  final int frameHeight;
  final int sensorOrientation;
  final int squareSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => CustomPaint(
        size: constraints.biggest,
        painter: _BoxesPainter(
          items: [
            for (final d in detections)
              _BoxItem(
                rect: detectionBoxOnScreen(
                  unit: d.box,
                  frameWidth: frameWidth,
                  frameHeight: frameHeight,
                  sensorOrientation: sensorOrientation,
                  squareSize: squareSize,
                  screen: constraints.biggest,
                ),
                matched: accepted.contains(d.label),
                text: d.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _BoxItem {
  const _BoxItem({
    required this.rect,
    required this.matched,
    required this.text,
  });

  final Rect rect;
  final bool matched;
  final String text;
}

class _BoxesPainter extends CustomPainter {
  const _BoxesPainter({required this.items});

  final List<_BoxItem> items;

  @override
  void paint(Canvas canvas, Size canvasSize) {
    for (final item in items) {
      final r = item.rect.deflate(3);
      if (r.width < 30 || r.height < 30) continue;

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = item.matched ? 3.2 : 2.2
        ..color = item.matched
            ? Bg.success
            : Colors.white.withValues(alpha: 0.85);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(12)),
        stroke,
      );

      // Named tag, clamped to the canvas.
      final tp = TextPainter(
        text: TextSpan(
          text: '${targetEmoji(item.text)} ${item.text}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: item.matched ? Colors.white : Bg.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      const tagH = 20.0;
      final maxX = (canvasSize.width - tp.width - 18).clamp(
        0.0,
        canvasSize.width,
      );
      final tagX = r.left.clamp(0.0, maxX);
      final tagY = (r.top - tagH - 2).clamp(4.0, canvasSize.height - tagH - 4);
      final tagRect = Rect.fromLTWH(tagX, tagY, tp.width + 12, tagH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(7)),
        Paint()
          ..style = PaintingStyle.fill
          ..color = item.matched
              ? Bg.success
              : Colors.white.withValues(alpha: 0.92),
      );
      tp.paint(canvas, Offset(tagX + 6, tagY + 3));
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter oldDelegate) => true;
}
