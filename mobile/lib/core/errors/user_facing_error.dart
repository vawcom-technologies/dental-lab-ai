import '../l10n/app_localizations.dart';

final _machineCodePrefix = RegExp(
  r'^\s*(?:ERROR|ERR|HTTP)[_-][A-Z0-9_]+\s*:\s*',
  caseSensitive: false,
);
final _machineCodeToken = RegExp(
  r'\b(?:ERROR|ERR|HTTP)[_-][A-Z0-9_]+\b',
  caseSensitive: false,
);

/// Drops `ERROR_403_FORBIDDEN:` / `HTTP_403` tokens from API copy.
String stripMachineErrorCodes(String text) {
  var out = text.trim();
  while (_machineCodePrefix.hasMatch(out)) {
    out = out.replaceFirst(_machineCodePrefix, '').trim();
  }
  out = out.replaceAll(_machineCodeToken, ' ');
  out = out.replaceFirst(
    RegExp(r'^Permission denied[.:]\s*', caseSensitive: false),
    '',
  );
  out = out
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'^[:\-–]+\s*'), '')
      .trim();
  return out;
}

/// Turns API codes, HTTP statuses, and raw exceptions into copy a person can read.
String friendlyError(Object error, [AppLocalizations? loc]) {
  final raw = error is String ? error : error.toString();
  var text = stripMachineErrorCodes(
    raw
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceFirst(RegExp(r'^HttpException:\s*'), '')
        .replaceFirst(RegExp(r'^ClientException:\s*'), '')
        .replaceFirst(RegExp(r'^SocketException:\s*'), '')
        .replaceFirst(RegExp(r'^HandshakeException:\s*'), '')
        .replaceFirst(RegExp(r'^TimeoutException:\s*'), '')
        .replaceFirst(RegExp(r'^FormatException:\s*'), '')
        .trim(),
  );

  final statusFromFailed = RegExp(r'Request failed \((\d+)\)').firstMatch(text);
  if (statusFromFailed != null) {
    return _fromParts(
      statusCode: int.parse(statusFromFailed.group(1)!),
      loc: loc,
    );
  }
  final statusFromDownload =
      RegExp(r'Failed to download file \((\d+)\)').firstMatch(text);
  if (statusFromDownload != null) {
    return loc?.errDownloadFailed ??
        'Could not download the file. Please try again.';
  }

  if (_looksLikeNetwork(text, error)) {
    return loc?.errNetwork ??
        'Cannot reach the server. Check your connection and try again.';
  }
  if (_looksLikeTimeout(text, error)) {
    return loc?.errTimeout ?? 'That took too long. Please try again.';
  }

  return _fromParts(detail: text, loc: loc);
}

String friendlyHttpError({
  required int statusCode,
  String? detail,
  String? code,
  AppLocalizations? loc,
}) {
  return _fromParts(
    statusCode: statusCode,
    detail: detail == null ? null : stripMachineErrorCodes(detail),
    code: code,
    loc: loc,
  );
}

String _fromParts({
  int? statusCode,
  String? detail,
  String? code,
  AppLocalizations? loc,
}) {
  final mappedCode = _mapCode(code, loc);
  final rewritten = _rewriteDetail((detail ?? '').trim(), loc);
  if (rewritten != null && rewritten.isNotEmpty) return rewritten;
  if (mappedCode != null) return mappedCode;
  return _mapStatus(statusCode, loc);
}

String? _rewriteDetail(String text, AppLocalizations? loc) {
  text = stripMachineErrorCodes(text);
  if (text.isEmpty) return null;
  if (_looksLikeCode(text)) return null;

  final lower = text.toLowerCase();

  if (_looksLikeNetwork(text, text)) {
    return loc?.errNetwork ??
        'Cannot reach the server. Check your connection and try again.';
  }
  if (_looksLikeTimeout(text, text)) {
    return loc?.errTimeout ?? 'That took too long. Please try again.';
  }

  if (lower.contains('incorrect email or password') ||
      lower.contains('invalid login') ||
      lower == 'invalid credentials') {
    return loc?.errBadCredentials ??
        'Email or password is incorrect. Please try again.';
  }
  if (lower.contains('could not validate credentials') ||
      lower.contains('not authenticated') ||
      lower.contains('invalid or expired token') ||
      lower.contains('jwt expired') ||
      lower.contains('session expired')) {
    return loc?.errSessionExpired ??
        'Your session expired. Please sign in again.';
  }
  if (lower == 'permission denied' ||
      lower == 'forbidden' ||
      lower == 'not allowed' ||
      lower == 'dentist access required' ||
      lower == 'admin access required' ||
      lower.contains('clinic, dentist, or lab access')) {
    return loc?.errNoPermission ??
        'You do not have permission to do this.';
  }
  if (lower.contains('already exists')) {
    return text;
  }
  if (lower.contains('pending') && lower.contains('verif')) {
    return text;
  }

  if (lower.contains('field required') ||
      lower.contains('input should be') ||
      lower.contains('value is not a valid') ||
      lower.contains('string should have at least')) {
    return loc?.errValidation ??
        'Please check the information you entered and try again.';
  }

  if (RegExp(r'^https?://').hasMatch(text) ||
      lower.startsWith('sql') ||
      lower.contains('traceback') ||
      lower.contains('postgrest') ||
      lower.contains('pgrst')) {
    return loc?.errGeneric ?? 'Something went wrong. Please try again.';
  }

  var cleaned = stripMachineErrorCodes(
    text.replaceAll(RegExp(r'\(\s*\d{3}\s*\)'), ' '),
  );
  if (cleaned.isEmpty || _looksLikeCode(cleaned)) return null;
  return cleaned;
}

String? _mapCode(String? code, AppLocalizations? loc) {
  final c = (code ?? '').trim().toUpperCase();
  if (c.isEmpty) return null;
  if (c.contains('UNAUTHORIZED') || c == 'HTTP_401') {
    return loc?.errSessionExpired ??
        'Your session expired. Please sign in again.';
  }
  if (c.contains('FORBIDDEN') || c == 'HTTP_403') {
    return loc?.errNoPermission ??
        'You do not have permission to do this.';
  }
  if (c.contains('NOT_FOUND') || c == 'HTTP_404') {
    return loc?.errNotFound ?? 'We could not find that. It may have been removed.';
  }
  if (c.contains('VALIDATION') || c == 'HTTP_422' || c.contains('UNPROCESSABLE')) {
    return loc?.errValidation ??
        'Please check the information you entered and try again.';
  }
  if (c.contains('TOO_MANY') || c == 'HTTP_429') {
    return loc?.errTooMany ?? 'Too many attempts. Please wait a moment and try again.';
  }
  if (c.startsWith('HTTP_5') ||
      c.contains('INTERNAL') ||
      c.contains('BAD_GATEWAY') ||
      c.contains('UNAVAILABLE')) {
    return loc?.errServer ??
        'Something went wrong on our side. Please try again.';
  }
  if (_looksLikeCode(c)) return null;
  return null;
}

String _mapStatus(int? statusCode, AppLocalizations? loc) {
  switch (statusCode) {
    case 401:
      return loc?.errSessionExpired ??
          'Your session expired. Please sign in again.';
    case 403:
      return loc?.errNoPermission ??
          'You do not have permission to do this.';
    case 404:
      return loc?.errNotFound ??
          'We could not find that. It may have been removed.';
    case 409:
      return loc?.errConflict ??
          'That change conflicts with existing data. Please refresh and try again.';
    case 422:
      return loc?.errValidation ??
          'Please check the information you entered and try again.';
    case 429:
      return loc?.errTooMany ??
          'Too many attempts. Please wait a moment and try again.';
    case 500:
    case 502:
    case 503:
    case 504:
      return loc?.errServer ??
          'Something went wrong on our side. Please try again.';
    default:
      return loc?.errGeneric ?? 'Something went wrong. Please try again.';
  }
}

bool _looksLikeCode(String text) {
  final t = text.trim();
  if (t.isEmpty) return true;
  if (RegExp(r'^\d{3}$').hasMatch(t)) return true;
  if (RegExp(r'^(ERR|ERROR|HTTP)[_-][A-Z0-9_]+$').hasMatch(t)) return true;
  if (RegExp(r'^HTTP_\d{3}$').hasMatch(t)) return true;
  if (RegExp(r'^[A-Z][A-Z0-9_]{3,}$').hasMatch(t)) return true;
  return false;
}

bool _looksLikeNetwork(String text, Object error) {
  final type = error.runtimeType.toString();
  if (type.contains('Socket') ||
      type.contains('ClientException') ||
      type.contains('Handshake') ||
      type.contains('OSError')) {
    return true;
  }
  final lower = text.toLowerCase();
  return lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('network is unreachable') ||
      lower.contains('xmlhttprequest') ||
      lower.contains('failed to fetch') ||
      lower.contains('connection closed') ||
      lower.contains('broken pipe') ||
      lower.contains('no address associated');
}

bool _looksLikeTimeout(String text, Object error) {
  if (error.runtimeType.toString().contains('Timeout')) return true;
  final lower = text.toLowerCase();
  return lower.contains('timeout') || lower.contains('timed out');
}
