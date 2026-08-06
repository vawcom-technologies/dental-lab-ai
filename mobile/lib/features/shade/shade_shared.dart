import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

const kShadeCardGlow = [
  BoxShadow(color: Color(0xD9FFFFFF), blurRadius: 12, spreadRadius: 1),
];

const kShadeZones = ['cervical', 'middle', 'incisal'];

const kVitaShades = [
  'A1', 'A2', 'A3', 'A3.5', 'A4',
  'B1', 'B2', 'B3', 'B4',
  'C1', 'C2', 'C3', 'C4',
  'D2', 'D3', 'D4',
];

Color shadeSwatch(String shade) {
  const map = {
    'A1': Color(0xFFF2E0C9),
    'A2': Color(0xFFECD2B4),
    'A3': Color(0xFFE2C09C),
    'A3.5': Color(0xFFD6B08A),
    'A4': Color(0xFFC69E7A),
    'B1': Color(0xFFF4E6D2),
    'B2': Color(0xFFECD8BC),
    'B3': Color(0xFFE0C4A0),
    'B4': Color(0xFFD2B28C),
    'C1': Color(0xFFE6D6C4),
    'C2': Color(0xFFD6C2AC),
    'C3': Color(0xFFC4AE96),
    'C4': Color(0xFFB09A84),
    'D2': Color(0xFFE4D0BA),
    'D3': Color(0xFFD2BAA0),
    'D4': Color(0xFFC4AC92),
  };
  return map[shade] ?? AppColors.border;
}

String capitalizeZone(String zone) =>
    zone.isEmpty ? zone : zone[0].toUpperCase() + zone.substring(1);

dynamic _deepCopy(dynamic v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries) e.key.toString(): _deepCopy(e.value),
    };
  }
  if (v is List) {
    return [for (final e in v) _deepCopy(e)];
  }
  return v;
}

List<Map<String, dynamic>> cloneShadeMaps(List<Map<String, dynamic>> rows) {
  return [
    for (final row in rows) Map<String, dynamic>.from(_deepCopy(row) as Map),
  ];
}
