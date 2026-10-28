import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'page_kit.dart';
import 'ui_kit.dart';

Widget _section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: SectionLabel(title),
    );

/// True when a scan was saved onto the case (not library-only).
bool _scanOnCase(Map<String, dynamic> r) => r['on_case'] == true;

/// True when a shade detection has a saved analysis (dentist finished it).
bool _shadeSaved(Map<String, dynamic> r) {
  final a = r['analysis'];
  return a is Map && a.isNotEmpty;
}

/// Scans / shades / smiles the dentist saved onto the case.
///
/// Matches backend [case_flow.items]: library scans (`on_case=false`) and
/// shade photos without analysis are excluded so admin/review records match
/// what was submitted.
Future<List<List<Map<String, dynamic>>>> loadPatientRecords(
  ApiClient api,
  String patientId,
) async {
  final rows = await Future.wait([
    api.listPatientScans(patientId),
    api.listShadeDetections(patientId),
    api.listSmilePreviews(patientId),
  ]);
  return [
    rows[0].where(_scanOnCase).toList(growable: false),
    rows[1].where(_shadeSaved).toList(growable: false),
    rows[2],
  ];
}

/// Scans, shade analyses and smile previews, read-only. With [onOpen]
/// (`scan` | `shade` | `smile`) every group and item opens its page.
class PatientRecords extends StatefulWidget {
  const PatientRecords({super.key, required this.api, required this.patientId, this.onOpen, this.rows});

  final ApiClient api;
  final String patientId;
  final ValueChanged<String>? onOpen;

  /// Already-started [loadPatientRecords], so a parent can wait on it.
  final Future<List<List<Map<String, dynamic>>>>? rows;

  @override
  State<PatientRecords> createState() => _RecordsState();
}

class _RecordsState extends State<PatientRecords> {
  ApiClient get api => widget.api;

  late final _rows = widget.rows ?? loadPatientRecords(api, widget.patientId);

  VoidCallback? _open(String tool) => widget.onOpen == null ? null : () => widget.onOpen!(tool);

  String _when(Map<String, dynamic> r) =>
      adminWhen(context, DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal());

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return FutureBuilder<List<List<Map<String, dynamic>>>>(
      future: _rows,
      builder: (context, snap) {
        Widget body;
        if (snap.hasError) {
          body = Text(
            friendlyError(snap.error!),
            style: AppFonts.style(fontSize: 13, color: AppColors.muted),
          );
        } else if (!snap.hasData) {
          body = const LinearProgressIndicator(minHeight: 2);
        } else {
          final [scans, shades, smiles] = snap.data!;
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _group(context, 'scan', loc.navScans, Icons.view_in_ar_outlined, scans, [
                for (final r in scans) _scanRow(r),
              ]),
              _group(context, 'shade', loc.tr('admin.shadeAnalyses'), Icons.palette_outlined, shades, [
                Wrap(spacing: 10, runSpacing: 10, children: [for (final r in shades) _shadeCard(r)]),
              ]),
              _group(context, 'smile', loc.navSmilePreview, Icons.sentiment_satisfied_alt_outlined, smiles, [
                Wrap(spacing: 10, runSpacing: 10, children: [for (final r in smiles) _thumb(r, onTap: _open('smile'))]),
              ]),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_section(loc.tr('admin.records')), body],
        );
      },
    );
  }

  Widget _group(
    BuildContext context,
    String tool,
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    List<Widget> items,
  ) {
    final loc = AppLocalizations.of(context);
    final open = _open(tool);
    final header = Row(
      children: [
        AdminIcon(icon: icon, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$title (${rows.length})',
            style: AppFonts.style(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.navy),
          ),
        ),
        if (open != null) ...[
          Text(loc.tr('records.openAll'),
              style: AppFonts.style(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.dentalBlue)),
          const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.dentalBlue),
        ],
      ],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          open == null
              ? header
              : InkWell(onTap: open, borderRadius: BorderRadius.circular(10), child: header),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(loc.tr('admin.none'), style: AppFonts.style(fontSize: 13, color: AppColors.muted))
          else
            ...items,
        ],
      ),
    );
  }

  Widget _scanRow(Map<String, dynamic> r) {
    final open = _open('scan');
    return InkWell(
      onTap: open,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, size: 18, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r['file_name'] ?? r['filename'] ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppFonts.style(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: open == null ? AppColors.navy : AppColors.dentalBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(_when(r), style: AppFonts.style(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  /// Photo with the shade the dentist settled on, and whether that was the
  /// AI's match or their own pick.
  Widget _shadeCard(Map<String, dynamic> r) {
    final loc = AppLocalizations.of(context);
    final a = r['analysis'] is Map ? Map<String, dynamic>.from(r['analysis'] as Map) : const <String, dynamic>{};
    String? str(Object? v) => (v?.toString().trim().isEmpty ?? true) ? null : v.toString().trim();
    final best = str(a['final_shade']) ?? str(a['summary_shade']);
    final ai = str(a['detected_shade']);
    final picked = a['overridden'] == true || (best != null && ai != null && best != ai);
    final open = _open('shade');
    return SizedBox(
      width: 150,
      child: InkWell(
        onTap: open ?? () => _preview(r),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _thumb(r, width: 150, height: 100, onTap: open),
            const SizedBox(height: 8),
            Text(loc.tr('records.bestShade').toUpperCase(),
                style: AppFonts.style(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: 0.6)),
            Text(best ?? '—',
                style: AppFonts.style(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.navy, letterSpacing: -0.4)),
            if (best != null)
              Text(
                loc.tr(picked ? 'records.dentistPick' : 'records.aiPick'),
                style: AppFonts.style(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: picked ? AppColors.review : AppColors.success,
                ),
              ),
            if (picked && ai != null)
              Text(loc.trp('records.aiWas', {'shade': ai}), style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
            Text(_when(r), style: AppFonts.style(fontSize: 11.5, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  Future<void> _preview(Map<String, dynamic> r) {
    final url = api.resolveMediaUrl('${r['file_url'] ?? ''}');
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: Image.network(url, headers: api.mediaHeaders, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  /// Image tile. [onTap] opens the page; without it the tap previews. With
  /// [onTap] a corner button still previews.
  Widget _thumb(Map<String, dynamic> r, {double width = 100, double height = 100, VoidCallback? onTap}) {
    final loc = AppLocalizations.of(context);
    final url = api.resolveMediaUrl('${r['file_url'] ?? ''}');
    return Tooltip(
      message: _when(r),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: url.isEmpty ? onTap : onTap ?? () => _preview(r),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: AppColors.inset,
                  child: url.isEmpty
                      ? null
                      : Image.network(
                          url,
                          headers: api.mediaHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
                          ),
                        ),
                ),
                if (onTap != null && url.isNotEmpty)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: loc.tr('records.preview'),
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                        padding: EdgeInsets.zero,
                        onPressed: () => _preview(r),
                        icon: const Icon(Icons.zoom_out_map_rounded, color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
