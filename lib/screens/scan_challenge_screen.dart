import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../core/build_info.dart';
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
  int _hitStreak = 0;
  bool _torchOn = false;
  bool _wasConfirmed = false;
  final RgbFrameBuffer _rgbBuffer = RgbFrameBuffer();

  late Set<String> _accepted;
  late String _target;

  bool get _isTrial => widget.alarm.id == trialAlarmId;

  List<String> get _targetPool => widget.alarm.scanTargets.isNotEmpty
      ? widget.alarm.scanTargets
      : kDefaultScanTargets;

  /// Show every clear detection, not only the current target. Target matches
  /// are highlighted in green, while other objects stay visible so the screen
  /// reflects what the model actually sees.
  List<Detection> get _displayDetections {
    final ranked = _detections.toList(growable: false);
    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(CocoDetector.maxDetections).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final pool = _targetPool;
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

  /// Trial runs can reroll the target without leaving the scan screen. A real
  /// alarm stays locked to the object picked when it rang.
  void _shuffleTarget() {
    if (!_isTrial || _finishing) return;
    final pool = _targetPool;
    var next = pickScanTarget(pool, isTrial: true);
    if (pool.length > 1) {
      var guard = 0;
      while (next == _target && guard++ < 12) {
        next = pickScanTarget(pool, isTrial: true);
      }
    }
    setState(() {
      _target = next;
      _accepted = acceptedScanLabels(next).toSet();
      _progress = 0;
      _hitStreak = 0;
      _wasConfirmed = false;
      _matchedLabel = null;
      _lastGateAt = null;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final next = !_torchOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() => _torchOn = next);
      HapticFeedback.selectionClick();
    } on Object catch (e) {
      debugPrint('torch toggle failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('This camera cannot switch the torch.')),
        );
    }
  }

  void _showHint() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ScanHintSheet(
        target: _target,
        accepted: _accepted,
        isTrial: _isTrial,
      ),
    );
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
    // Never leave the torch burning while Bangun is in the background.
    if (state == AppLifecycleState.paused && _torchOn) {
      _torchOn = false;
      unawaited(
        _controller?.setFlashMode(FlashMode.off) ?? Future<void>.value(),
      );
    }
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
        _torchOn = false;
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
        buffer: _rgbBuffer,
      );
      final dets = det.detect(rgb);
      _detections = dets;
      _detectErrors = 0;

      final hit = dets
          .where((d) => _accepted.contains(d.label))
          .fold<Detection?>(null, (best, d) => best ?? d);

      // Do not trust a single-frame hit. A label must survive two nearby
      // frames before it can add hold time; a miss only removes one notch so
      // ordinary detector flicker does not reset the gate.
      final wasConfirmed = _wasConfirmed;
      _hitStreak = hit == null
          ? math.max(0, _hitStreak - 1)
          : math.min(3, _hitStreak + 1);
      final confirmed = hit != null && _hitStreak >= 2;
      _wasConfirmed = confirmed;
      if (confirmed && !wasConfirmed) {
        HapticFeedback.mediumImpact();
      }

      // Temporal gate delta — clamp so a background pause doesn't grant a
      // giant free chunk of presence time.
      final dt = _lastGateAt == null
          ? 84
          : now.difference(_lastGateAt!).inMilliseconds.clamp(0, 400);
      _lastGateAt = now;
      _applySession(confirmed, hit?.label, hit?.score ?? 0, dt);

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
    HapticFeedback.heavyImpact();
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
    final visibleDetections = _displayDetections;
    final preview = _controller != null && _controller!.value.isInitialized
        ? RepaintBoundary(
            child: ClipRect(
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
                visibleDetections.isNotEmpty &&
                _frameW > 0)
              Positioned.fill(
                child: RepaintBoundary(
                  child: _DetectionBoxes(
                    detections: visibleDetections,
                    accepted: _accepted,
                    frameWidth: _frameW,
                    frameHeight: _frameH,
                    sensorOrientation:
                        _controller!.description.sensorOrientation,
                    squareSize: CocoDetector.I.inputSize,
                  ),
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
                detections: visibleDetections,
                matchedLabel: _matchedLabel,
                holding: _hitStreak >= 2,
                accepted: _accepted,
                holdMs: _holdMs,
                isTrial: _isTrial,
                detectorLoading: _detectorLoading,
                torchOn: _torchOn,
                onTorch: () => unawaited(_toggleTorch()),
                onHint: _showHint,
                onShuffle: _isTrial ? _shuffleTarget : null,
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
    required this.holding,
    required this.accepted,
    required this.holdMs,
    required this.isTrial,
    required this.detectorLoading,
    required this.torchOn,
    required this.onTorch,
    required this.onHint,
    required this.onShuffle,
  });

  final String target;
  final double progress;
  final List<Detection> detections;
  final String? matchedLabel;
  final bool holding;
  final Set<String> accepted;
  final int holdMs;
  final bool isTrial;
  final bool detectorLoading;
  final bool torchOn;
  final VoidCallback onTorch;
  final VoidCallback onHint;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 640;
          final side = compact ? 12.0 : 16.0;
          final meter = compact ? 104.0 : 132.0;
          final status = detectorLoading
              ? 'Loading on-device AI...'
              : progress >= 1
              ? 'Got it!'
              : holding
              ? 'Hold it - '
                    '${((1 - progress) * holdMs / 1000).toStringAsFixed(1)}s '
                    'to 100%'
              : matchedLabel != null
              ? 'Target found - keep it in frame'
              : 'Find the $target and hold it in frame';
          return Padding(
            padding: EdgeInsets.fromLTRB(
              side,
              compact ? 10 : 14,
              side,
              compact ? 10 : 16,
            ),
            child: Column(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: _TargetCard(
                    target: target,
                    accepted: accepted,
                    isTrial: isTrial,
                    holding: holding,
                    compact: compact,
                    detectionCount: detections.length,
                    torchOn: torchOn,
                    onTorch: onTorch,
                    onHint: onHint,
                    onShuffle: onShuffle,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, inner) => SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: inner.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(height: compact ? 8 : 16),
                            _PulseHalo(
                              active: holding,
                              size: meter,
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: progress),
                                duration: const Duration(milliseconds: 120),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) => SizedBox(
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
                                          strokeWidth: compact ? 8 : 9,
                                          strokeCap: StrokeCap.round,
                                          backgroundColor: Colors.white30,
                                          valueColor: AlwaysStoppedAnimation(
                                            value >= 1 ? Bg.success : Bg.ctaB,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${(value * 100).round()}%',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: compact ? 21 : 24,
                                          shadows: const [
                                            Shadow(
                                              blurRadius: 12,
                                              color: Bg.ink,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: compact ? 8 : 10),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: Text(
                                status,
                                key: ValueKey(
                                  '$detectorLoading-$holding-${progress >= 1}',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: compact ? 13 : 14,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 10,
                                      color: Bg.ink.withValues(alpha: 0.7),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 4),
                              Text(
                                'the meter is hold time, not AI confidence - '
                                'keep it in frame',
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
                            if (detections.isNotEmpty) ...[
                              SizedBox(height: compact ? 12 : 18),
                              _DetectionsPanel(
                                detections: detections,
                                accepted: accepted,
                              ),
                            ],
                            if (!isTrial)
                              const Padding(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                  'locked - finishing the scan is the only exit',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: Colors.white70,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                kBuildStamp,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    required this.target,
    required this.accepted,
    required this.isTrial,
    required this.holding,
    required this.compact,
    required this.detectionCount,
    required this.torchOn,
    required this.onTorch,
    required this.onHint,
    required this.onShuffle,
  });

  final String target;
  final Set<String> accepted;
  final bool isTrial;
  final bool holding;
  final bool compact;
  final int detectionCount;
  final bool torchOn;
  final VoidCallback onTorch;
  final VoidCallback onHint;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final also = accepted
        .where((label) => label != target)
        .toList(growable: false);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.all(compact ? 13 : 16),
      decoration: BoxDecoration(
        color: Bg.card.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: holding ? Bg.success : Colors.transparent,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: holding
                ? Bg.success.withValues(alpha: 0.38)
                : Bg.ink.withValues(alpha: 0.14),
            blurRadius: holding ? 26 : 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: Tween<double>(begin: 0.72, end: 1).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Text(
                  targetEmoji(target),
                  key: ValueKey('emoji-$target'),
                  style: TextStyle(fontSize: compact ? 26 : 30),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        const SizedBox(width: 8),
                        _ModeBadge(isTrial: isTrial),
                      ],
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 240),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.18),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Align(
                        key: ValueKey('target-$target'),
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            target,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: Bg.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (also.isNotEmpty)
                      Text(
                        'also counts: ${also.join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: Bg.sub),
                      ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HudPill(
                icon: torchOn
                    ? Icons.flashlight_on_rounded
                    : Icons.flashlight_off_rounded,
                label: torchOn ? 'Torch on' : 'Torch',
                active: torchOn,
                onTap: onTorch,
              ),
              _HudPill(
                icon: Icons.lightbulb_outline_rounded,
                label: 'Tips',
                onTap: onHint,
              ),
              if (onShuffle != null)
                _HudPill(
                  icon: Icons.shuffle_rounded,
                  label: 'Shuffle',
                  onTap: onShuffle!,
                ),
              _HudPill(
                icon: Icons.visibility_outlined,
                label: detectionCount == 0
                    ? 'Scanning...'
                    : '$detectionCount in frame',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.isTrial});

  final bool isTrial;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isTrial ? Bg.cardSoft : Bg.ink,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isTrial ? 'TRIAL' : 'LOCKED',
        style: TextStyle(
          fontSize: 8.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w900,
          color: isTrial ? Bg.plum : Colors.white,
        ),
      ),
    );
  }
}

class _HudPill extends StatelessWidget {
  const _HudPill({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : Bg.plum;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active ? Bg.ctaA : Bg.cardSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulseHalo extends StatefulWidget {
  const _PulseHalo({
    required this.active,
    required this.size,
    required this.child,
  });

  final bool active;
  final double size;
  final Widget child;

  @override
  State<_PulseHalo> createState() => _PulseHaloState();
}

class _PulseHaloState extends State<_PulseHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseHalo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: Bg.success.withValues(alpha: 0.22 + 0.20 * t),
                      blurRadius: 16 + 22 * t,
                      spreadRadius: 1 + 5 * t,
                    ),
                  ]
                : null,
          ),
          child: Transform.scale(
            scale: widget.active ? 1 + 0.018 * t : 1,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _DetectionsPanel extends StatelessWidget {
  const _DetectionsPanel({required this.detections, required this.accepted});

  final List<Detection> detections;
  final Set<String> accepted;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
        decoration: BoxDecoration(
          color: Bg.ink.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'IN FRAME',
                  style: TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                Text(
                  '${detections.length} object'
                  '${detections.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final detection in detections)
                  _DetectionChip(
                    detection: detection,
                    matched: accepted.contains(detection.label),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionChip extends StatelessWidget {
  const _DetectionChip({required this.detection, required this.matched});

  final Detection detection;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        alignment: Alignment.centerLeft,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: matched ? Bg.success : Colors.white.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              targetEmoji(detection.label),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(width: 5),
            Text(
              '${detection.label} ${(detection.score * 100).round()}%',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: matched ? Colors.white : Bg.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanHintSheet extends StatelessWidget {
  const _ScanHintSheet({
    required this.target,
    required this.accepted,
    required this.isTrial,
  });

  final String target;
  final Set<String> accepted;
  final bool isTrial;

  @override
  Widget build(BuildContext context) {
    final also = accepted
        .where((label) => label != target)
        .toList(growable: false);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            child: BgCard(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Bg.hairline,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        targetEmoji(target),
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'SCAN TIPS',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 2,
                                color: Bg.sub,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              'How to catch a $target',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Bg.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const _HintRow(
                    icon: Icons.center_focus_strong_rounded,
                    text:
                        'Fill most of the frame with the object. Get close '
                        'enough that it is unmistakable.',
                  ),
                  const _HintRow(
                    icon: Icons.wb_sunny_rounded,
                    text:
                        'Turn on the torch or add light. Low light hides '
                        'edges and lowers confidence.',
                  ),
                  const _HintRow(
                    icon: Icons.timer_rounded,
                    text:
                        'Keep it steady for 3 seconds. The ring only counts '
                        'clear detections at 60% or higher.',
                  ),
                  const _HintRow(
                    icon: Icons.visibility_rounded,
                    text:
                        'Every object in frame gets a box. The target turns '
                        'green when the model counts it.',
                  ),
                  if (also.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'ALSO COUNTS',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 1.6,
                        color: Bg.sub,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final label in also)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Bg.cardSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${targetEmoji(label)} $label',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Bg.plum,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (isTrial) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Bg.cardSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Trial run: use Shuffle for a different object. Stats '
                        'stay unchanged.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: Bg.sub,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  InkPill(
                    icon: '👍',
                    label: 'Got it',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HintRow extends StatelessWidget {
  const _HintRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Bg.cardSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: Bg.plum),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: Bg.sub,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
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
  bool shouldRepaint(_BoxesPainter oldDelegate) {
    if (oldDelegate.items.length != items.length) return true;
    for (var i = 0; i < items.length; i++) {
      final a = oldDelegate.items[i];
      final b = items[i];
      if (a.rect != b.rect || a.matched != b.matched || a.text != b.text) {
        return true;
      }
    }
    return false;
  }
}
