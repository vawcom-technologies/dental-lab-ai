import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
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
  String _query = '';
  bool _loading = false;
  bool _loadingDetail = false;
  bool _loadingNotes = false;
  bool _mutating = false;
  String? _error;
  GdprPatient? _selected;

  ApiClient get api => _api;
  String? get currentUserId => _api.userId;
  List<GdprPatient> get patients => List.unmodifiable(_patients);
  List<PatientNote> get notes => List.unmodifiable(_notes);
  String get query => _query;
  bool get loading => _loading;
  bool get loadingDetail => _loadingDetail;
  bool get loadingNotes => _loadingNotes;
  bool get mutating => _mutating;
  String? get error => _error;
  GdprPatient? get selected => _selected;

  int get totalCount => _patients.length;

  List<GdprPatient> get visiblePatients {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return patients;
    return _patients.where((p) {
      final blob = '${p.firstName} ${p.lastName} ${p.phone}'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  int get shownCount => visiblePatients.length;

  bool isOwner(GdprPatient p) => p.isOwnedBy(currentUserId);

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final rows = await _service.listPatients();
      _patients
        ..clear()
        ..addAll(rows);
      if (_selected != null) {
        final match = _patients.where((p) => p.id == _selected!.id);
        _selected = match.isEmpty ? null : match.first;
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
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
    notifyListeners();
  }

  Future<GdprPatient> createPatient({
    required String firstName,
    required String lastName,
    required String dateOfBirth,
    required String address,
    required String phone,
    required String healthInsurance,
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
        address: address,
        phone: phone,
        healthInsurance: healthInsurance,
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
      }
    } finally {
      _mutating = false;
      notifyListeners();
    }
  }

  Future<void> grantAccess({
    required String patientId,
    required String targetUserId,
  }) async {
    if (_mutating) return;
    _mutating = true;
    notifyListeners();
    try {
      await _service.grantAccess(
        patientId: patientId,
        targetUserId: targetUserId,
      );
    } finally {
      _mutating = false;
      notifyListeners();
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
    } finally {
      _mutating = false;
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
