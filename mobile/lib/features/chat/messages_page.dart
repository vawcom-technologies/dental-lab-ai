import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/layout/adaptive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, required this.api});

  final ApiClient api;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _searchCtrl = TextEditingController();
  final _composeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _threads = [];
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _active;
  bool _loading = true;
  bool _loadingMsgs = false;
  bool _sending = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _composeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _threads;
    return _threads.where((t) {
      final blob =
          '${t['patient_name']} ${t['meta']} ${t['preview']}'.toLowerCase();
      return blob.contains(q);
    }).toList();
  }

  Future<void> _loadThreads({int? preferCaseId}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final threads = await widget.api.listMessageThreads();
      setState(() => _threads = threads);
      if (threads.isEmpty) return;
      final prefer = preferCaseId ?? _active?['case_id'] as int?;
      final match = prefer == null
          ? threads.first
          : threads.firstWhere(
              (t) => t['case_id'] == prefer,
              orElse: () => threads.first,
            );
      await _openThread(match);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openThread(Map<String, dynamic> thread) async {
    setState(() {
      _active = thread;
      _loadingMsgs = true;
      _error = null;
    });
    try {
      final caseId = thread['case_id'] as int;
      final msgs = await widget.api.listMessages(caseId);
      await widget.api.markThreadRead(caseId);
      final refreshed = await widget.api.listMessageThreads();
      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _threads = refreshed;
        _active = refreshed.firstWhere(
          (t) => t['case_id'] == caseId,
          orElse: () => thread,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingMsgs = false);
    }
  }

  Future<void> _send([String? preset]) async {
    final caseId = _active?['case_id'] as int?;
    if (caseId == null) return;
    final text = (preset ?? _composeCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final msg = await widget.api.sendMessage(caseId: caseId, body: text);
      _composeCtrl.clear();
      setState(() => _messages = [..._messages, msg]);
      final refreshed = await widget.api.listMessageThreads();
      setState(() {
        _threads = refreshed;
        _active = refreshed.firstWhere(
          (t) => t['case_id'] == caseId,
          orElse: () => _active!,
        );
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatTime(dynamic raw) {
    if (raw == null) return '';
    final dt = DateTime.tryParse(raw.toString())?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${dt.day}/${dt.month}';
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final name = active?['patient_name']?.toString() ?? 'Select a conversation';
    final meta = active?['meta']?.toString() ?? '';
    final status = CaseStatuses.normalize(active?['case_status']?.toString());

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ),
          Expanded(
            child: AdaptiveSplit(
              narrowPanelHeight: 300,
              panel: SectionCard(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context).messagesTitle,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Refresh',
                              onPressed: _loading ? null : () => _loadThreads(),
                              icon: const Icon(Icons.refresh, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          decoration: const InputDecoration(
                            hintText: 'Search conversations...',
                            prefixIcon: Icon(Icons.search, size: 18),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'CONVERSATIONS',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: _loading
                              ? const Center(child: CircularProgressIndicator())
                              : _filtered.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No cases yet.\nCreate a patient to start chatting with the lab.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: AppColors.muted),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: _filtered.length,
                                      itemBuilder: (context, i) {
                                        final t = _filtered[i];
                                        final selected =
                                            active?['case_id'] == t['case_id'];
                                        return InkWell(
                                          onTap: () => _openThread(t),
                                          borderRadius: BorderRadius.circular(12),
                                          child: _ThreadTile(
                                            name: t['patient_name']?.toString() ??
                                                'Patient',
                                            meta: t['meta']?.toString() ?? '',
                                            preview:
                                                t['preview']?.toString() ?? '',
                                            time: _formatTime(t['last_sent_at']),
                                            unread:
                                                (t['unread'] as num?)?.toInt() ??
                                                    0,
                                            selected: selected,
                                          ),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
              content: SectionCard(
                    padding: EdgeInsets.zero,
                    child: active == null
                        ? const Center(
                            child: Text(
                              'Select a patient case to message the lab',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          )
                        : Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: AppColors.border),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    InitialsAvatar(name: name),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            meta,
                                            style: const TextStyle(
                                              color: AppColors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    StatusChip(statusKey: status),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _loadingMsgs
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : _messages.isEmpty
                                        ? const Center(
                                            child: Text(
                                              'No messages yet — say hello to the lab.',
                                              style: TextStyle(
                                                color: AppColors.muted,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            controller: _scrollCtrl,
                                            padding: const EdgeInsets.all(16),
                                            itemCount: _messages.length,
                                            itemBuilder: (context, i) {
                                              final m = _messages[i];
                                              return _Bubble(
                                                mine: m['mine'] == true,
                                                text: m['body']?.toString() ??
                                                    '[${m['type']}]',
                                                time: _formatTime(m['sent_at']),
                                                sender: m['sender_name']
                                                        ?.toString() ??
                                                    '',
                                              );
                                            },
                                          ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    _Quick(
                                      'Shade confirmed',
                                      onTap: () => _send('Shade confirmed'),
                                    ),
                                    _Quick(
                                      'Rescan needed',
                                      onTap: () => _send('Rescan needed'),
                                    ),
                                    _Quick(
                                      'Approved for fabrication',
                                      onTap: () =>
                                          _send('Approved for fabrication'),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _composeCtrl,
                                        minLines: 1,
                                        maxLines: 4,
                                        textInputAction: TextInputAction.send,
                                        onSubmitted: (_) => _send(),
                                        decoration: const InputDecoration(
                                          hintText:
                                              'Message Elite Dent Lab...',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _sending ? null : () => _send(),
                                      child: _sending
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.send, size: 18),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    required this.name,
    required this.meta,
    required this.preview,
    required this.time,
    this.unread = 0,
    this.selected = false,
  });

  final String name;
  final String meta;
  final String preview;
  final String time;
  final int unread;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: selected ? AppColors.sidebarActive : null,
        borderRadius: BorderRadius.circular(12),
        border: selected
            ? Border.all(color: AppColors.dentalBlue.withValues(alpha: 0.35))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialsAvatar(name: name, size: 36),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                Text(
                  meta,
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        unread > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (unread > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.mine,
    required this.text,
    this.time = '',
    this.sender = '',
  });

  final bool mine;
  final String text;
  final String time;
  final String sender;

  @override
  Widget build(BuildContext context) {
    final bg = mine ? AppColors.navy : AppColors.sidebarActive;
    final fg = mine ? Colors.white : AppColors.navy;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(mine ? 14 : 4),
              bottomRight: Radius.circular(mine ? 4 : 14),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!mine && sender.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    sender,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              Text(text, style: TextStyle(color: fg, height: 1.35)),
              if (time.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: fg.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
    );
  }
}
