import 'dart:convert';

/// Case/punctuation-insensitive identity for a spoken phrase, so STT
/// variations ("Open wide." / "open wide") count as the same phrase.
String phraseKey(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}]+', unicode: true), ' ')
    .trim();

/// How often each phrase was sent. Only phrases sent [minRepeats]+ times are
/// offered as quick pills, so one-off sentences never clutter the pane.
class PhraseCounts {
  PhraseCounts();

  factory PhraseCounts.fromJson(String? raw) {
    final out = PhraseCounts();
    if (raw == null || raw.isEmpty) return out;
    try {
      final data = jsonDecode(raw);
      if (data is! List) return out;
      for (final row in data) {
        if (row is! Map) continue;
        final text = '${row['t'] ?? ''}'.trim();
        final count = row['n'];
        if (text.isEmpty || count is! int) continue;
        out._rows[phraseKey(text)] = _Row(text, count, out._tick++);
      }
    } catch (_) {}
    return out;
  }

  static const minRepeats = 2;
  static const _maxKept = 60;

  final Map<String, _Row> _rows = {};
  int _tick = 0;

  bool get isEmpty => _rows.isEmpty;

  void add(String text) {
    final shown = text.trim();
    final key = phraseKey(shown);
    if (key.isEmpty) return;
    final prev = _rows[key];
    _rows[key] = _Row(shown, (prev?.count ?? 0) + 1, _tick++);
    if (_rows.length > _maxKept) {
      final drop = _rows.entries.reduce(
        (a, b) => a.value.count != b.value.count
            ? (a.value.count < b.value.count ? a : b)
            : (a.value.tick < b.value.tick ? a : b),
      );
      _rows.remove(drop.key);
    }
  }

  void remove(String text) => _rows.remove(phraseKey(text));

  void clear() => _rows.clear();

  /// Repeated phrases, most used first (ties: most recent first).
  List<String> repeated({int limit = 12}) {
    final rows = _rows.values.where((r) => r.count >= minRepeats).toList()
      ..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.tick.compareTo(a.tick);
      });
    return [for (final r in rows.take(limit)) r.text];
  }

  String toJson() => jsonEncode([
    for (final r in _rows.values) {'t': r.text, 'n': r.count},
  ]);
}

class _Row {
  const _Row(this.text, this.count, this.tick);
  final String text;
  final int count;
  final int tick;
}
