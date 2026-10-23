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

/// Emoji per challenge/tone/target label, for the pastel look.
const kTargetEmoji = {
  'person': '🧑',
  'bicycle': '🚲',
  'car': '🚗',
  'motorcycle': '🏍️',
  'airplane': '✈️',
  'bus': '🚌',
  'train': '🚆',
  'truck': '🚚',
  'boat': '⛵',
  'traffic light': '🚦',
  'fire hydrant': '🧯',
  'stop sign': '🛑',
  'parking meter': '🅿️',
  'bench': '🪨',
  'bird': '🐦',
  'cat': '🐱',
  'dog': '🐶',
  'horse': '🐎',
  'sheep': '🐑',
  'cow': '🐄',
  'elephant': '🐘',
  'bear': '🐻',
  'zebra': '🦓',
  'giraffe': '🦒',
  'backpack': '🎒',
  'handbag': '👜',
  'tie': '👔',
  'suitcase': '🧳',
  'umbrella': '☂️',
  'frisbee': '🥏',
  'skis': '🎿',
  'snowboard': '🏂',
  'sports ball': '⚽',
  'kite': '🪁',
  'baseball bat': '🏏',
  'baseball glove': '🧤',
  'skateboard': '🛹',
  'surfboard': '🏄',
  'tennis racket': '🎾',
  'bottle': '🍾',
  'wine glass': '🍷',
  'cup': '☕',
  'fork': '🍴',
  'knife': '🔪',
  'spoon': '🥄',
  'bowl': '🥣',
  'banana': '🍌',
  'apple': '🍎',
  'sandwich': '🥪',
  'orange': '🍊',
  'broccoli': '🥦',
  'carrot': '🥕',
  'hot dog': '🌭',
  'pizza': '🍕',
  'donut': '🍩',
  'cake': '🍰',
  'chair': '🪑',
  'couch': '🛋️',
  'potted plant': '🪴',
  'bed': '🛏️',
  'dining table': '🍽️',
  'toilet': '🚽',
  'tv': '📺',
  'laptop': '💻',
  'mouse': '🖱️',
  'remote': '🎛️',
  'keyboard': '⌨️',
  'cell phone': '📱',
  'microwave': '🍱',
  'oven': '🔥',
  'toaster': '🍞',
  'sink': '🚰',
  'refrigerator': '🧊',
  'book': '📚',
  'clock': '🕰️',
  'vase': '🏺',
  'scissors': '✂️',
  'teddy bear': '🧸',
  'hair drier': '💨',
  'toothbrush': '🪥',
};

String _targetEmojiAlias(String label) => switch (label) {
  'glass' => 'wine glass',
  'screen' => 'tv',
  _ => label,
};

String targetEmoji(String label) =>
    kTargetEmoji[_targetEmojiAlias(label)] ?? '🎯';
