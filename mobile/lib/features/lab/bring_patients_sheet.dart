import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

/// Multi-select owned patients to auto-share with a lab on join/transfer.
/// [ownerUserId] defaults to the signed-in user; admins pass the dentist id.
Future<List<String>?> pickPatientsToBring(
  BuildContext context,
  ApiClient api, {
  required String title,
  required String message,
  String? ownerUserId,
}) async {
  final loc = AppLocalizations.of(context);
  List<Map<String, dynamic>> patients = [];
  Object? loadError;
  try {
    final uid = ownerUserId ?? api.userId ?? '';
    final raw = api.isAdmin && ownerUserId != null
        ? await api.adminPatients(q: '')
        : await api.listPatients();
    patients = [
      for (final p in raw)
        if (uid.isEmpty ||
            '${p['created_by'] ?? ''}' == uid ||
            '${p['owner_id'] ?? ''}' == uid)
          p,
    ];
  } catch (e) {
    loadError = e;
  }
  if (!context.mounted) return null;

  if (loadError != null) {
    AppSnackBars.error(context, friendlyError(loadError));
    return <String>[];
  }
  if (patients.isEmpty) return <String>[];

  final selected = <String>{};
  final maxH = (MediaQuery.sizeOf(context).height * 0.7).clamp(320.0, 640.0);

  return showCupertinoModalPopup<List<String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return Material(
            color: AppColors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: maxH,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: AppFonts.style(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.navy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  message,
                                  style: AppFonts.style(
                                    fontSize: 13,
                                    color: AppColors.muted,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          AppButtons.ghost(
                            onPressed: () => Navigator.pop(ctx, <String>[]),
                            label: loc.tr('join.bringNone'),
                            compact: true,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: patients.length,
                        itemBuilder: (_, i) {
                          final p = patients[i];
                          final id = '${p['id'] ?? ''}';
                          final first = '${p['first_name'] ?? ''}'.trim();
                          final last = '${p['last_name'] ?? ''}'.trim();
                          final name = '$first $last'.trim().isEmpty
                              ? id
                              : '$first $last'.trim();
                          final on = selected.contains(id);
                          return CheckboxListTile(
                            value: on,
                            onChanged: (v) {
                              setLocal(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                            title: Text(
                              name,
                              style: AppFonts.style(
                                fontWeight: FontWeight.w600,
                                color: AppColors.navy,
                              ),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Row(
                        children: [
                          AppButtons.ghost(
                            onPressed: () => Navigator.pop(ctx),
                            label: loc.cancel,
                          ),
                          const Spacer(),
                          AppButtons.primary(
                            onPressed: () =>
                                Navigator.pop(ctx, selected.toList()),
                            label: loc.trp('join.bringContinue', {
                              'n': '${selected.length}',
                            }),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
