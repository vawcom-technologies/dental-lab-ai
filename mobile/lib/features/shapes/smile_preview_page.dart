import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

/// Tooth shape library from client (20 smile previews in a 4×5 grid).
class SmilePreviewPage extends StatefulWidget {
  const SmilePreviewPage({super.key});

  static const assetPath = 'assets/clinical/tooth-preview-grid.png';

  @override
  State<SmilePreviewPage> createState() => _SmilePreviewPageState();
}

class _SmilePreviewPageState extends State<SmilePreviewPage> {
  static const cols = 5;
  static const rows = 4;
  static const total = cols * rows;

  int? _selected;

  @override
  Widget build(BuildContext context) {
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
                      'Smile Preview',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.navy,
                      ),
                    ),
                    Text(
                      'Select a tooth shape from the client library, then overlay on the patient photo (Week 3).',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (_selected != null)
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.check, size: 18),
                  label: Text('Use shape ${_selected! + 1}'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected == null
                              ? 'Shape library · $total options'
                              : 'Selected · Shape ${_selected! + 1} of $total',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.navy,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 1024 / 563,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      SmilePreviewPage.assetPath,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.high,
                                    ),
                                    GridView.builder(
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: cols,
                                        childAspectRatio: (1024 / cols) / (563 / rows),
                                      ),
                                      itemCount: total,
                                      itemBuilder: (context, i) {
                                        final selected = _selected == i;
                                        return InkWell(
                                          onTap: () =>
                                              setState(() => _selected = i),
                                          child: AnimatedContainer(
                                            duration:
                                                const Duration(milliseconds: 160),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: selected
                                                    ? AppColors.dentalBlue
                                                    : Colors.white24,
                                                width: selected ? 3 : 0.5,
                                              ),
                                              color: selected
                                                  ? AppColors.dentalBlue
                                                      .withValues(alpha: 0.15)
                                                  : Colors.transparent,
                                            ),
                                            alignment: Alignment.topLeft,
                                            padding: const EdgeInsets.all(4),
                                            child: selected
                                                ? Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 2,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: AppColors.dentalBlue,
                                                      borderRadius:
                                                          BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      '${i + 1}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 280,
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Overlay controls',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selected == null
                              ? 'Pick a smile shape from the grid to prepare an overlay on the patient photo.'
                              : 'Shape ${_selected! + 1} ready. Resize / rotate / reposition will attach to the patient photo in Week 3.',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_selected != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment(
                                  -1 + 2 * ((_selected! % cols) + 0.5) / cols,
                                  -1 + 2 * ((_selected! ~/ cols) + 0.5) / rows,
                                ),
                                child: SizedBox(
                                  width: cols.toDouble(),
                                  height: rows.toDouble(),
                                  child: Image.asset(
                                    SmilePreviewPage.assetPath,
                                    fit: BoxFit.fill,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Transform (preview)',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const _SliderRow(label: 'Scale', value: 0.7),
                          const _SliderRow(label: 'Rotate', value: 0.5),
                          const _SliderRow(label: 'Opacity', value: 0.85),
                        ] else
                          Expanded(
                            child: Center(
                              child: Icon(
                                Icons.sentiment_satisfied_alt_outlined,
                                size: 48,
                                color: AppColors.muted.withValues(alpha: 0.4),
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
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.dentalBlue,
                thumbColor: AppColors.navy,
                inactiveTrackColor: AppColors.border,
              ),
              child: Slider(value: value, onChanged: (_) {}),
            ),
          ),
        ],
      ),
    );
  }
}
