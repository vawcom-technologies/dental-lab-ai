import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/widgets/ui_kit.dart';
import '../../core/l10n/app_localizations.dart';

/// Camera tab "Incoming (n)": photos sent from the PC page (/scan-upload).
/// Pick one, check it, add it to the selected patient's photos. Scans arrive on
/// the Scans tab instead.
class IncomingPhotosButton extends StatefulWidget {
  const IncomingPhotosButton({
    super.key,
    required this.api,
    required this.patientId,
    required this.patientLabel,
    required this.angle,
    required this.active,
    required this.enabled,
    required this.onAssigned,
    required this.onOpenShade,
    required this.onOpenSmile,
  });

  final ApiClient api;
  final String? patientId;
  final String patientLabel;
  /// Camera angle tab in view; the default for the added photo.
  final String angle;
  /// Tab is visible: refresh the count when it becomes active.
  final bool active;
  final bool enabled;
  /// Photo added to the patient under [angle] (switch tab, reload the grid).
  final Future<void> Function(String photoId, String angle) onAssigned;
  final void Function(String photoId) onOpenShade;
  final void Function(String photoId) onOpenSmile;

  @override
  State<IncomingPhotosButton> createState() => _IncomingPhotosButtonState();
}

class _IncomingPhotosButtonState extends State<IncomingPhotosButton> {
  List<Map<String, dynamic>> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant IncomingPhotosButton old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.api.listScanInbox();
      if (!mounted) return;
      setState(() => _items = all.where((i) => i['kind'] == 'photo').toList());
    } catch (_) {
      // Count only; opening the list shows errors.
    }
  }

  Future<void> _open() async {
    await _load();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: _items.isEmpty
            ? Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  AppLocalizations.of(context).tr('c.noIncoming'),
                  textAlign: TextAlign.center,
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final item in _items)
                    ListTile(
                      leading: const Icon(Icons.photo_outlined),
                      title: Text('${item['file_name']}'),
                      subtitle: Text(
                        '${((item['byte_size'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MB'
                        ' · ${'${item['created_at'] ?? ''}'.split('T').first}',
                      ),
                      onTap: () => Navigator.pop(ctx, item),
                    ),
                ],
              ),
      ),
    );
    if (picked != null && mounted) await _review(picked);
  }

  /// Full-size check, then Add to patient / Delete / Close.
  Future<void> _review(Map<String, dynamic> item) async {
    final id = '${item['id']}';
    Uint8List bytes;
    setState(() => _busy = true);
    try {
      bytes = await widget.api.downloadScanInboxFile(id);
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final pid = widget.patientId;
    var angle = const {'frontal', 'left', 'right'}.contains(widget.angle)
        ? widget.angle
        : 'frontal';
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${item['file_name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640, maxHeight: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx, setInner) => SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'frontal', label: Text(AppLocalizations.of(context).cameraAngleLabel('frontal'))),
                    ButtonSegment(value: 'left', label: Text(AppLocalizations.of(context).cameraAngleLabel('left'))),
                    ButtonSegment(value: 'right', label: Text(AppLocalizations.of(context).cameraAngleLabel('right'))),
                  ],
                  selected: {angle},
                  onSelectionChanged: (v) => setInner(() => angle = v.first),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: Text(AppLocalizations.of(context).commonDelete),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).commonClose)),
          FilledButton(
            onPressed: pid == null ? null : () => Navigator.pop(ctx, 'assign'),
            child: Text(pid == null ? AppLocalizations.of(context).tr('c.selPatFirst') : AppLocalizations.of(context).trp('c.addTo', {'n': widget.patientLabel})),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'delete') await _delete(id);
    if (action == 'assign' && pid != null) await _assign(id, pid, angle);
  }

  Future<void> _assign(String id, String pid, String angle) async {
    setState(() => _busy = true);
    String photoId;
    try {
      final res = await widget.api.assignScanInbox(id, pid, angle: angle);
      photoId = '${res['record_id']}';
      await widget.onAssigned(photoId, angle);
      await _load();
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context).tr('c.photoAdded')),
        content: Text(AppLocalizations.of(context).trp('c.savedTo', {'n': widget.patientLabel})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context).tr('c.later'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'smile'),
            child: Text(AppLocalizations.of(context).navSmilePreview),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'shade'),
            child: Text(AppLocalizations.of(context).navShade),
          ),
        ],
      ),
    );
    if (choice == 'shade') widget.onOpenShade(photoId);
    if (choice == 'smile') widget.onOpenSmile(photoId);
  }

  Future<void> _delete(String id) async {
    final ok = await confirmPatientMediaDelete(context);
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.api.deleteScanInbox(id);
      await _load();
    } catch (e) {
      if (mounted) AppSnackBars.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: widget.enabled && !_busy ? _open : null,
      icon: const Icon(Icons.inbox_outlined, size: 18),
      label: Text(_items.isEmpty ? AppLocalizations.of(context).tr('c.incoming') : '${AppLocalizations.of(context).tr('c.incoming')} (${_items.length})'),
    );
  }
}
