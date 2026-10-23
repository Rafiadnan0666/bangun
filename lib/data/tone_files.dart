/// Durable custom ringtone files.
///
/// A picked audio file is copied into the app documents directory at selection
/// time. SAF grants expire and picker cache copies get evicted, so the alarm
/// must never depend on the original path. Every managed file is named
/// `tone_<counter>.<ext>`.
///
/// The same class also cleans up: without a sweep, every file-picker session
/// leaves another copy behind forever.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

final class ToneFiles {
  ToneFiles._();

  static const prefix = 'tone_';

  /// A picked ringtone larger than this is almost certainly a mistake, and
  /// copying it into app storage would waste space. The editor checks this
  /// before copying and shows a readable message.
  static const maxBytes = 25 * 1024 * 1024;

  static bool exists(String? path) {
    if (path == null || path.isEmpty) return false;
    try {
      return File(path).existsSync();
    } on Object {
      return false;
    }
  }

  /// Copies [source] into app documents and returns the durable path.
  /// Removes a partial target when the copy fails.
  static Future<String> store(File source, String? extension) async {
    final docs = await getApplicationDocumentsDirectory();
    final ext = _safeExtension(extension);
    final target = File(
      '${docs.path}/$prefix${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    try {
      await source.copy(target.path);
      return target.path;
    } on Object {
      try {
        if (await target.exists()) await target.delete();
      } on Object {
        // Best effort: an orphan sweep on the next boot will catch it.
      }
      rethrow;
    }
  }

  /// Deletes one managed file when no remaining alarm references it. Files
  /// outside the managed `tone_` naming scheme are left alone.
  static Future<void> deleteIfUnreferenced(
    String? path,
    Iterable<String?> referenced,
  ) async {
    if (path == null || path.isEmpty) return;
    if (!_basename(path).startsWith(prefix)) return;
    if (referenced.any((p) => p == path)) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Object catch (e) {
      debugPrint('tone cleanup failed: $e');
    }
  }

  /// Removes managed tone files that no alarm references. Safe to run on
  /// every boot; only files inside the app documents directory are touched.
  static Future<void> sweepOrphans(Iterable<String?> referenced) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final keep = referenced.whereType<String>().toSet();
      await for (final entity in Directory(docs.path).list()) {
        if (entity is! File) continue;
        if (!_basename(entity.path).startsWith(prefix)) continue;
        if (keep.contains(entity.path)) continue;
        try {
          await entity.delete();
        } on Object catch (e) {
          debugPrint('tone sweep skip: $e');
        }
      }
    } on Object catch (e) {
      debugPrint('tone sweep failed: $e');
    }
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  static String _safeExtension(String? raw) {
    final ext = (raw ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (ext.isEmpty || ext.length > 5) return 'audio';
    return ext;
  }
}
