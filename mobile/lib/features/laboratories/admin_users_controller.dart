import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import 'admin_user.dart';

enum AdminUserFilter { all, unverified, verified }

/// Holds the admin users list, filters, and mutation results.
class AdminUsersController extends ChangeNotifier {
  AdminUsersController(this._api);

  final ApiClient _api;

  final List<AdminUser> _users = [];
  bool _loading = false;
  bool _actionBusy = false;
  String? _error;
  String _query = '';
  AdminUserFilter _filter = AdminUserFilter.all;
  int _skip = 0;
  int _limit = 50;
  int _count = 0;

  List<AdminUser> get users => List.unmodifiable(_users);
  bool get loading => _loading;
  bool get actionBusy => _actionBusy;
  String? get error => _error;
  String get query => _query;
  AdminUserFilter get filter => _filter;
  int get skip => _skip;
  int get limit => _limit;
  int get count => _count;
  int get totalLoaded => _users.length;

  List<AdminUser> get visibleUsers {
    var rows = _users.where((u) => !u.deleted).toList();
    switch (_filter) {
      case AdminUserFilter.all:
        break;
      case AdminUserFilter.unverified:
        rows = rows.where((u) => !u.verified).toList();
        break;
      case AdminUserFilter.verified:
        rows = rows.where((u) => u.verified).toList();
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((u) {
        return u.name.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q) ||
            (u.clinicName?.toLowerCase().contains(q) ?? false) ||
            (u.phone?.toLowerCase().contains(q) ?? false) ||
            u.role.toLowerCase().contains(q);
      }).toList();
    }
    return rows;
  }

  void setQuery(String value) {
    final next = value.trim().toLowerCase();
    if (next == _query) return;
    _query = next;
    notifyListeners();
  }

  void setFilter(AdminUserFilter value) {
    if (value == _filter) return;
    _filter = value;
    notifyListeners();
  }

  Future<void> load({int skip = 0, int limit = 50}) async {
    _loading = true;
    _error = null;
    _skip = skip;
    _limit = limit;
    notifyListeners();
    try {
      final page = await _api.listAdminUsers(skip: skip, limit: limit);
      _users
        ..clear()
        ..addAll(page.items);
      _count = page.count;
      _skip = page.skip;
      _limit = page.limit;
      _error = null;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load(skip: _skip, limit: _limit);

  Future<String> verifyUser(String userId) async {
    _actionBusy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _api.verifyAdminUser(userId);
      if (result.user != null) {
        _upsert(result.user!);
      }
      return result.message;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _error = msg;
      rethrow;
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  Future<String> softDeleteUser(String userId) async {
    _actionBusy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _api.softDeleteAdminUser(userId);
      _users.removeWhere((u) => u.id == userId);
      if (_count > 0) _count -= 1;
      return result.message;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _error = msg;
      rethrow;
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  Future<String> hardDeleteUser(String userId) async {
    _actionBusy = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _api.hardDeleteAdminUser(userId);
      _users.removeWhere((u) => u.id == userId);
      if (_count > 0) _count -= 1;
      return result.message;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _error = msg;
      rethrow;
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  void _upsert(AdminUser user) {
    final i = _users.indexWhere((u) => u.id == user.id);
    if (i >= 0) {
      _users[i] = user;
    } else {
      _users.insert(0, user);
      _count += 1;
    }
  }
}
