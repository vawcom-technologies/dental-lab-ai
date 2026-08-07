import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

const kShadeCardGlow = [
  BoxShadow(
    color: Color(0xFFFFFFFF),
    blurRadius: 16,
    spreadRadius: 1,
  ),
  BoxShadow(
    color: Color(0x99FFFFFF),
    blurRadius: 8,
    spreadRadius: 0,
  ),
];

const kShadeZones = ['cervical', 'middle', 'incisal'];

const kVitaShades = [
  'A1', 'A2', 'A3', 'A3.5', 'A4',
  'B1', 'B2', 'B3', 'B4',
  'C1', 'C2', 'C3', 'C4',
  'D2', 'D3', 'D4',
];

const kTargetShades = ['M1', 'M2', 'M3'];

const kAllowedShades = [...kVitaShades, ...kTargetShades];

/// Mid-body mean RGB — same source as backend `VITA_SHADES` / swatches.
const kShadeRgb = <String, List<int>>{
  'A1': [210, 199, 169],
  'A2': [206, 188, 143],
  'A3': [208, 192, 154],
  'A3.5': [203, 181, 131],
  'A4': [191, 166, 119],
  'B1': [210, 202, 174],
  'B2': [206, 193, 154],
  'B3': [205, 185, 136],
  'B4': [201, 180, 128],
  'C1': [198, 187, 155],
  'C2': [192, 177, 137],
  'C3': [190, 175, 134],
  'C4': [181, 157, 112],
  'D2': [200, 188, 157],
  'D3': [200, 183, 143],
  'D4': [197, 182, 136],
  'M1': [226, 220, 205],
  'M2': [225, 218, 203],
  'M3': [229, 220, 204],
};

String vitaToothAsset(String shade) =>
    'assets/clinical/vita_teeth/${shade.toLowerCase()}.png';

Color shadeSwatch(String shade) {
  final rgb = kShadeRgb[shade];
  if (rgb == null) return AppColors.border;
  return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
}

List<double> rgbToLab(List<num> rgb) {
  double lin(num c) {
    final v = c / 255.0;
    return v > 0.04045 ? math.pow((v + 0.055) / 1.055, 2.4).toDouble() : v / 12.92;
  }

  final r = lin(rgb[0]), g = lin(rgb[1]), b = lin(rgb[2]);
  var x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047;
  var y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750);
  var z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883;
  double f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : (7.787 * t) + 16.0 / 116.0;
  final fx = f(x), fy = f(y), fz = f(z);
  return [116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz)];
}

/// CIEDE2000 (Sharma), kL=1.15 — matches backend `shade.py`.
double deltaECie2000(List<num> lab1, List<num> lab2) {
  final l1 = lab1[0].toDouble(), a1 = lab1[1].toDouble(), b1 = lab1[2].toDouble();
  final l2 = lab2[0].toDouble(), a2 = lab2[1].toDouble(), b2 = lab2[2].toDouble();
  final c1 = math.sqrt(a1 * a1 + b1 * b1);
  final c2 = math.sqrt(a2 * a2 + b2 * b2);
  final cBar = 0.5 * (c1 + c2);
  final cBar7 = math.pow(cBar, 7).toDouble();
  final g = 0.5 * (1.0 - math.sqrt(cBar7 / (cBar7 + math.pow(25.0, 7))));
  final a1p = (1.0 + g) * a1, a2p = (1.0 + g) * a2;
  final c1p = math.sqrt(a1p * a1p + b1 * b1);
  final c2p = math.sqrt(a2p * a2p + b2 * b2);
  double hp(double ap, double bp, double cp) {
    if (cp == 0) return 0;
    final h = math.atan2(bp, ap) * 180 / math.pi;
    return h < 0 ? h + 360 : h;
  }

  final h1p = hp(a1p, b1, c1p), h2p = hp(a2p, b2, c2p);
  final dLp = l2 - l1, dCp = c2p - c1p;
  double dhp = 0;
  if (c1p * c2p != 0) {
    var dh = h2p - h1p;
    if (dh > 180) dh -= 360;
    if (dh < -180) dh += 360;
    dhp = 2 * math.sqrt(c1p * c2p) * math.sin((dh * math.pi / 180) / 2);
  }
  final lBar = 0.5 * (l1 + l2), cBarP = 0.5 * (c1p + c2p);
  double hBar;
  if (c1p * c2p == 0) {
    hBar = h1p + h2p;
  } else {
    final hsum = h1p + h2p, hdiff = (h1p - h2p).abs();
    if (hdiff > 180) {
      hBar = hsum < 360 ? (hsum + 360) * 0.5 : (hsum - 360) * 0.5;
    } else {
      hBar = hsum * 0.5;
    }
  }
  final t = 1.0 -
      0.17 * math.cos((hBar - 30) * math.pi / 180) +
      0.24 * math.cos(2 * hBar * math.pi / 180) +
      0.32 * math.cos((3 * hBar + 6) * math.pi / 180) -
      0.20 * math.cos((4 * hBar - 63) * math.pi / 180);
  final dRo = 30.0 * math.exp(-math.pow((hBar - 275.0) / 25.0, 2));
  final cBarP7 = math.pow(cBarP, 7).toDouble();
  final rc = 2.0 * math.sqrt(cBarP7 / (cBarP7 + math.pow(25.0, 7)));
  final sl = 1.0 + (0.015 * math.pow(lBar - 50.0, 2)) / math.sqrt(20.0 + math.pow(lBar - 50.0, 2));
  final sc = 1.0 + 0.045 * cBarP;
  final sh = 1.0 + 0.015 * cBarP * t;
  final rt = -math.sin(2 * dRo * math.pi / 180) * rc;
  const kL = 1.15, kC = 1.0, kH = 1.0;
  return math.sqrt(
    math.pow(dLp / (kL * sl), 2) +
        math.pow(dCp / (kC * sc), 2) +
        math.pow(dhp / (kH * sh), 2) +
        rt * (dCp / (kC * sc)) * (dhp / (kH * sh)),
  );
}

double? deltaEVsShade(List<num> sampledLab, String shade) {
  final rgb = kShadeRgb[shade];
  if (rgb == null) return null;
  return deltaECie2000(sampledLab, rgbToLab(rgb));
}

/// ΔE 0→97%, 2→89%, 5→76%, 10→62%.
double confidenceFromDeltaE(double de) =>
    (1.0 / (1.0 + de / 16.0)).clamp(0.05, 0.97);

/// Mid-body enamel crop filling the chip (photo, not flat hex).
Widget shadeEnamelFill(String shade) {
  if (!kVitaShades.contains(shade)) {
    return ColoredBox(color: shadeSwatch(shade));
  }
  // ~1.7×: fills the box without collapsing to a flat mid-tone.
  return ClipRect(
    child: Transform.scale(
      scale: 1.7,
      alignment: Alignment.center,
      child: Image.asset(
        vitaToothAsset(shade),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => ColoredBox(color: shadeSwatch(shade)),
      ),
    ),
  );
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
