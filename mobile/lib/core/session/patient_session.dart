import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../api/api_client.dart';

/// Shared patient list + selection for the signed-in shell session.
///
/// Workflow pages read from here instead of re-calling [ApiClient.listPatients]
/// on every visit. Selection is published here; pages apply it when they become
/// active so offstage keep-alive pages do not reload in the background.
class PatientSession extends ChangeNotifier {
  PatientSession(this.api);

  final ApiClient api;

  List<Map<String, dynamic>> _patients = const [];
  Map<String, dynamic>? _selected;
  bool _loading = false;
  bool _loaded = false;
  Future<void>? _inFlight;
  bool _notifyScheduled = false;

  /// Chairside visit window for the currently selected patient (UTC).
  String? _visitPatientId;
  DateTime? _visitStartedAt;

  /// Camera → Shade: open this detection and run the same AI suggest path.
  String? _pendingShadeDetectionId;
  bool _navigateToShade = false;
  bool _navigateToNewPatient = false;

  List<Map<String, dynamic>> get patients => _patients;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;
  bool get isLoaded => _loaded;

  /// When the current patient's chairside visit began (for visit-scoped media).
  DateTime? get visitStartedAt {
    final sel = _selected;
    if (sel == null || _visitPatientId == null) return null;
    if (pidOf(sel) != _visitPatientId) return null;
    return _visitStartedAt;
  }

  String? get pendingShadeDetectionId => _pendingShadeDetectionId;

  String pidOf(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  void _beginVisitFor(String patientId) {
    if (patientId.isEmpty) return;
    _visitPatientId = patientId;
    _visitStartedAt = DateTime.now().toUtc();
  }

  /// After copying a camera photo into shade_detections, hand off to Shade.
  void requestShadeHandoff(String shadeDetectionId) {
    final id = shadeDetectionId.trim();
    if (id.isEmpty) return;
    _pendingShadeDetectionId = id;
    _navigateToShade = true;
    _notify();
  }

  /// Returns and clears the pending shade detection id (one-shot).
  String? takePendingShadeDetectionId() {
    final id = _pendingShadeDetectionId;
    _pendingShadeDetectionId = null;
    return id;
  }

  /// Shell consumes this to switch to the Shade tab (one-shot).
  bool consumeNavigateToShade() {
    if (!_navigateToShade) return false;
    _navigateToShade = false;
    return true;
  }

  /// Open the full New Patient form from any workflow picker.
  void requestNavigateToNewPatient() {
    _navigateToNewPatient = true;
    _notify();
  }

  /// Shell consumes this to switch to New Patient (one-shot).
  bool consumeNavigateToNewPatient() {
    if (!_navigateToNewPatient) return false;
    _navigateToNewPatient = false;
    return true;
  }

  /// Avoid "notifyListeners during build" when refresh is kicked off from
  /// [State.initState] / dialog mount (common on Appointments modal open).
  void _notify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;
    if (!duringBuild) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      notifyListeners();
    });
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await refresh();
  }

  Future<void> refresh({bool keepSelection = true}) async {
    final existing = _inFlight;
    if (existing != null) {
      await existing;
      return;
    }
    final future = _doRefresh(keepSelection: keepSelection);
    _inFlight = future;
    try {
      await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  Future<void> _doRefresh({required bool keepSelection}) async {
    _loading = true;
    _notify();
    try {
      final rows = await api.listPatients();
      _patients = rows;
      _loaded = true;
      if (rows.isEmpty) {
        _selected = null;
        _visitPatientId = null;
        _visitStartedAt = null;
      } else if (!keepSelection || _selected == null) {
        _selected = rows.first;
        _beginVisitFor(pidOf(_selected!));
      } else {
        final id = pidOf(_selected!);
        final match = rows.where((p) => pidOf(p) == id);
        _selected = match.isEmpty ? rows.first : match.first;
        if (match.isEmpty) {
          _beginVisitFor(pidOf(_selected!));
        } else if (_visitPatientId != id || _visitStartedAt == null) {
          _beginVisitFor(id);
        }
      }
    } finally {
      _loading = false;
      _notify();
    }
  }

  void select(Map<String, dynamic> patient) {
    final nextId = pidOf(patient);
    if (nextId.isEmpty) return;
    if (_selected != null && pidOf(_selected!) == nextId) {
      _selected = patient;
      return;
    }
    _selected = patient;
    _beginVisitFor(nextId);
    _notify();
  }

  void clearSelection() {
    if (_selected == null) return;
    _selected = null;
    _visitPatientId = null;
    _visitStartedAt = null;
    _notify();
  }

  Future<Map<String, dynamic>> createPatient({
    required String firstName,
    required String lastName,
    Map<String, dynamic>? extra,
  }) async {
    final body = <String, dynamic>{
      'first_name': firstName,
      'last_name': lastName,
      ...?extra,
    };
    final created = await api.createPatient(body);
    await refresh(keepSelection: true);
    final id = pidOf(created);
    final match = _patients.where((p) => pidOf(p) == id);
    final row = match.isEmpty ? created : match.first;
    select(row);
    return row;
  }

  /// After the full New Patient form creates a row, sync list + selection.
  Future<void> adoptCreatedPatient(Map<String, dynamic> created) async {
    await refresh(keepSelection: true);
    final id = pidOf(created);
    if (id.isEmpty) return;
    final match = _patients.where((p) => pidOf(p) == id);
    select(match.isEmpty ? created : match.first);
  }
}
