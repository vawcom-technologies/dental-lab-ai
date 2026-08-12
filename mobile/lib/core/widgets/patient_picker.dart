import 'package:flutter/material.dart';

import '../haptics/app_haptics.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'touchable.dart';
import 'ui_kit.dart';

/// Compact header control: tap to open the patient list.
class PatientPickerButton extends StatefulWidget {
  const PatientPickerButton({
    super.key,
    required this.patients,
    required this.selected,
    required this.onSelect,
    required this.onAdd,
    this.caseId,
    this.enabled = true,
    this.onRefresh,
    this.emptyHint = 'No patients yet — add one to continue.',
    this.width = 220,
  });

  final List<Map<String, dynamic>> patients;
  final Map<String, dynamic>? selected;
  /// Legacy int case ids or future UUID strings.
  final Object? caseId;
  final bool enabled;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final VoidCallback onAdd;
  final Future<void> Function()? onRefresh;
  final String emptyHint;
  final double width;

  @override
  State<PatientPickerButton> createState() => _PatientPickerButtonState();
}

class _PatientPickerButtonState extends State<PatientPickerButton> {
  final _menu = MenuController();

  /// GDPR patients use UUID strings; legacy rows used ints.
  String _pid(Map<String, dynamic> row) => '${row['id'] ?? ''}';

  String _name(Map<String, dynamic> p) =>
      '${p['first_name'] ?? ''} ${p['last_name'] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final label = selected == null
        ? 'Select patient'
        : _name(selected).isEmpty
            ? 'Patient'
            : _name(selected);
    final subtitle = selected == null
        ? (widget.patients.isEmpty
            ? 'None yet'
            : '${widget.patients.length} available')
        : (widget.caseId == null ? 'Ready for detect' : 'Case #${widget.caseId}');

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(AppColors.card),
        elevation: WidgetStateProperty.all(0),
        shadowColor: WidgetStateProperty.all(Colors.transparent),
        padding:
            WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 6)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: AppRadii.borderSm),
        ),
      ),
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLocalizations.of(context).navPatients,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.onRefresh != null)
                IconButton(
                  tooltip: AppLocalizations.of(context).refresh,
                  onPressed: widget.enabled
                      ? () async {
                          await widget.onRefresh!();
                          if (mounted) setState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.refresh, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        if (widget.patients.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Text(
              widget.emptyHint,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          )
        else
          ...widget.patients.map((p) {
            final selectedRow =
                selected != null && _pid(selected) == _pid(p);
            final name = _name(p);
            return MenuItemButton(
              onPressed: () {
                AppHaptics.selection();
                widget.onSelect(p);
                _menu.close();
              },
              leadingIcon: InitialsAvatar(
                name: name.isEmpty ? '?' : name,
                size: 28,
              ),
              trailingIcon: selectedRow
                  ? const Icon(
                      Icons.check,
                      size: 16,
                      color: AppColors.dentalBlue,
                    )
                  : null,
              child: SizedBox(
                width: 180,
                child: Text(
                  name.isEmpty ? 'Patient #${_pid(p)}' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        selectedRow ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }),
        const Divider(height: 8),
        MenuItemButton(
          onPressed: () {
            AppHaptics.light();
            _menu.close();
            // Defer so MenuAnchor can dispose dependents before navigation.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              widget.onAdd();
            });
          },
          leadingIcon: const Icon(Icons.person_add_alt_1, size: 18),
          child: Text(AppLocalizations.of(context).addPatient),
        ),
      ],
      builder: (context, controller, child) {
        return SizedBox(
          width: widget.width,
          child: Touchable(
            enabled: widget.enabled,
            borderRadius: AppRadii.borderSm,
            minHeight: 44,
            onTap: () {
              if (controller.isOpen) {
                controller.close();
              } else {
                controller.open();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.neo,
                borderRadius: AppRadii.borderSm,
                boxShadow: controller.isOpen
                    ? NeoShadows.pressed()
                    : NeoShadows.soft(depth: 0.55),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 20,
                    color: selected == null
                        ? AppColors.warning
                        : AppColors.navy,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            color: selected == null
                                ? AppColors.warning
                                : AppColors.navy,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    controller.isOpen
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
