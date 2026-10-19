import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';

/// A patient's case as the server sees it (GET /api/patients/{id}/case).
class CaseInfo {
  CaseInfo(Map<String, dynamic> j)
      : status = '${j['status'] ?? 'pending'}',
        autoSubmit = j['auto_submit'] == true,
        hasScan = _item(j, 'scan'),
        hasShade = _item(j, 'shade'),
        hasSmile = _item(j, 'smile'),
        missing = [for (final m in (j['missing'] as List? ?? const [])) '$m'],
        labName = (j['lab'] is Map) ? '${(j['lab'] as Map)['name'] ?? ''}' : null,
        sharedWithLab = j['shared_with_lab'] == true,
        canSubmit = j['can_submit'] == true,
        canReview = j['can_review'] == true,
        owner = j['owner'] is Map ? Map<String, dynamic>.from(j['owner'] as Map) : null,
        rejection = j['last_rejection'] is Map
            ? CaseRejection(Map<String, dynamic>.from(j['last_rejection'] as Map))
            : null,
        events = [
          for (final e in (j['events'] as List? ?? const []))
            if (e is Map) CaseHistoryEvent(Map<String, dynamic>.from(e)),
        ];

  static bool _item(Map<String, dynamic> j, String k) =>
      j['items'] is Map && (j['items'] as Map)[k] == true;

  final String status;
  final bool autoSubmit, hasScan, hasShade, hasSmile, sharedWithLab, canSubmit, canReview;
  final List<String> missing;
  final String? labName;
  final CaseRejection? rejection;
  final List<CaseHistoryEvent> events;

  /// The patient's owner: `{id, name, role, clinic_name, lab_name, avatar_url}`.
  final Map<String, dynamic>? owner;

  /// Under review or completed: items can only be replaced, not deleted.
  bool get locked => status == 'in_review' || status == 'completed';
}

class CaseRejection {
  CaseRejection(Map<String, dynamic> j)
      : remarks = '${j['remarks'] ?? ''}',
        by = j['by']?.toString(),
        at = DateTime.tryParse('${j['at'] ?? ''}')?.toLocal();

  final String remarks;
  final String? by;
  final DateTime? at;
}

class CaseHistoryEvent {
  CaseHistoryEvent(Map<String, dynamic> j)
      : type = '${j['type'] ?? ''}',
        actor = j['actor_name']?.toString(),
        remarks = (j['remarks']?.toString().trim().isEmpty ?? true) ? null : j['remarks'].toString(),
        fromStatus = j['from_status']?.toString(),
        toStatus = j['to_status']?.toString(),
        at = DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal();

  final String type;
  final String? actor, remarks, fromStatus, toStatus;
  final DateTime? at;
}

/// Case summaries by patient id. Pages read [of] and call [refresh] after any
/// upload / save / delete, because the server may move the status on its own.
class CaseStore extends ChangeNotifier {
  CaseStore(this._api);

  final ApiClient _api;
  final _cases = <String, CaseInfo>{};
  final _errors = <String, Object>{};

  CaseInfo? of(String? patientId) => patientId == null ? null : _cases[patientId];
  Object? errorOf(String patientId) => _errors[patientId];

  Future<CaseInfo?> refresh(String patientId) async {
    try {
      final info = CaseInfo(await _api.patientCase(patientId));
      _cases[patientId] = info;
      _errors.remove(patientId);
      return info;
    } catch (e) {
      _errors[patientId] = e;
      return null;
    } finally {
      notifyListeners();
    }
  }

  /// Throws [CaseIncomplete] when items are missing and not confirmed.
  Future<void> submit(String patientId, {bool confirmIncomplete = false}) async {
    _cases[patientId] = CaseInfo(await _api.submitCase(patientId, confirmIncomplete: confirmIncomplete));
    notifyListeners();
  }

  Future<void> review(String patientId, {required bool approve, String? remarks}) async {
    _cases[patientId] = CaseInfo(await _api.reviewCase(patientId, approve: approve, remarks: remarks));
    notifyListeners();
  }
}
