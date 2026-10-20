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
        readyToSubmit = j['ready_to_submit'] == true,
        canSubmit = j['can_submit'] == true,
        canReview = j['can_review'] == true,
        canSuggest = j['can_suggest'] == true,
        isOwner = j['is_owner'] == true,
        updatedSinceRejection = j['updated_since_rejection'] == true,
        feedback = {
          for (final MapEntry(:key, :value) in _map(_map(j['lab_review'])['feedback']).entries)
            if (value is Map) key: CaseItemFeedback({...Map<String, dynamic>.from(value), 'item': key}),
        },
        suggestions = {
          for (final MapEntry(:key, :value) in _map(_map(j['lab_review'])['suggestions']).entries)
            if (value is Map) key: CaseSuggestion(key, Map<String, dynamic>.from(value)),
        },
        owner = j['owner'] is Map ? Map<String, dynamic>.from(j['owner'] as Map) : null,
        rejection = j['last_rejection'] is Map
            ? CaseRejection(Map<String, dynamic>.from(j['last_rejection'] as Map))
            : null,
        events = [
          for (final e in (j['events'] as List? ?? const []))
            if (e is Map) CaseHistoryEvent(Map<String, dynamic>.from(e)),
        ];

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static bool _item(Map<String, dynamic> j, String k) =>
      j['items'] is Map && (j['items'] as Map)[k] == true;

  final String status;
  final bool autoSubmit,
      hasScan,
      hasShade,
      hasSmile,
      sharedWithLab,
      readyToSubmit,
      canSubmit,
      canReview,
      canSuggest,
      isOwner,
      updatedSinceRejection;

  /// Lab's draft verdicts while reviewing, by item (lab / admin only).
  final Map<String, CaseItemFeedback> feedback;

  /// Changes the lab proposed, by item; the owning dentist accepts or dismisses.
  final Map<String, CaseSuggestion> suggestions;
  final List<String> missing;
  final String? labName;
  final CaseRejection? rejection;
  final List<CaseHistoryEvent> events;

  /// The patient's owner: `{id, name, role, clinic_name, lab_name, avatar_url}`.
  final Map<String, dynamic>? owner;

  /// Under review or completed: items can only be replaced, not deleted.
  bool get locked => status == 'in_review' || status == 'completed';
}

class CaseItemFeedback {
  CaseItemFeedback(Map<String, dynamic> j)
      : item = '${j['item'] ?? ''}',
        status = '${j['status'] ?? ''}',
        note = (j['note']?.toString().trim().isEmpty ?? true) ? null : j['note'].toString();

  final String item;
  final String status; // ok | needs_work
  final String? note;

  bool get needsWork => status == 'needs_work';
}

class CaseSuggestion {
  CaseSuggestion(this.item, Map<String, dynamic> j)
      : id = '${j['id'] ?? ''}',
        forId = j['for_id']?.toString(),
        fileName = j['file_name']?.toString(),
        by = j['by']?.toString(),
        at = DateTime.tryParse('${j['at'] ?? ''}')?.toLocal();

  final String item, id;
  final String? forId, fileName, by;
  final DateTime? at;

  /// Backend file path (resolve with ApiClient) — `/api/files/<kind>/<id>`.
  String get fileUrl => '/api/files/${switch (item) { 'scan' => 'scans', 'shade' => 'shades', _ => 'smiles' }}/$id';
}

class CaseRejection {
  CaseRejection(Map<String, dynamic> j)
      : remarks = '${j['remarks'] ?? ''}',
        by = j['by']?.toString(),
        at = DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
        items = [
          for (final e in (j['items'] as List? ?? const []))
            if (e is Map) CaseItemFeedback(Map<String, dynamic>.from(e)),
        ];

  final String remarks;
  final String? by;
  final DateTime? at;
  final List<CaseItemFeedback> items;
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

  Future<void> saveFeedback(String patientId, String item, {String? status, String? note}) async {
    _cases[patientId] = CaseInfo(await _api.saveReviewDraft(patientId, item: item, status: status, note: note));
    notifyListeners();
  }

  Future<void> resolveSuggestion(String patientId, String item, {required bool accept}) async {
    _cases[patientId] = CaseInfo(await _api.resolveSuggestion(patientId, item: item, accept: accept));
    notifyListeners();
  }

  Future<void> review(
    String patientId, {
    required bool approve,
    String? remarks,
    List<Map<String, dynamic>>? items,
  }) async {
    _cases[patientId] = CaseInfo(
      await _api.reviewCase(patientId, approve: approve, remarks: remarks, items: items),
    );
    notifyListeners();
  }
}
