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

/// Scans, shade analyses and smile previews, read-only.
class PatientRecords extends StatefulWidget {
  const PatientRecords({super.key, required this.api, required this.patientId});

  final ApiClient api;
  final String patientId;

  @override
  State<PatientRecords> createState() => _RecordsState();
}

class _RecordsState extends State<PatientRecords> {
  ApiClient get api => widget.api;

  late final _rows = Future.wait([
    api.listPatientScans(widget.patientId),
    api.listShadeDetections(widget.patientId),
    api.listSmilePreviews(widget.patientId),
  ]);

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
              _group(context, loc.navScans, Icons.view_in_ar_outlined, scans, images: false),
              _group(context, loc.tr('admin.shadeAnalyses'), Icons.palette_outlined, shades),
              _group(context, loc.navSmilePreview, Icons.sentiment_satisfied_alt_outlined, smiles),
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
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows, {
    bool images = true,
  }) {
    final loc = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.dentalBlue),
              const SizedBox(width: 8),
              Text(
                '$title (${rows.length})',
                style: AppFonts.style(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(loc.tr('admin.none'), style: AppFonts.style(fontSize: 13, color: AppColors.muted))
          else if (!images)
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${r['file_name'] ?? r['filename'] ?? '—'} · ${adminWhen(context, DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal())}',
                  style: AppFonts.style(fontSize: 13, color: AppColors.navy),
                ),
              )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final r in rows) _thumb(context, r)],
            ),
        ],
      ),
    );
  }

  Widget _thumb(BuildContext context, Map<String, dynamic> r) {
    final url = api.resolveMediaUrl('${r['file_url'] ?? ''}');
    final shade = r['shade']?.toString();
    Widget image(BoxFit fit) => Image.network(
          url,
          headers: api.mediaHeaders,
          fit: fit,
          errorBuilder: (_, _, _) => const Center(
            child: Icon(Icons.broken_image_outlined, color: AppColors.muted),
          ),
        );
    return Tooltip(
      message: adminWhen(context, DateTime.tryParse('${r['created_at'] ?? ''}')?.toLocal()),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: url.isEmpty
            ? null
            : () => showDialog<void>(
                  context: context,
                  builder: (ctx) => Dialog(
                    backgroundColor: Colors.black,
                    insetPadding: const EdgeInsets.all(24),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: InteractiveViewer(child: image(BoxFit.contain)),
                    ),
                  ),
                ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: AppColors.inset, child: url.isEmpty ? null : image(BoxFit.cover)),
                if (shade != null)
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: AdminBadge(shade, color: AppColors.navy),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

