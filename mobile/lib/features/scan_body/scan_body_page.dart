import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

/// Week 3 — scan-body diameter match (provisional table until client data).
class ScanBodyPage extends StatefulWidget {
  const ScanBodyPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<ScanBodyPage> createState() => _ScanBodyPageState();
}

class _ScanBodyPageState extends State<ScanBodyPage> {
  final _diameterCtrl = TextEditingController(text: '4.0');
  List<Map<String, dynamic>> _table = [];
  Map<String, dynamic>? _match;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTable();
  }

  @override
  void dispose() {
    _diameterCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTable() async {
    try {
      final rows = await widget.api.scanBodyTable();
      setState(() => _table = rows);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _matchManual() async {
    final mm = double.tryParse(_diameterCtrl.text.trim());
    if (mm == null) {
      setState(() => _error = 'Enter a valid diameter in mm');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.matchScanBody(mm);
      setState(() => _match = result);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _detectFromPhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final result = await widget.api.detectScanBody(bytes, file.name);
      setState(() {
        _match = result;
        final d = result['detected_diameter'];
        if (d != null) _diameterCtrl.text = d.toString();
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
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
          const Text(
            'Scan Body Diameter',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const Text(
            'Detect or enter diameter (mm) → match tooth / manufacturer',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSoft,
              borderRadius: AppRadii.border,
            ),
            child: const Text(
              'Using provisional reference table. Replace with client manufacturer data before production.',
              style: TextStyle(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
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
                  flex: 2,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Measurement',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _diameterCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Diameter (mm)',
                            hintText: 'e.g. 4.1',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _busy ? null : _matchManual,
                                icon: const Icon(Icons.search, size: 18),
                                label: Text(_busy ? 'Matching…' : 'Match table'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy ? null : _detectFromPhoto,
                                icon: const Icon(Icons.image_search_outlined, size: 18),
                                label: const Text('Detect from photo'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        if (_match != null) ...[
                          const Text(
                            'Result',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          _ResultTile(
                            label: 'Detected',
                            value: '${_match!['detected_diameter'] ?? '—'} mm',
                          ),
                          _ResultTile(
                            label: 'Tooth',
                            value: '${_match!['matched_tooth_position'] ?? '—'}',
                          ),
                          _ResultTile(
                            label: 'Manufacturer',
                            value: '${_match!['matched_manufacturer'] ?? '—'}',
                          ),
                          _ResultTile(
                            label: 'Platform',
                            value: '${_match!['matched_platform'] ?? '—'}',
                          ),
                          _ResultTile(
                            label: 'Confidence',
                            value: _match!['confidence_score'] == null
                                ? '—'
                                : '${(((_match!['confidence_score'] as num) * 100).round())}%',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _match!['note']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reference table (${_table.length} rows)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _table.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No reference rows loaded',
                                    style: TextStyle(color: AppColors.muted),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _table.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, i) {
                                    final row = _table[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        '${row['diameter_mm']} mm · ${row['manufacturer']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Tooth ${row['tooth_position']} · ${row['platform']}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: TextButton(
                                        onPressed: () {
                                          _diameterCtrl.text =
                                              '${row['diameter_mm']}';
                                          _matchManual();
                                        },
                                        child: const Text('Use'),
                                      ),
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

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
