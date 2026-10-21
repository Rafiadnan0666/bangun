// Generates the built-in alarm tones as 16-bit PCM WAV assets.
// Run:  dart run tools/gen_sounds.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const int sampleRate = 44100;

void main() {
  Directory('assets/sounds').createSync(recursive: true);
  writeWav('assets/sounds/morning_bricks.wav', _morningBricks());
  writeWav('assets/sounds/twin_chime.wav', _twinChime());
  writeWav('assets/sounds/siren_rush.wav', _sirenRush());
  writeWav('assets/sounds/digital_chirp.wav', _digitalChirp());
  stdout.writeln('Generated alarm tones.');
}

void _beep(
  List<double> out, {
  required double freq,
  required double dur,
  required double vol,
  int? attackMs,
  double? rampFreqTo,
}) {
  final n = (dur * sampleRate).round();
  final attack = attackMs == null ? 0 : (attackMs / 1000 * sampleRate).round();
  final target = rampFreqTo ?? freq;
  for (var i = 0; i < n; i++) {
    var env = 1.0;
    if (attack > 0 && i < attack) env = i / attack;
    if (attack > 0 && n - i < attack) env = (n - i) / attack;
    final t = i / sampleRate;
    final f = freq + (target - freq) * (i / math.max(1, n - 1));
    final w = 2 * math.pi * f * t;
    var v = math.sin(w) + 0.18 * math.sin(2 * w);
    out.add((v * env * vol).clamp(-1.0, 1.0));
  }
}

void _gap(List<double> out, double dur) {
  final n = (dur * sampleRate).round();
  out.addAll(List<double>.filled(n, 0));
}

/// Classic brick-digital: beep beep beeeep · beep beep beeeep (~4.4 s loop).
List<double> _morningBricks() {
  final s = <double>[];
  for (var rep = 0; rep < 2; rep++) {
    _beep(s, freq: 1174.7, dur: 0.13, vol: 0.42, attackMs: 6);
    _gap(s, 0.07);
    _beep(s, freq: 1174.7, dur: 0.13, vol: 0.42, attackMs: 6);
    _gap(s, 0.07);
    _beep(s, freq: 1568.0, dur: 0.26, vol: 0.46, attackMs: 6);
    _gap(s, rep == 0 ? 0.42 : 0.60);
  }
  return s;
}

/// Soft marimba-ish two-note chime run (~4.8 s loop).
List<double> _twinChime() {
  const notes = [659.26, 880.0, 987.77, 880.0, 659.26, 587.33, 659.26, 880.0];
  final s = <double>[];
  for (var rep = 0; rep < 2; rep++) {
    for (final f in notes) {
      _chime(s, f, 0.42);
      _gap(s, 0.04);
    }
    _gap(s, 0.55);
  }
  return s;
}

void _chime(List<double> out, double freq, double dur) {
  final n = (dur * sampleRate).round();
  for (var i = 0; i < n; i++) {
    final env = math.exp(-4.2 * i / n); // percussive decay
    final w = 2 * math.pi * freq * i / sampleRate;
    var v = math.sin(w) + 0.35 * math.sin(2.76 * w); // marimba partial
    out.add((v * env * 0.5).clamp(-1.0, 1.0));
  }
}

/// Rising-falling wail, 2 sweeps (~5.0 s loop).
List<double> _sirenRush() {
  final n = (5.0 * sampleRate).round();
  final s = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final f = 520 + 260 * math.sin(2 * math.pi * t / 2.4);
    final w = 2 * math.pi * f * t;
    var v = math.sin(w) + 0.22 * math.sin(2 * w);
    s[i] = (v * 0.42).clamp(-1.0, 1.0);
  }
  return s;
}

/// Fast double-chirp digital alarm, phone-in-my-ear vibes (~2.6 s loop).
List<double> _digitalChirp() {
  final s = <double>[];
  for (var rep = 0; rep < 4; rep++) {
    _beep(s, freq: 1960, dur: 0.05, vol: 0.45, attackMs: 3, rampFreqTo: 2320);
    _gap(s, 0.045);
    _beep(s, freq: 2620, dur: 0.05, vol: 0.45, attackMs: 3, rampFreqTo: 2280);
    _gap(s, 0.205);
  }
  return s;
}

void writeWav(String path, List<double> samples) {
  final dataBytes = ByteData(2 * samples.length);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    dataBytes.setInt16(2 * i, v, Endian.little);
  }
  final dataSize = dataBytes.lengthInBytes;
  final b = BytesBuilder();
  b.addUtf8('RIFF');
  b.addInt32(36 + dataSize);
  b.addUtf8('WAVE');
  b.addUtf8('fmt ');
  b.addInt32(16); // PCM
  b.addInt16(1);
  b.addInt16(1); // mono
  b.addInt32(sampleRate);
  b.addInt32(sampleRate * 2); // byte rate
  b.addInt16(2); // block align
  b.addInt16(16); // bits
  b.addUtf8('data');
  b.addInt32(dataSize);
  b.add(dataBytes.buffer.asUint8List());

  File(path).writeAsBytesSync(b.takeBytes(), flush: true);
  stdout.writeln('  $path (${(dataSize / 1024).round()} KB)');
}

extension on BytesBuilder {
  void addUtf8(String s) => add(s.codeUnits);
  void addInt32(int v) => add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  void addInt16(int v) => add([v & 0xFF, (v >> 8) & 0xFF]);
}
