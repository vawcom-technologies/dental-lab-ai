import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class ShadePage extends StatefulWidget {
  const ShadePage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ShadePage> createState() => _ShadePageState();
}

class _ShadePageState extends State<ShadePage> {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;

  String _selected = '—';
  String _detected = '—';
  double _confidence = 0.0;
  String? _note;
  String? _finalShade;
  bool _busy = false;
  bool _saving = false;
  bool _loading = true;
  String? _saveStatus;
  String? _error;
  Uint8List? _previewBytes;
  List<Map<String, dynamic>> _topMatches = [];
  final List<Map<String, dynamic>> _history = [];

  final _vita = const [
    'A1', 'A2', 'A3', 'A3.5', 'A4',
    'B1', 'B2', 'B3', 'B4',
    'C1', 'C2', 'C3', 'C4',
    'D2', 'D3', 'D4',
  ];

  Color _swatch(String shade) {
    const map = {
      'A1': Color(0xFFF2E0C9),
      'A2': Color(0xFFECD2B4),
      'A3': Color(0xFFE2C09C),
      'A3.5': Color(0xFFD6B08A),
      'A4': Color(0xFFC69E7A),
      'B1': Color(0xFFF4E6D2),
      'B2': Color(0xFFECD8BC),
      'B3': Color(0xFFE0C4A0),
      'B4': Color(0xFFD2B28C),
      'C1': Color(0xFFE6D6C4),
      'C2': Color(0xFFD6C2AC),
      'C3': Color(0xFFC4AE96),
      'C4': Color(0xFFB09A84),
      'D2': Color(0xFFE4D0BA),
      'D3': Color(0xFFD2BAA0),
      'D4': Color(0xFFC4AC92),
    };
    return map[shade] ?? AppColors.border;
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final patients = await widget.api.listPatients();
      setState(() => _patients = patients);
      if (patients.isNotEmpty) await _selectPatient(patients.first);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectPatient(Map<String, dynamic> patient) async {
    setState(() {
      _patient = patient;
      _saveStatus = null;
    });
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => c['patient_id'] == patient['id']).toList();
    final caseRow = mine.isEmpty
        ? await widget.api.createCase(patient['id'] as int)
        : mine.first;
    setState(() => _case = caseRow);
  }

  Future<void> _runAiFromGallery() async {
    setState(() {
      _busy = true;
      _error = null;
      _saveStatus = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() => _error = 'Could not read image bytes. Try another photo.');
        return;
      }

      final name = file.name.isNotEmpty ? file.name : 'tooth.jpg';
      setState(() => _previewBytes = Uint8List.fromList(bytes));

      final result = await widget.api.suggestShade(bytes, name);
      final suggested = result['suggested_shade'] as String? ?? 'A2';
      final top = (result['top_matches'] as List?)
              ?.whereType<Map>()
              .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
              .cast<Map<String, dynamic>>()
              .toList() ??
          <Map<String, dynamic>>[];

      setState(() {
        _detected = suggested;
        _selected = suggested;
        _confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
        _note = result['note'] as String? ?? 'Shade detected from uploaded photo.';
        _topMatches = top;
        _finalShade = null;
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist({required bool acceptAi}) async {
    if (_case == null) {
      setState(() => _error = 'Select a patient first');
      return;
    }
    if (_detected == '—' && acceptAi) {
      setState(() => _error = 'Upload a tooth photo first so AI can detect a shade.');
      return;
    }
    final finalShade = acceptAi ? _detected : _selected;
    if (finalShade == '—' || !_vita.contains(finalShade)) {
      setState(() => _error = 'Pick a VITA shade before saving.');
      return;
    }
    final overridden = !acceptAi && finalShade != _detected;
    setState(() {
      _saving = true;
      _saveStatus = null;
      _error = null;
    });
    try {
      await widget.api.saveShade(
        caseId: _case!['id'] as int,
        aiSuggested: _detected == '—' ? null : _detected,
        confidence: _confidence > 0 ? _confidence : null,
        finalShade: finalShade,
        overridden: overridden,
      );
      setState(() {
        _finalShade = finalShade;
        _selected = finalShade;
        _saveStatus = overridden
            ? 'Saved override $finalShade on case #${_case!['id']}'
            : 'Accepted AI $finalShade on case #${_case!['id']}';
        _history.insert(0, {
          'name':
              '${_patient?['first_name'] ?? ''} ${_patient?['last_name'] ?? ''}'.trim(),
          'shade': finalShade,
          'conf': _confidence,
          'override': overridden,
        });
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shade Detection',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'Upload a tooth photo → AI detects VITA shade → confirm or override',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_patients.isNotEmpty)
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<int>(
                    initialValue: _patient?['id'] as int?,
                    decoration: const InputDecoration(isDense: true),
                    items: _patients
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as int,
                            child: Text('${p['first_name']} ${p['last_name']}'),
                          ),
                        )
                        .toList(),
                    onChanged: (id) {
                      final p = _patients.firstWhere((e) => e['id'] == id);
                      _selectPatient(p);
                    },
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _runAiFromGallery,
                icon: Icon(_busy ? Icons.hourglass_top : Icons.upload_file, size: 18),
                label: Text(_busy ? 'Detecting…' : 'Upload & detect'),
              ),
            ],
          ),
          if (_saveStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _saveStatus!,
                style: const TextStyle(color: AppColors.success),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: SectionCard(
                                padding: EdgeInsets.zero,
                                child: ClipRRect(
                                  borderRadius: AppRadii.border,
                                  child: Container(
                                    color: const Color(0xFF15263F),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        if (_previewBytes != null)
                                          Image.memory(
                                            _previewBytes!,
                                            fit: BoxFit.contain,
                                          )
                                        else
                                          const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.add_photo_alternate_outlined,
                                                  color: Colors.white54,
                                                  size: 44,
                                                ),
                                                SizedBox(height: 10),
                                                Text(
                                                  'Upload a close-up tooth / smile photo',
                                                  style: TextStyle(color: Colors.white70),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (_busy)
                                          Container(
                                            color: Colors.black45,
                                            child: const Center(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(
                                                    color: Colors.white,
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Analyzing shade…',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        if (_detected != '—' && !_busy)
                                          Positioned(
                                            left: 12,
                                            top: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.navy,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'AI: $_detected · ${(_confidence * 100).round()}%',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        Positioned(
                                          left: 12,
                                          right: 12,
                                          bottom: 12,
                                          child: FilledButton.icon(
                                            onPressed:
                                                _busy ? null : _runAiFromGallery,
                                            icon: const Icon(
                                              Icons.upload_file,
                                              size: 18,
                                            ),
                                            label: Text(
                                              _previewBytes == null
                                                  ? 'Upload tooth photo'
                                                  : 'Upload another',
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.dentalBlue,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 3,
                              child: SectionCard(
                                padding: const EdgeInsets.all(14),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            const Text(
                                              'Result',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: AppColors.aiPurpleSoft,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: AppColors.aiPurple.withValues(alpha: 0.35),
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 52,
                                                    height: 52,
                                                    decoration: BoxDecoration(
                                                      color: _detected == '—'
                                                          ? AppColors.border
                                                          : _swatch(_detected),
                                                      borderRadius: BorderRadius.circular(10),
                                                      border: Border.all(color: AppColors.border),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          _detected == '—' ? 'No detection yet' : _detected,
                                                          style: const TextStyle(
                                                            fontSize: 28,
                                                            fontWeight: FontWeight.w800,
                                                            color: AppColors.navy,
                                                            height: 1.1,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          _confidence > 0
                                                              ? '${(_confidence * 100).round()}% confidence'
                                                              : 'Upload a photo to analyze',
                                                          style: const TextStyle(
                                                            fontSize: 12,
                                                            color: AppColors.muted,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(6),
                                              child: LinearProgressIndicator(
                                                value: _confidence.clamp(0, 1),
                                                minHeight: 6,
                                                backgroundColor: AppColors.border,
                                                color: AppColors.aiPurple,
                                              ),
                                            ),
                                            if (_selected != '—' && _selected != _detected) ...[
                                              const SizedBox(height: 10),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: AppColors.warningSoft,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  'Override selected: $_selected',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.warning,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (_finalShade != null) ...[
                                              const SizedBox(height: 8),
                                              Text(
                                                'Saved final: $_finalShade',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ],
                                            if (_topMatches.isNotEmpty) ...[
                                              const SizedBox(height: 12),
                                              const Text(
                                                'Top matches',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.muted,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 6,
                                                children: _topMatches.take(5).map((m) {
                                                  final s = m['shade']?.toString() ?? '';
                                                  final active = _selected == s;
                                                  return InkWell(
                                                    onTap: () => setState(() {
                                                      _selected = s;
                                                      _saveStatus = null;
                                                    }),
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                      decoration: BoxDecoration(
                                                        color: _swatch(s).withValues(alpha: 0.45),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(
                                                          color: active ? AppColors.navy : AppColors.border,
                                                          width: active ? 1.5 : 1,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        s,
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                            const SizedBox(height: 14),
                                            FilledButton(
                                              onPressed: _saving || _detected == '—'
                                                  ? null
                                                  : () => _persist(acceptAi: true),
                                              style: FilledButton.styleFrom(
                                                backgroundColor: AppColors.navy,
                                                minimumSize: const Size.fromHeight(40),
                                              ),
                                              child: Text(
                                                _saving
                                                    ? 'Saving…'
                                                    : (_detected == '—' ? 'Accept AI' : 'Accept $_detected'),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            OutlinedButton(
                                              onPressed: _saving ? null : () => _persist(acceptAi: false),
                                              style: OutlinedButton.styleFrom(
                                                minimumSize: const Size.fromHeight(40),
                                              ),
                                              child: Text(
                                                _selected == '—' || _selected == _detected
                                                    ? 'Save override'
                                                    : 'Save override ($_selected)',
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              _note ??
                                                  'Natural light, close-up tooth photos work best. Confirm or override below.',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                height: 1.35,
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Manual Override — VITA Classical',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/clinical/vita-classical-a1-d4.png',
                                height: 90,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _vita.map((s) {
                                final selected = _selected == s;
                                return InkWell(
                                  onTap: () => setState(() {
                                    _selected = s;
                                    _saveStatus = null;
                                  }),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    width: 48,
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected ? AppColors.navy : AppColors.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: _swatch(s),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          s,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 200,
                  child: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Session', style: TextStyle(fontWeight: FontWeight.w700)),
                        const Text(
                          'Saves this visit',
                          style: TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _history.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No saves yet',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _history.length,
                                  itemBuilder: (context, i) {
                                    final h = _history[i];
                                    return _Recent(
                                      name: h['name'] as String? ?? 'Patient',
                                      shade: h['shade'] as String,
                                      conf: (h['conf'] as num?)?.toDouble() ?? 0,
                                      color: _swatch(h['shade'] as String),
                                      isOverride: h['override'] == true,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({
    required this.name,
    required this.shade,
    required this.conf,
    required this.color,
    this.isOverride = false,
  });

  final String name;
  final String shade;
  final double conf;
  final Color color;
  final bool isOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(shade, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (isOverride) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warningSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'OVERRIDE',
                style: TextStyle(
                  color: AppColors.warning,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: conf.clamp(0, 1),
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: AppColors.aiPurple,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            conf > 0 ? '${(conf * 100).round()}% confidence' : 'Manual selection',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
