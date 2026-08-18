import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
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
  final Set<String> _knownIds = {};
  final List<Map<String, dynamic>> _pendingToasts = [];

  List<Map<String, dynamic>> _items = const [];
  int _unreadCount = 0;
  String? _error;
  AppSettings? prefs;

  List<Map<String, dynamic>> get items => _items;
  int get unreadCount => _unreadCount;
  String? get error => _error;

  Future<void> start() async {
    prefs = await AppSettings.load();
    await refresh(announce: false);
    _timer?.cancel();
    _timer = Timer.periodic(_pollEvery, (_) {
      unawaited(refresh());
    });
  }

  /// Pull latest rows. [announce] queues a toast for newly arrived *incoming*
  /// alerts (not "You …" activity from this device).
  Future<void> refresh({bool announce = true}) async {
    if (_inFlight) {
      _queued = true;
      return;
    }
    _inFlight = true;
    try {
      final rows = await api.listNotifications();
      final fresh = <Map<String, dynamic>>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final id = '${row['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final isNew = _seeded && !_knownIds.contains(id);
        _knownIds.add(id);
        if (isNew && announce && row['read'] != true && _isIncoming(row)) {
          fresh.add(row);
        }
      }
      _seeded = true;
      _items = [for (final row in rows) Map<String, dynamic>.from(row)];
      _unreadCount = _items.where((n) => n['read'] != true).length;
      _error = null;
      if (fresh.isNotEmpty) {
        _pendingToasts.addAll(fresh);
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    } finally {
      _inFlight = false;
      if (_queued) {
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
    final trimmed = id.trim();
    if (trimmed.isEmpty) return;
    await api.markNotificationRead(trimmed);
    for (final n in _items) {
      if ('${n['id']}' == trimmed) {
        n['read'] = true;
      }
    }
    _unreadCount = _items.where((n) => n['read'] != true).length;
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await api.markAllNotificationsRead();
    for (final n in _items) {
      n['read'] = true;
    }
    _unreadCount = 0;
    notifyListeners();
  }

  bool allowedBySettings(String type) {
    final p = prefs;
    if (p == null) return true;
    if (!p.notificationsEnabled) {
      switch (type) {
        case 'message':
        case 'case_status':
        case 'scan_quality':
          return false;
        default:
          return true;
      }
    }
    switch (type) {
      case 'message':
        return p.notifyMessages;
      case 'case_status':
        return p.notifyCaseStatus;
      case 'scan_quality':
        return p.notifyScanQuality;
      default:
        return true;
    }
  }

  /// Activity rows written for the actor ("You declined…") stay in the inbox
  /// but should not pop a second toast on this device.
  static bool _isIncoming(Map<String, dynamic> row) {
    final msg = '${row['message'] ?? ''}'.trim();
    return msg.isNotEmpty && !msg.startsWith('You ');
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
