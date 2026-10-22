import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/palette.dart';
import 'data/alarm_repository.dart';
import 'screens/home_screen.dart';
import 'screens/ring_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Alarm.init();
  } on Exception catch (e) {
    debugPrint('Alarm.init failed: $e'); // app still runs without scheduling
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => AlarmRepository(),
      child: const BangunApp(),
    ),
  );
}

/// App shell. Owns the navigator key + the ring router: the `alarm` plugin
/// emits on a seeded BehaviorSubject, so even cold-start rings (full-screen
/// intent relaunch) replay into our listener and get routed to [RingScreen].
/// Host-side losses (boot-window refusals, stale-at-boot drops) surface as
/// [AlarmDropped]/[AlarmMoved] events  cleared or re-armed here.
class BangunApp extends StatefulWidget {
  const BangunApp({super.key});

  @override
  State<BangunApp> createState() => _BangunAppState();
}

class _BangunAppState extends State<BangunApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final _RingRouteTracker _ringTracker = _RingRouteTracker();

  StreamSubscription<AlarmSet>? _ringSub;
  StreamSubscription<AlarmEvent>? _eventSub;
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _ringSub = Alarm.ringing.listen(_routeRing);
    _eventSub = Alarm.events.listen(_onHostEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_booted) return;
      _booted = true;
      unawaited(_bootRepository());
    });
  }

  Future<void> _bootRepository() async {
    final repo = context.read<AlarmRepository>();
    await repo.boot();
    // Cold-start ring: the BehaviorSubject replays current ringing state.
    if (mounted) _routeRing(Alarm.ringing.value);
  }

  /// Host-driven change: a dropped alarm (refused by the platform or stale at
  /// boot) can no longer ring on its old slot  clear bell state and quietly
  /// re-arm the next occurrence. `AlarmMoved` is handled natively by the
  /// plugin (it re-stored the alarm with a new time), so nothing to do.
  void _onHostEvent(AlarmEvent event) {
    final repo = context.read<AlarmRepository>();
    if (event is AlarmDropped) {
      repo.onAlarmStopped(event.id);
      unawaited(repo.rearm(event.id));
    }
  }

  void _routeRing(AlarmSet set) {
    final navigator = _navKey.currentState;
    if (navigator == null) return;
    context.read<AlarmRepository>().onRingEvent(set);
    if (set.alarms.isEmpty || _ringTracker.open) return;
    final id = set.alarms.first.id;
    _ringTracker.open = true;
    unawaited(
      navigator
          .push(RingScreen.route(id))
          .then((_) => _ringTracker.open = false),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Belt & braces: refresh ringing state when the user comes back.
      _routeRing(Alarm.ringing.value);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ringSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bangun',
      debugShowCheckedModeBanner: false,
      theme: bangunTheme(),
      navigatorKey: _navKey,
      navigatorObservers: [_ringTracker],
      // The layout is tuned for phones with default text size; clamp extreme
      // accessibility scales so every card still fits the screen.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.12,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const HomeScreen(),
    );
  }
}

/// Keeps a simple answer to "is our /ring route on the stack?" so repeated
/// ring events never stack duplicate ring screens.
class _RingRouteTracker extends NavigatorObserver {
  bool open = false;

  static bool _isRing(Route<dynamic>? route) =>
      route?.settings.name == '/ring';

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRing(route)) open = true;
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRing(route)) open = false;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_isRing(route)) open = false;
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_isRing(oldRoute)) open = false;
    if (_isRing(newRoute)) open = true;
  }
}
