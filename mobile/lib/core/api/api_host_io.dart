import 'dart:io' show Platform;

/// Resolves API host for every run path (IDE, Xcode, bare `flutter run`).
///
/// Physical iPads cannot use 127.0.0.1. Debug builds on a real iOS device
/// fall back to this Mac's Bonjour name.
String resolveApiBase() {
  const fromEnv = String.fromEnvironment('API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) {
    return fromEnv.trim().replaceFirst(RegExp(r'/$'), '');
  }
  if (!bool.fromEnvironment('dart.vm.product') && Platform.isIOS) {
    if (_looksLikeIosSimulator()) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://Arhams-MacBook-Pro.local:8000';
  }
  return 'http://127.0.0.1:8000';
}

bool _looksLikeIosSimulator() {
  const keys = [
    'SIMULATOR_DEVICE_NAME',
    'SIMULATOR_UDID',
    'SIMULATOR_HOST_HOME',
    'SIMULATOR_ROOT',
  ];
  for (final key in keys) {
    final value = Platform.environment[key];
    if (value != null && value.isNotEmpty) return true;
  }
  // Flutter does not forward SIMULATOR_* into the Dart isolate. The sandbox
  // HOME on Simulator usually lives under CoreSimulator; newer runtimes only
  // expose that path on the Flutter executable.
  final home = Platform.environment['HOME'] ?? '';
  if (home.contains('CoreSimulator')) return true;
  try {
    if (Platform.resolvedExecutable.contains('CoreSimulator')) return true;
  } catch (_) {}
  return false;
}
