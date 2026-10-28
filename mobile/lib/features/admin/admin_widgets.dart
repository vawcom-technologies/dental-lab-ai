import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/widgets/page_kit.dart';
import 'admin_models.dart';

// The shared page kit moved to core; admin screens keep importing it here.
export '../../core/widgets/page_kit.dart';

/// Searchable lab picker. Returns null when cancelled; `(lab: null)` when
/// [noneLabel] was chosen.
Future<({AdminLab? lab})?> pickLab(
  BuildContext context,
  ApiClient api, {
  required String title,
  String? message,
  String? noneLabel,
  String? excludeLabId,
}) {
  return AppDialogs.sheet<({AdminLab? lab})>(
    context: context,
    maxWidth: 520,
    builder: (ctx) => _LabPicker(
      api: api,
      title: title,
      message: message,
      noneLabel: noneLabel,
      excludeLabId: excludeLabId,
    ),
  );
}

class _LabPicker extends StatefulWidget {
  const _LabPicker({
    required this.api,
    required this.title,
    this.message,
    this.noneLabel,
    this.excludeLabId,
  });

  final ApiClient api;
  final String title;
  final String? message;
  final String? noneLabel;
  final String? excludeLabId;

  @override
  State<_LabPicker> createState() => _LabPickerState();
}

class _LabPickerState extends State<_LabPicker> {
  late final Future<List<AdminLab>> _labs = widget.api
      .adminLabs()
      .then((rows) => rows.map(AdminLab.new).toList());
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final height = (MediaQuery.sizeOf(context).height * 0.7).clamp(320.0, 620.0);
    // Own (transparent) Material: ListTiles paint highlights on the nearest
    // Material, which otherwise sits under the sheet's frosted box.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: AppFonts.style(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
              ),
            ),
            if (widget.message != null) ...[
              const SizedBox(height: 6),
              Text(
                widget.message!,
                style: AppFonts.style(fontSize: 13, color: AppColors.muted),
              ),
            ],
            const SizedBox(height: 12),
            CupertinoSearchTextField(
              placeholder: loc.tr('admin.searchLabs'),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            if (widget.noneLabel != null)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: const Icon(Icons.link_off_rounded, color: AppColors.muted),
                title: Text(
                  widget.noneLabel!,
                  style: AppFonts.style(
                    fontWeight: FontWeight.w600,
                    color: AppColors.navy,
                  ),
                ),
                onTap: () => Navigator.pop(context, (lab: null)),
              ),
            Expanded(
              child: FutureBuilder<List<AdminLab>>(
                future: _labs,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(child: Text(friendlyError(snap.error!)));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  final labs = snap.data!
                      .where((l) =>
                          l.id != widget.excludeLabId &&
                          (l.name.toLowerCase().contains(_q) ||
                              l.email.toLowerCase().contains(_q)))
                      .toList();
                  if (labs.isEmpty) {
                    return Center(
                      child: Text(
                        loc.tr('admin.noLabsFound'),
                        style: AppFonts.style(color: AppColors.muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: labs.length,
                    itemBuilder: (context, i) {
                      final lab = labs[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: UserAvatar(name: lab.name, url: lab.avatarUrl, size: 36),
                        title: Text(
                          lab.name,
                          style: AppFonts.style(
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                          ),
                        ),
                        subtitle: Text(
                          dentistCount(loc, lab.dentistCount),
                          style: AppFonts.style(fontSize: 12, color: AppColors.muted),
                        ),
                        trailing: lab.hiddenFromLabs
                            ? AdminBadge(
                                loc.tr('admin.hidden'),
                                color: AppColors.muted,
                              )
                            : null,
                        onTap: () => Navigator.pop(context, (lab: lab)),
                      );
                    },
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: AppButtons.ghost(
                onPressed: () => Navigator.pop(context),
                label: loc.cancel,
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
