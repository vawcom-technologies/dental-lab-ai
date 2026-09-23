import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/settings/app_settings.dart';

/// Live inbox: polls the server, updates the bell, and queues incoming toasts.
class NotificationInboxController extends ChangeNotifier {
  NotificationInboxController(this.api);

  final ApiClient api;

  static const _pollEvery = Duration(seconds: 8);

  Timer? _timer;
  bool _inFlight = false;
  bool _queued = false;
  bool _seeded = false;
  bool _markingAll = false;
  bool _disposed = false;
  final Set<String> _knownIds = {};
  final List<Map<String, dynamic>> _pendingToasts = [];

  List<Map<String, dynamic>> _items = const [];
  int _unreadCount = 0;
  String? _error;
  AppSettings? prefs;
  void Function(String message)? onError;

  List<Map<String, dynamic>> get items => _items;
  int get unreadCount => _unreadCount;
  String? get error => _error;

  Future<void> start() async {
    prefs = await AppSettings.load();
    if (_disposed) return;
    await refresh(announce: false);
    _timer?.cancel();
    _timer = Timer.periodic(_pollEvery, (_) {
      unawaited(refresh());
    });
  }

  /// Pull latest rows. [announce] queues a toast for newly arrived *incoming*
  /// alerts (not "You …" activity from this device).
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> refresh({bool announce = true}) async {
    if (_disposed) return;
    if (_inFlight) {
      _queued = true;
      return;
    }
    _inFlight = true;
    try {
      final rows = await api.listNotifications(forceRefresh: true);
      final fresh = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final id = '${row['id'] ?? ''}'.trim();
        if (id.isEmpty || isMessageType(row)) continue;
        final isNew = _seeded && !_knownIds.contains(id);
        _knownIds.add(id);
        if (isNew && announce && row['read'] != true && _isIncoming(row)) {
          fresh.add(row);
        }
      }
      _seeded = true;
      _items = [
        for (final row in rows)
          if (!isMessageType(row)) Map<String, dynamic>.from(row),
      ];
      _unreadCount = _items.where((n) => n['read'] != true).length;
      _error = null;
      if (fresh.isNotEmpty) {
        _pendingToasts.addAll(fresh);
      }
      _notify();
    } catch (e) {
      if (_disposed) return;
      _error = friendlyError(e);
      onError?.call(_error!);
      _notify();
    } finally {
      _inFlight = false;
      if (!_disposed && _queued) {
        _queued = false;
        unawaited(refresh(announce: announce));
      }
    }
  }

  List<Map<String, dynamic>> takePendingToasts() {
    if (_pendingToasts.isEmpty) return const [];
    final out = List<Map<String, dynamic>>.from(_pendingToasts);
    _pendingToasts.clear();
    return out;
  }

  Future<void> markRead(String id) async {
    if (_disposed) return;
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    await api.markNotificationRead(trimmed);
    if (_disposed) return;
    for (final n in _items) {
      if ('${n['id']}' == trimmed) {
        n['read'] = true;
      }
    }
    _unreadCount = _items.where((n) => n['read'] != true).length;
    _notify();
  }

  Future<void> markAllRead() async {
    if (_markingAll) return;
    if (_unreadCount == 0 && _items.every((n) => n['read'] == true)) return;
    _markingAll = true;
    for (final n in _items) {
      n['read'] = true;
    }
    _unreadCount = 0;
    _notify();
    try {
      await api.markAllNotificationsRead();
    } finally {
      _markingAll = false;
    }
  }

  bool allowedBySettings(String type) {
    if (type == 'message') return false;
    final p = prefs;
    if (p == null) return true;
    if (!p.notificationsEnabled) {
      switch (type) {
        case 'case_status':
        case 'scan_quality':
          return false;
        default:
          return true;
      }
    }
    switch (type) {
      case 'case_status':
        return p.notifyCaseStatus;
      case 'scan_quality':
        return p.notifyScanQuality;
      default:
        return true;
    }
  }

  static bool isMessageType(Map<String, dynamic> row) =>
      '${row['type'] ?? ''}'.trim().toLowerCase() == 'message';

  /// Activity rows written for the actor ("You declined…") stay in the inbox
  /// but should not pop a second toast on this device.
  static bool _isIncoming(Map<String, dynamic> row) {
    final msg = '${row['message'] ?? ''}'.trim();
    return msg.isNotEmpty && !msg.startsWith('You ');
  }

  @override
  void dispose() {
    _disposed = true;
    _queued = false;
    _timer?.cancel();
    super.dispose();
  }
}
