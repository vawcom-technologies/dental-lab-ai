import '../models/chat_models.dart';

/// Detects an in-progress `@query` immediately before [cursor].
class MentionDraft {
  const MentionDraft({required this.atIndex, required this.query});

  /// Index of the `@` that started this mention.
  final int atIndex;

  /// Text after `@` up to the cursor (no spaces).
  final String query;
}

final _draftPattern = RegExp(r'(^|[\s])@([^\s@]*)$');

/// Returns the active @mention draft at [cursor], or null if none.
MentionDraft? mentionDraftAt(String text, int cursor) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final match = _draftPattern.firstMatch(before);
  if (match == null) return null;
  final atIndex = match.start + match.group(1)!.length;
  return MentionDraft(atIndex: atIndex, query: match.group(2) ?? '');
}

/// Replaces `@query` with `@Label ` and returns the new text + caret.
({String text, int cursor}) insertMention({
  required String text,
  required int cursor,
  required MentionDraft draft,
  required PatientMention mention,
}) {
  final after = cursor <= text.length ? text.substring(cursor) : '';
  final before = text.substring(0, draft.atIndex);
  final inserted = '@${mention.label} ';
  final next = '$before$inserted$after';
  return (text: next, cursor: before.length + inserted.length);
}

/// Mentions whose `@label` still appears in [text].
List<PatientMention> mentionsPresentIn(
  String text,
  List<PatientMention> pending,
) {
  if (pending.isEmpty) return const [];
  final kept = <PatientMention>[];
  final seen = <String>{};
  for (final mention in pending) {
    if (mention.id.isEmpty || seen.contains(mention.id)) continue;
    if (!_labelAppears(text, mention.label)) continue;
    seen.add(mention.id);
    kept.add(mention);
  }
  return kept;
}

bool _labelAppears(String text, String label) {
  final needle = '@${label.trim()}';
  if (needle.length < 2) return false;
  return text.contains(needle);
}

class MentionSpan {
  const MentionSpan({
    required this.start,
    required this.end,
    required this.mention,
  });

  final int start;
  final int end;
  final PatientMention mention;
}

/// Locate `@label` ranges for rendering tappable chips. Longer labels first
/// so "Jane Doe" wins over "Jane".
List<MentionSpan> mentionSpansIn(String text, List<PatientMention> mentions) {
  if (text.isEmpty || mentions.isEmpty) return const [];
  final ranked = [...mentions]..sort(
      (a, b) => b.label.trim().length.compareTo(a.label.trim().length),
    );
  final taken = List<bool>.filled(text.length, false);
  final spans = <MentionSpan>[];
  for (final mention in ranked) {
    final needle = '@${mention.label.trim()}';
    if (needle.length < 2) continue;
    var from = 0;
    while (true) {
      final index = text.indexOf(needle, from);
      if (index < 0) break;
      final end = index + needle.length;
      final overlap = taken.sublist(index, end).any((v) => v);
      if (!overlap) {
        for (var i = index; i < end; i++) {
          taken[i] = true;
        }
        spans.add(MentionSpan(start: index, end: end, mention: mention));
      }
      from = index + 1;
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  return spans;
}

String patientRowLabel(Map<String, dynamic> row) {
  final first = '${row['first_name'] ?? ''}'.trim();
  final last = '${row['last_name'] ?? ''}'.trim();
  final name = '$first $last'.trim();
  return name.isEmpty ? 'Unnamed patient' : name;
}

List<Map<String, dynamic>> filterPatientsForMention(
  List<Map<String, dynamic>> patients,
  String query, {
  int limit = 8,
}) {
  final q = query.trim().toLowerCase();
  final hits = <Map<String, dynamic>>[];
  for (final row in patients) {
    final id = '${row['id'] ?? ''}'.trim();
    if (id.isEmpty) continue;
    if (q.isNotEmpty) {
      final blob = [
        row['first_name'],
        row['last_name'],
        patientRowLabel(row),
      ].whereType<Object>().join(' ').toLowerCase();
      if (!blob.contains(q)) continue;
    }
    hits.add(row);
    if (hits.length >= limit) break;
  }
  return hits;
}
