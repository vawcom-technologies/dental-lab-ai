#!/usr/bin/env dart
// Fill missing German strings for Elite Dent l10n.
//
// Workflow (EN is source of truth):
//   1. Developers add EN keys to AppLocalizations (_en + getter) — or to app_en.arb
//   2. Run: dart run tool/export_l10n_arb.dart   (optional sync maps → ARB)
//   3. Run: dart run tool/fill_missing_de.dart
//        - Fills missing DE in lib/l10n/app_de.arb
//        - Also patches _de in lib/core/l10n/app_localizations.dart when possible
//   4. Spot-check DE in the running app
//
// Translation sources (in order):
//   a) DEEPL_API_KEY env → DeepL API (free or pro endpoint auto-detected)
//   b) Bundled glossary / heuristic table for common dental UI phrases
//   c) Otherwise prints missing keys and leaves a TODO marker value
//
// Usage (from mobile/):
//   dart run tool/fill_missing_de.dart
//   DEEPL_API_KEY=xxx dart run tool/fill_missing_de.dart

import 'dart:convert';
import 'dart:io';

const enArbPath = 'lib/l10n/app_en.arb';
const deArbPath = 'lib/l10n/app_de.arb';
const locPath = 'lib/core/l10n/app_localizations.dart';

/// Small dental / UI glossary used when DeepL is unavailable.
const glossary = <String, String>{
  'Save': 'Speichern',
  'Cancel': 'Abbrechen',
  'Delete': 'Löschen',
  'Edit': 'Bearbeiten',
  'Loading…': 'Laden…',
  'Uploading…': 'Wird hochgeladen…',
  'Working…': 'Wird bearbeitet…',
  'Saving…': 'Wird gespeichert…',
  'Refresh': 'Aktualisieren',
  'Close': 'Schließen',
  'Done': 'Fertig',
  'Approve': 'Genehmigen',
  'Reject': 'Ablehnen',
  'Request': 'Anfragen',
  'Patient': 'Patient',
  'Patients': 'Patienten',
  'Laboratory': 'Labor',
  'Laboratories': 'Labore',
  'Dentist': 'Zahnarzt',
  'Shade Detection': 'Farbbestimmung',
  'Smile Preview': 'Lächeln-Vorschau',
  'Scan Body': 'Scanbody',
  'Settings': 'Einstellungen',
  'Appointments': 'Termine',
  'Camera': 'Kamera',
  'Messages': 'Nachrichten',
  'Notifications': 'Benachrichtigungen',
  'Reports': 'Berichte',
  'Profile': 'Profil',
  'Dashboard': 'Übersicht',
  'Scans': 'Scans',
  'Add': 'Hinzufügen',
  'Add patient': 'Patient hinzufügen',
  'Search': 'Suchen',
  'Continue': 'Weiter',
  'Required': 'Pflichtfeld',
  'Online': 'Online',
  'Offline': 'Offline',
  'Undo': 'Rückgängig',
  'Redo': 'Wiederholen',
  'Rename': 'Umbenennen',
  'Retry': 'Erneut versuchen',
  'Share': 'Teilen',
  'Upload': 'Hochladen',
  'Gallery': 'Galerie',
  'Take photo': 'Foto aufnehmen',
};

String heuristicDe(String en) {
  if (glossary.containsKey(en)) return glossary[en]!;
  // Light phrase heuristics for coverage (MT-quality, not perfect)
  var s = en;
  s = s.replaceAll('Loading ', 'Laden: ');
  s = s.replaceAll('Loading…', 'Laden…');
  s = s.replaceAll('…', '…');
  if (s == en && !glossary.containsKey(en)) {
    return 'TODO_DE: $en';
  }
  return s;
}

Future<String?> deeplTranslate(String text, String apiKey) async {
  // DeepL Free keys end with :fx; Pro keys do not.
  final useFree = apiKey.trim().endsWith(':fx');
  final host = useFree
      ? 'https://api-free.deepl.com/v2/translate'
      : 'https://api.deepl.com/v2/translate';
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse(host));
    req.headers.contentType =
        ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
    req.write(
      'auth_key=${Uri.encodeQueryComponent(apiKey)}'
      '&text=${Uri.encodeQueryComponent(text)}'
      '&source_lang=EN'
      '&target_lang=DE',
    );
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      stderr.writeln('DeepL HTTP ${res.statusCode}: $body');
      return null;
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final translations = json['translations'] as List<dynamic>?;
    if (translations == null || translations.isEmpty) return null;
    return (translations.first as Map)['text'] as String?;
  } catch (e) {
    stderr.writeln('DeepL error: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

Map<String, String> readArb(String path) {
  final file = File(path);
  if (!file.existsSync()) return {};
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final out = <String, String>{};
  for (final e in json.entries) {
    if (e.key.startsWith('@')) continue;
    if (e.value is String) out[e.key] = e.value as String;
  }
  return out;
}

void writeArb(String path, Map<String, String> map, String locale) {
  final arb = <String, dynamic>{'@@locale': locale};
  final keys = map.keys.toList()..sort();
  for (final k in keys) {
    arb[k] = map[k];
  }
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(arb)}\n');
}

String escDart(String s) =>
    s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

/// Insert missing keys into the `_de` map in app_localizations.dart.
void patchAppLocalizationsDe(Map<String, String> filled) {
  final file = File(locPath);
  if (!file.existsSync()) {
    stderr.writeln('Skip map patch — missing $locPath');
    return;
  }
  var src = file.readAsStringSync();
  final existing = RegExp(r"'([^']+)':").allMatches(src).map((m) => m.group(1)!).toSet();
  final toAdd = filled.entries.where((e) => !src.contains("'${e.key}':")).toList();
  // Also fill keys present in EN map but missing in DE section only.
  // Safer approach: find `_de =` block and append before closing `};`
  final deMarker = "static const _de = <String, String>{";
  final deStart = src.indexOf(deMarker);
  if (deStart < 0) return;
  final close = src.indexOf('\n  };', deStart);
  if (close < 0) return;

  final deSlice = src.substring(deStart, close);
  final missingInDe = <MapEntry<String, String>>[];
  for (final e in filled.entries) {
    if (!deSlice.contains("'${e.key}':")) {
      missingInDe.add(e);
    }
  }
  if (missingInDe.isEmpty) {
    stdout.writeln('AppLocalizations _de already has all filled keys');
    return;
  }
  final buf = StringBuffer();
  for (final e in missingInDe) {
    buf.writeln("    '${e.key}': '${escDart(e.value)}',");
  }
  src = src.substring(0, close) + '\n' + buf.toString() + src.substring(close);
  file.writeAsStringSync(src);
  stdout.writeln('Patched ${missingInDe.length} keys into $locPath (_de)');
}

Future<void> main() async {
  // Ensure ARB exists — export first if needed
  if (!File(enArbPath).existsSync()) {
    stdout.writeln('No ARB yet — running export_l10n_arb.dart…');
    final r = await Process.run('dart', ['run', 'tool/export_l10n_arb.dart']);
    stdout.write(r.stdout);
    stderr.write(r.stderr);
    if (r.exitCode != 0) exit(r.exitCode);
  }

  final en = readArb(enArbPath);
  final de = readArb(deArbPath);
  if (en.isEmpty) {
    stderr.writeln('Empty EN ARB at $enArbPath');
    exit(1);
  }

  final missing = en.keys.where((k) => !de.containsKey(k) || de[k]!.isEmpty).toList()
    ..sort();
  if (missing.isEmpty) {
    stdout.writeln('DE coverage 100% (${en.length} keys). Nothing to fill.');
    exit(0);
  }

  stdout.writeln('Missing DE: ${missing.length} / ${en.length}');
  final apiKey = Platform.environment['DEEPL_API_KEY']?.trim();
  final filled = Map<String, String>.from(de);
  var deeplCount = 0;
  var glossaryCount = 0;
  var todoCount = 0;

  for (final key in missing) {
    final enText = en[key]!;
    String? deText;
    if (apiKey != null && apiKey.isNotEmpty) {
      deText = await deeplTranslate(enText, apiKey);
      if (deText != null) deeplCount++;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    if (deText == null) {
      if (glossary.containsKey(enText)) {
        deText = glossary[enText]!;
        glossaryCount++;
      } else {
        deText = heuristicDe(enText);
        if (deText.startsWith('TODO_DE:')) {
          todoCount++;
          stdout.writeln('  TODO  $key = $enText');
        } else {
          glossaryCount++;
        }
      }
    }
    filled[key] = deText;
  }

  writeArb(deArbPath, filled, 'de');
  patchAppLocalizationsDe(
    Map.fromEntries(missing.map((k) => MapEntry(k, filled[k]!))),
  );

  stdout.writeln(
    'Filled DE → $deArbPath '
    '(DeepL: $deeplCount, glossary/heuristic: $glossaryCount, TODO: $todoCount)',
  );
  if (apiKey == null || apiKey.isEmpty) {
    stdout.writeln(
      'Tip: set DEEPL_API_KEY for higher-quality machine translation.',
    );
  }
}
