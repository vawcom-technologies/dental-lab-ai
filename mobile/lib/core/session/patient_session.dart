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

  List<Map<String, dynamic>> get patients => _patients;
  Map<String, dynamic>? get selected => _selected;
  bool get loading => _loading;
  bool get isLoaded => _loaded;

  String pidOf(Map<String, dynamic> row) => '${row['id'] ?? ''}';

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
      } else if (!keepSelection || _selected == null) {
        _selected = rows.first;
      } else {
        final id = pidOf(_selected!);
        final match = rows.where((p) => pidOf(p) == id);
        _selected = match.isEmpty ? rows.first : match.first;
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
    _notify();
  }

  void clearSelection() {
    if (_selected == null) return;
    _selected = null;
    _notify();
  }

  Future<Map<String, dynamic>> createPatient({
    required String firstName,
    required String lastName,
  }) async {
    final created = await api.createPatient({
      'first_name': firstName,
      'last_name': lastName,
    });
    await refresh(keepSelection: true);
    final id = pidOf(created);
    final match = _patients.where((p) => pidOf(p) == id);
    final row = match.isEmpty ? created : match.first;
    select(row);
    return row;
  }
}
