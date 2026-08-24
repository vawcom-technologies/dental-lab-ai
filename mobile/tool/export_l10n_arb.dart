#!/usr/bin/env dart
// Export AppLocalizations _en/_de maps to ARB files.
//
// Usage (from mobile/):
//   dart run tool/export_l10n_arb.dart
//
// Writes:
//   lib/l10n/app_en.arb
//   lib/l10n/app_de.arb
//
// EN is the template/source. DE is machine-filled for coverage.
// Runtime still uses AppLocalizations maps — ARB is scaffolding for gen-l10n later.

import 'dart:convert';
import 'dart:io';

final _mapEntry = RegExp(
  r"""^\s*'([^']+)':\s*((?:'[^']*')|(?:"[^"]*")|(?:'[^']*(?:\\'[^']*)*')),?\s*$""",
  multiLine: true,
);

// Multi-line string entries: 'key': 'line1 '\n        'line2',
final _keyStart = RegExp(r"""^\s*'([^']+)':\s*(.*)$""");

Map<String, String> parseMap(String source, String mapName) {
  final start = source.indexOf('static const $mapName = <String, String>{');
  if (start < 0) {
    throw StateError('Could not find map $mapName');
  }
  final open = source.indexOf('{', start);
  var depth = 0;
  var end = open;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) {
        end = i;
        break;
      }
    }
  }
  final body = source.substring(open + 1, end);
  final out = <String, String>{};

  final lines = body.split('\n');
  String? pendingKey;
  final pendingParts = <String>[];

  String unquote(String s) {
    s = s.trim();
    if (s.endsWith(',')) s = s.substring(0, s.length - 1).trim();
    if ((s.startsWith("'") && s.endsWith("'")) ||
        (s.startsWith('"') && s.endsWith('"'))) {
      s = s.substring(1, s.length - 1);
    }
    return s.replaceAll(r"\'", "'").replaceAll(r'\\', r'\');
  }

  bool isCompleteQuoted(String s) {
    s = s.trim();
    if (s.endsWith(',')) s = s.substring(0, s.length - 1).trim();
    if (!s.startsWith("'")) return false;
    // naive: ends with unescaped '
    if (!s.endsWith("'")) return false;
    if (s.length >= 2) return true;
    return false;
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;

    if (pendingKey != null) {
      pendingParts.add(line.trim());
      final joined = pendingParts.join(' ');
      // try to detect completion: last non-space char before optional comma is '
      final stripped = joined.trim();
      if (stripped.endsWith("',") || stripped.endsWith("'")) {
        // concatenate adjacent dart string literals
        final pieces = RegExp(r"'((?:\\'|[^'])*)'")
            .allMatches(joined)
            .map((m) => m.group(1)!.replaceAll(r"\'", "'"))
            .toList();
        out[pendingKey!] = pieces.join();
        pendingKey = null;
        pendingParts.clear();
      }
      continue;
    }

    final m = _keyStart.firstMatch(line.trim());
    if (m == null) continue;
    final key = m.group(1)!;
    final rest = m.group(2)!.trim();
    if (isCompleteQuoted(rest) && !rest.contains("'\n")) {
      // may still be adjacent literals on one line: 'a' 'b'
      final pieces = RegExp(r"'((?:\\'|[^'])*)'")
          .allMatches(rest)
          .map((mm) => mm.group(1)!.replaceAll(r"\'", "'"))
          .toList();
      if (pieces.isNotEmpty) {
        out[key] = pieces.join();
        continue;
      }
    }
    // multi-line start
    pendingKey = key;
    pendingParts
      ..clear()
      ..add(rest);
  }

  return out;
}

Map<String, dynamic> toArb(Map<String, String> map, {required String locale}) {
  final arb = <String, dynamic>{
    '@@locale': locale,
  };
  final keys = map.keys.toList()..sort();
  for (final k in keys) {
    // ARB keys can't contain dots easily for gen-l10n — keep dotted keys as-is
    // for now (valid JSON). Flutter gen-l10n prefers camelCase; conversion later.
    arb[k] = map[k];
  }
  return arb;
}

void main() {
  final root = Directory.current;
  final locFile = File('${root.path}/lib/core/l10n/app_localizations.dart');
  if (!locFile.existsSync()) {
    stderr.writeln('Run from mobile/: missing ${locFile.path}');
    exit(1);
  }
  final source = locFile.readAsStringSync();
  final en = parseMap(source, '_en');
  final de = parseMap(source, '_de');

  final outDir = Directory('${root.path}/lib/l10n')..createSync(recursive: true);
  final enPath = File('${outDir.path}/app_en.arb');
  final dePath = File('${outDir.path}/app_de.arb');

  const encoder = JsonEncoder.withIndent('  ');
  enPath.writeAsStringSync('${encoder.convert(toArb(en, locale: 'en'))}\n');
  dePath.writeAsStringSync('${encoder.convert(toArb(de, locale: 'de'))}\n');

  stdout.writeln('Exported ${en.length} EN keys → ${enPath.path}');
  stdout.writeln('Exported ${de.length} DE keys → ${dePath.path}');
  final missing = en.keys.where((k) => !de.containsKey(k)).toList();
  if (missing.isNotEmpty) {
    stdout.writeln('DE missing ${missing.length} keys (run fill_missing_de.dart)');
  }
}
