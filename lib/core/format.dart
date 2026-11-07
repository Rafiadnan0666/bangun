/// Small formatting/label helpers shared across screens.
library;

const kWeekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const kWeekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String two(int n) => n.toString().padLeft(2, '0');

/// 24h clock label, e.g. `06:30`.
String hhmm(int hour, int minute) => '${two(hour)}:${two(minute)}';

/// Repeat label, e.g. `Every day` / `Mon Tue Sat` / `Once`.
String repeatLabel({required bool daily, required List<int> days}) {
  if (days.isEmpty) return 'Once';
  if (days.length == 7) return 'Every day';
  if (daily && days.length == 7) return 'Every day';
  final named = days.map((d) => kWeekdayNames[d - 1]).join(' ');
  return named;
}

/// `in 7 h 12 m` style badge text for the next ring.
String countdownText(DateTime? next) {
  if (next == null) return 'not scheduled';
  final d = next.difference(DateTime.now());
  if (d.inSeconds <= 0) return 'ringing';
  final h = d.inHours;
  final m = d.inMinutes - h * 60;
  if (h == 0) return 'in $m min';
  return 'in $h h ${two(m)} min';
}

String todayKey([DateTime? now]) {
  final t = now ?? DateTime.now();
  return '${t.year}-${two(t.month)}-${two(t.day)}';
}
