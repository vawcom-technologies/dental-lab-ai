import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import 'patient_models.dart';
import 'patients_api_service.dart';

/// Client state for the GDPR Patients module.
class PatientsController extends ChangeNotifier {
  PatientsController({
    required ApiClient api,
    PatientsApiService? apiService,
  })  : _api = api,
        _service = apiService ?? PatientsApiService(api);

  final ApiClient _api;
  final PatientsApiService _service;

  final List<GdprPatient> _patients = [];
  final List<PatientNote> _notes = [];
  final List<PendingAccessRequest> _pendingRequests = [];
  final List<PatientAccessEntry> _accessEntries = [];
  PatientAccessOwner? _accessOwner;
  bool _accessViewerIsOwner = false;
  VoidCallback? onAccessMutated;
  String _query = '';
  String _statusFilter = 'all';
  bool _loading = false;
  bool _loadingDetail = false;
  bool _loadingNotes = false;
  bool _loadingPending = false;
  bool _loadingAccess = false;
  bool _mutating = false;
  String? _error;
  GdprPatient? _selected;

  ApiClient get api => _api;
  String? get currentUserId => _api.userId;
  List<GdprPatient> get patients => List.unmodifiable(_patients);
  List<PatientNote> get notes => List.unmodifiable(_notes);
  List<PendingAccessRequest> get pendingRequests =>
      List.unmodifiable(_pendingRequests);
  List<PatientAccessEntry> get accessEntries =>
      List.unmodifiable(_accessEntries);
  PatientAccessOwner? get accessOwner => _accessOwner;
  bool get accessViewerIsOwner => _accessViewerIsOwner;
  String get query => _query;
  String get statusFilter => _statusFilter;
  bool get loading => _loading;
  bool get loadingDetail => _loadingDetail;
  bool get loadingNotes => _loadingNotes;
  bool get loadingPending => _loadingPending;
  bool get loadingAccess => _loadingAccess;
  bool get mutating => _mutating;
  String? get error => _error;
  GdprPatient? get selected => _selected;
  int get pendingCount => _pendingRequests.length;

  int get totalCount => _patients.length;

  List<GdprPatient> get visiblePatients {
    final q = _query.trim().toLowerCase();
    return _patients.where((p) {
      if (!CaseStatuses.matchesFilter(p.status, _statusFilter)) return false;
      if (q.isEmpty) return true;
      final blob =
          '${p.firstName} ${p.lastName} ${p.email} ${p.phone}'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  int get shownCount => visiblePatients.length;

  bool isOwner(GdprPatient p) => p.isOwnedBy(currentUserId);

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  void setStatusFilter(String value) {
    final next = value.trim().isEmpty ? 'all' : value.trim().toLowerCase();
    if (next == _statusFilter) return;
    _statusFilter = next;
    notifyListeners();
  }

  Future<void> load({bool forceRefresh = false}) async {
    if (_loading) return;
    final showLoader = _patients.isEmpty || forceRefresh;
    if (showLoader) {
      _loading = true;
      _error = null;
      notifyListeners();
    }
    try {
      final rows = await _service.listPatients(forceRefresh: forceRefresh);
      _patients
        ..clear()
        ..addAll(rows);
      if (_selected != null) {
        final match = _patients.where((p) => p.id == _selected!.id);
        _selected = match.isEmpty ? null : match.first;
      }
      await loadPendingRequests(silent: true);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadPendingRequests({bool silent = false}) async {
    if (_loadingPending) return;
    if (!silent) {
      _loadingPending = true;
      notifyListeners();
    }
    try {
      final rows = await _service.listPendingAccessRequests();
      _pendingRequests
        ..clear()
        ..addAll(rows);
    } catch (_) {
      // Pending badge is primarily for owners; ignore soft failures on refresh.
      if (!silent) rethrow;
    } finally {
      if (!silent) _loadingPending = false;
      notifyListeners();
    }
  }

  Future<GdprPatient?> openPatient(String patientId) async {
    if (_loadingDetail) return null;
    _loadingDetail = true;
    _error = null;
    notifyListeners();
    try {
      final patient = await _service.getPatient(patientId);
      _selected = patient;
      final i = _patients.indexWhere((p) => p.id == patient.id);
      if (i >= 0) {
        _patients[i] = patient;
      }
      await loadAccess(patientId, silent: true);
      return patient;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      rethrow;
    } finally {
      _loadingDetail = false;
      notifyListeners();
    }
  }

  void clearSelected() {
    _selected = null;
    _notes.clear();
    _accessEntries.clear();
    _accessOwner = null;
    _accessViewerIsOwner = false;
    notifyListeners();
  }

  Future<GdprPatient> createPatient({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String email,
    required String address,
    required String phone,
    required String healthInsurance,
    String status = 'pending',
  }) async {
    if (_mutating) {
      throw StateError('Another patient change is already in progress');
    }
    _mutating = true;
    notifyListeners();
    try {
      final created = await _service.createPatient(
        firstName: firstName,
        lastName: lastName,
        dateOfBirth: dateOfBirth,
        email: email,
        address: address,
        phone: phone,
        healthInsurance: healthInsurance,
        status: status,
      );
      _patients.insert(0, created);
      return created;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<GdprPatient> updatePatient(
    String patientId,
    Map<String, dynamic> fields,
  ) async {
    if (_mutating) {
      throw StateError('Another patient change is already in progress');
    }
    _mutating = true;
    notifyListeners();
    try {
      final updated = await _service.updatePatient(patientId, fields);
      final i = _patients.indexWhere((p) => p.id == patientId);
      if (i >= 0) _patients[i] = updated;
      if (_selected?.id == patientId) _selected = updated;
      return updated;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<void> deletePatient(String patientId, {required bool hard}) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.deletePatient(patientId, hard: hard);
      _patients.removeWhere((p) => p.id == patientId);
      if (_selected?.id == patientId) {
        _selected = null;
        _notes.clear();
        _accessEntries.clear();
        _accessOwner = null;
        _accessViewerIsOwner = false;
      }
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<AccessMutationResult> shareAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    if (_mutating) {
      throw StateError('Another patient change is already in progress');
    }
    GdprPatient? patient;
    for (final p in _patients) {
      if (p.id == patientId) {
        patient = p;
        break;
      }
    }
    patient ??= _selected?.id == patientId ? _selected : null;
    final asOwner = patient != null && isOwner(patient);
    _mutating = true;
    notifyListeners();
    try {
      final result = await _service.grantOrRequestAccess(
        patientId: patientId,
        targetUserId: targetUserId,
        asOwner: asOwner,
      );
      if (_selected?.id == patientId) {
        await loadAccess(patientId, silent: true);
      }
      return result;
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<void> revokeAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.revokeAccess(
        patientId: patientId,
        targetUserId: targetUserId,
      );
      _accessEntries.removeWhere((e) => e.userId == targetUserId);
      if (_selected?.id == patientId) {
        await loadAccess(patientId, silent: true);
      }
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<void> approveAccessRequest(String requestId) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.resolveAccessRequest(
        requestId: requestId,
        action: 'approve',
      );
      _pendingRequests.removeWhere((r) => r.id == requestId);
      // Refresh roster so newly approved staff visibility stays consistent.
      final rows = await _service.listPatients();
      _patients
        ..clear()
        ..addAll(rows);
      await loadPendingRequests(silent: true);
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<void> rejectAccessRequest(String requestId) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.resolveAccessRequest(
        requestId: requestId,
        action: 'reject',
      );
      _pendingRequests.removeWhere((r) => r.id == requestId);
      await loadPendingRequests(silent: true);
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<void> approveAccessEntry(PatientAccessEntry entry) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.resolveAccessRequest(
        requestId: entry.id,
        action: 'approve',
      );
      await loadPendingRequests(silent: true);
      if (_selected != null) {
        await loadAccess(_selected!.id, silent: true);
      }
      final rows = await _service.listPatients();
      _patients
        ..clear()
        ..addAll(rows);
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<void> rejectAccessEntry(PatientAccessEntry entry) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.resolveAccessRequest(
        requestId: entry.id,
        action: 'reject',
      );
      await loadPendingRequests(silent: true);
      if (_selected != null) {
        await loadAccess(_selected!.id, silent: true);
      }
    } finally {
      _mutating = false;
      notifyListeners();
      onAccessMutated?.call();
    }
  }

  Future<List<EligibleAccessUser>> listEligibleUsers(String patientId) {
    return _service.listEligibleUsers(patientId);
  }

  Future<void> loadAccess(String patientId, {bool silent = false}) async {
    if (_loadingAccess) return;
    if (!silent) {
      _loadingAccess = true;
      notifyListeners();
    }
    try {
      final snapshot = await _service.listPatientAccess(patientId);
      _accessOwner = snapshot.owner;
      _accessViewerIsOwner = snapshot.isOwner;
      _accessEntries
        ..clear()
        ..addAll(snapshot.isOwner ? snapshot.accessList : const []);
    } finally {
      if (!silent) _loadingAccess = false;
      notifyListeners();
    }
  }

  Future<void> loadNotes(String patientId) async {
    if (_loadingNotes) return;
    _loadingNotes = true;
    notifyListeners();
    try {
      final rows = await _service.listNotes(patientId);
      _notes
        ..clear()
        ..addAll(rows);
    } finally {
      _loadingNotes = false;
      notifyListeners();
    }
  }

  Future<PatientNote> addNote({
    required String patientId,
    required String content,
  }) async {
    if (_mutating) {
      throw StateError('Another patient change is already in progress');
    }
    _mutating = true;
    notifyListeners();
    try {
      final note = await _service.uploadNote(
        patientId: patientId,
        noteContent: content,
      );
      _notes.insert(0, note);
      return note;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<PatientNote> editNote({
    required String noteId,
    required String content,
  }) async {
    if (_mutating) {
      throw StateError('Another patient change is already in progress');
    }
    _mutating = true;
    notifyListeners();
    try {
      final note = await _service.editNote(
        noteId: noteId,
        newNoteContent: content,
      );
      final i = _notes.indexWhere((n) => n.id == noteId);
      if (i >= 0) _notes[i] = note;
      return note;
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<void> deleteNote(String noteId) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.deleteNote(noteId);
      _notes.removeWhere((n) => n.id == noteId);
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }
}
