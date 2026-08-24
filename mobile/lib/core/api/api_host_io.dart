import 'dart:io' show Platform;

/// Resolves API host for every run path (IDE, Xcode, bare `flutter run`).
///
/// Physical iPads cannot use 127.0.0.1. Debug builds on a real iOS device
/// fall back to this Mac's Bonjour name.
/// ponytail: change if this Mac is renamed
String resolveApiBase() {
  const fromEnv = String.fromEnvironment('API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv;
  if (!bool.fromEnvironment('dart.vm.product') && Platform.isIOS) {
    final sim = Platform.environment['SIMULATOR_DEVICE_NAME'];
    if (sim == null || sim.isEmpty) {
      return 'http://Mishis-MacBook-Pro.local:8000';
    }
  }
  return 'http://127.0.0.1:8000';
}
