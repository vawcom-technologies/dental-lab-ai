import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

/// Week 3 — overlay tooth shape on patient photo (pan / resize / rotate).
class ShapeOverlayPage extends StatefulWidget {
  const ShapeOverlayPage({super.key, required this.api});

  final ApiClient api;

  static const shapeAsset = 'assets/clinical/tooth-preview-grid.png';
  static const cols = 5;
  static const rows = 4;
  static const total = cols * rows;

  @override
  State<ShapeOverlayPage> createState() => _ShapeOverlayPageState();
}

class _ShapeOverlayPageState extends State<ShapeOverlayPage> {
  List<Map<String, dynamic>> _patients = [];
  Map<String, dynamic>? _patient;
  Map<String, dynamic>? _case;
  Uint8List? _photoBytes;
  int _shapeIndex = 0;
  Offset _offset = const Offset(40, 40);
  double _scale = 0.55;
  double _rotation = 0;
  bool _loading = true;
  bool _saving = false;
  String? _status;
  String? _error;

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
      _status = null;
    });
    final cases = await widget.api.listCases();
    final mine = cases.where((c) => c['patient_id'] == patient['id']).toList();
    final caseRow = mine.isEmpty
        ? await widget.api.createCase(patient['id'] as int)
        : mine.first;
    setState(() => _case = caseRow);
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoBytes = Uint8List.fromList(bytes);
      _offset = const Offset(40, 40);
      _scale = 0.55;
      _rotation = 0;
    });
  }

  Future<void> _save() async {
    if (_case == null) return;
    setState(() => _saving = true);
    try {
      await widget.api.saveShape(
        caseId: _case!['id'] as int,
        shapeId: 'shape_${_shapeIndex + 1}',
        x: _offset.dx,
        y: _offset.dy,
        rotation: _rotation,
        scale: _scale,
      );
      setState(
        () => _status =
            'Saved shape ${_shapeIndex + 1} (x=${_offset.dx.toStringAsFixed(0)}, y=${_offset.dy.toStringAsFixed(0)}, r=${_rotation.toStringAsFixed(1)}°, s=${_scale.toStringAsFixed(2)})',
      );
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
                      'Smile Preview / Overlay',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'Select shape · drag to move · sliders for resize & rotate',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_patients.isNotEmpty)
                SizedBox(
                  width: 200,
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
              OutlinedButton.icon(
                onPressed: _pickPhoto,
                icon: const Icon(Icons.image_outlined, size: 18),
                label: const Text('Patient photo'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _saving || _photoBytes == null ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save overlay'),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: const TextStyle(color: AppColors.success)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 260,
                  child: SectionCard(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Library · shape ${_shapeIndex + 1}/${ShapeOverlayPage.total}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  ShapeOverlayPage.shapeAsset,
                                  fit: BoxFit.cover,
                                ),
                                GridView.builder(
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: ShapeOverlayPage.cols,
                                    childAspectRatio: (1024 / ShapeOverlayPage.cols) /
                                        (563 / ShapeOverlayPage.rows),
                                  ),
                                  itemCount: ShapeOverlayPage.total,
                                  itemBuilder: (context, i) {
                                    final selected = _shapeIndex == i;
                                    return InkWell(
                                      onTap: () => setState(() => _shapeIndex = i),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.dentalBlue
                                                : Colors.transparent,
                                            width: 2.5,
                                          ),
                                          color: selected
                                              ? AppColors.dentalBlue
                                                  .withValues(alpha: 0.15)
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text('Scale', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        Slider(
                          value: _scale,
                          min: 0.2,
                          max: 1.6,
                          onChanged: (v) => setState(() => _scale = v),
                        ),
                        const Text('Rotate', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        Slider(
                          value: _rotation,
                          min: -45,
                          max: 45,
                          onChanged: (v) => setState(() => _rotation = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SectionCard(
                    padding: EdgeInsets.zero,
                    child: ClipRRect(
                      borderRadius: AppRadii.border,
                      child: _photoBytes == null
                          ? const Center(
                              child: Text(
                                'Load a patient photo to position the tooth shape overlay.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  children: [
                                    Positioned.fill(
                                      child: Image.memory(
                                        _photoBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    Positioned(
                                      left: _offset.dx,
                                      top: _offset.dy,
                                      child: GestureDetector(
                                        onPanUpdate: (d) {
                                          setState(() => _offset += d.delta);
                                        },
                                        child: Transform.rotate(
                                          angle: _rotation * 3.1415926535 / 180,
                                          child: Transform.scale(
                                            scale: _scale,
                                            child: SizedBox(
                                              width: 200,
                                              height: 140,
                                              child: _ShapeCell(
                                                index: _shapeIndex,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 12,
                                      bottom: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'Drag overlay to reposition',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
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

/// Crops one cell from the 5×4 tooth-shape grid asset.
class _ShapeCell extends StatelessWidget {
  const _ShapeCell({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    const cols = ShapeOverlayPage.cols;
    const rows = ShapeOverlayPage.rows;
    final col = index % cols;
    final row = index ~/ cols;
    final ax = cols == 1 ? 0.0 : -1.0 + 2.0 * col / (cols - 1);
    final ay = rows == 1 ? 0.0 : -1.0 + 2.0 * row / (rows - 1);

    return ClipRect(
      child: Align(
        alignment: Alignment(ax, ay),
        widthFactor: 1 / cols,
        heightFactor: 1 / rows,
        child: Image.asset(
          ShapeOverlayPage.shapeAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
