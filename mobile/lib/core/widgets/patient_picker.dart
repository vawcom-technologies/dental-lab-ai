import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
  final int? caseId;
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

  int _pid(Map<String, dynamic> row) => (row['id'] as num).toInt();

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
        : 'Case #${widget.caseId ?? '—'}';

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
              const Expanded(
                child: Text(
                  'Patients',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                    fontSize: 13,
                  ),
                ),
              ),
              if (widget.onRefresh != null)
                IconButton(
                  tooltip: 'Refresh',
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
            _menu.close();
            widget.onAdd();
          },
          leadingIcon: const Icon(Icons.person_add_alt_1, size: 18),
          child: const Text('Add patient'),
        ),
      ],
      builder: (context, controller, child) {
        return SizedBox(
          width: widget.width,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadii.borderSm,
              onTap: !widget.enabled
                  ? null
                  : () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      size: 18,
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
                              fontSize: 13,
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
                              fontSize: 11,
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
                      size: 18,
                      color: AppColors.muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
