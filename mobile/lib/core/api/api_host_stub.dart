/// Web / non-IO: dart-define or loopback.
String resolveApiBase() {
  const fromEnv = String.fromEnvironment('API_BASE', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv;
  return 'http://127.0.0.1:8000';
}
