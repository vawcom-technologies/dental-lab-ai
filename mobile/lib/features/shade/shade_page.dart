import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  String _selected = 'B2';
  String _detected = 'B2';
  double _confidence = 0.0;
  String? _note;
  String? _finalShade;
  bool _busy = false;
  bool _saving = false;
  bool _loading = true;
  String? _saveStatus;
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
      setState(() => _note = e.toString().replaceFirst('Exception: ', ''));
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
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final result = await widget.api.suggestShade(bytes, file.name);
      setState(() {
        _detected = result['suggested_shade'] as String? ?? _detected;
        _selected = _detected;
        _confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
        _note = result['note'] as String?;
        _finalShade = null;
        _saveStatus = null;
      });
    } catch (e) {
      setState(() => _note = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _persist({required bool acceptAi}) async {
    if (_case == null) {
      setState(() => _note = 'Select a patient first');
      return;
    }
    final finalShade = acceptAi ? _detected : _selected;
    final overridden = !acceptAi && finalShade != _detected;
    setState(() {
      _saving = true;
      _saveStatus = null;
    });
    try {
      await widget.api.saveShade(
        caseId: _case!['id'] as int,
        aiSuggested: _detected,
        confidence: _confidence > 0 ? _confidence : null,
        finalShade: finalShade,
        overridden: overridden || (!acceptAi && finalShade != _detected),
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
      setState(() => _note = e.toString().replaceFirst('Exception: ', ''));
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
                      'AI suggestion · manual override · persisted on case',
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
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF15263F),
                                    borderRadius: AppRadii.border,
                                  ),
                                  child: Stack(
                                    children: [
                                      const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.photo_camera_outlined,
                                                color: Colors.white54, size: 40),
                                            SizedBox(height: 8),
                                            Text('Tooth photo analysis',
                                                style: TextStyle(color: Colors.white70)),
                                          ],
                                        ),
                                      ),
                                      Positioned(
                                        left: 16,
                                        right: 16,
                                        bottom: 12,
                                        child: Row(
                                          children: [
                                            const Text(
                                              'VITA Classical A1–D4',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const Spacer(),
                                            TextButton(
                                              onPressed: _busy ? null : _runAiFromGallery,
                                              child: Text(
                                                _busy ? 'ANALYZING…' : 'AUTO CAPTURE',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: SectionCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('AI Detected',
                                        style: TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        _ShadeBlock(
                                          label: 'DETECTED',
                                          shade: _detected,
                                          color: _swatch(_detected),
                                          highlight: true,
                                          sub: _confidence > 0
                                              ? '${(_confidence * 100).round()}%'
                                              : '—',
                                        ),
                                        _ShadeBlock(
                                          label: 'SELECTED',
                                          shade: _selected,
                                          color: _swatch(_selected),
                                        ),
                                        _ShadeBlock(
                                          label: 'FINAL',
                                          shade: _finalShade ?? '—',
                                          color: _finalShade == null
                                              ? AppColors.border
                                              : _swatch(_finalShade!),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _confidence > 0
                                          ? 'Confidence ${(_confidence * 100).round()}%'
                                          : 'Confidence — run AUTO CAPTURE',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.muted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: _confidence.clamp(0, 1),
                                        minHeight: 8,
                                        backgroundColor: AppColors.border,
                                        color: AppColors.aiPurple,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _saving
                                                ? null
                                                : () => _persist(acceptAi: true),
                                            icon: const Icon(Icons.check, size: 18),
                                            label: Text(
                                              _saving ? 'Saving…' : 'Accept AI',
                                            ),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: AppColors.navy,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: _saving
                                                ? null
                                                : () => _persist(acceptAi: false),
                                            icon: const Icon(Icons.edit_outlined, size: 18),
                                            label: const Text('Save override'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.aiPurpleSoft,
                                        borderRadius: AppRadii.border,
                                      ),
                                      child: Text(
                                        _note ??
                                            'Pick a tooth photo to run shade suggestion. Manual override is always available and saved to the case.',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          height: 1.4,
                                          color: AppColors.navy,
                                        ),
                                      ),
                                    ),
                                  ],
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
                                height: 110,
                                width: double.infinity,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _vita.map((s) {
                                final selected = _selected == s;
                                return InkWell(
                                  onTap: () => setState(() {
                                    _selected = s;
                                    _saveStatus = null;
                                  }),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: 56,
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.navy
                                            : AppColors.border,
                                        width: selected ? 2 : 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: _swatch(s),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          s,
                                          style: const TextStyle(
                                            fontSize: 11,
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
                  width: 260,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Session saves',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'Accepted & overrides this session',
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

class _ShadeBlock extends StatelessWidget {
  const _ShadeBlock({
    required this.label,
    required this.shade,
    required this.color,
    this.highlight = false,
    this.sub,
  });

  final String label;
  final String shade;
  final Color color;
  final bool highlight;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: highlight ? AppColors.aiPurple : AppColors.border,
            width: highlight ? 2 : 1,
          ),
          color: highlight ? AppColors.aiPurpleSoft : null,
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(height: 6),
            Text(shade, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (sub != null)
              Text(sub!, style: const TextStyle(fontSize: 10, color: AppColors.aiPurple)),
          ],
        ),
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
