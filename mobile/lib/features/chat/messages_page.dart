import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui_kit.dart';

class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: SectionCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Lab Messages',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  const TextField(
                    decoration: InputDecoration(
                      hintText: 'Search conversations...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('PINNED',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: const [
                        _Thread(
                          name: 'Marcus Webb',
                          meta: 'PT-2841 · Precision Ceramics',
                          preview: 'Distal margin looks slightly underprepared…',
                          time: '10:24',
                          unread: 2,
                          selected: true,
                        ),
                        _Thread(
                          name: 'Elaine Torres',
                          meta: 'PT-2839 · Elite Dent Lab',
                          preview: 'Please confirm shade before milling.',
                          time: '09:40',
                          unread: 1,
                        ),
                        _Thread(
                          name: 'Linda Moore',
                          meta: 'PT-2836 · Elite Dent Lab',
                          preview: 'Case marked complete.',
                          time: 'Yesterday',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SectionCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        const InitialsAvatar(name: 'Marcus Webb'),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Marcus Webb',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                              Text('PT-2841 · Precision Ceramics Lab',
                                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        StatusChip(statusKey: 'in_progress'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: const [
                        _Bubble(
                          mine: true,
                          text:
                              'Uploaded intraoral scan for #14. Prefer shade A2 if AI disagrees.',
                        ),
                        _Bubble(
                          mine: false,
                          text: 'Received, thank you. Reviewing margins now.',
                        ),
                        _Bubble(
                          mine: false,
                          text:
                              'Note: distal margin looks slightly underprepared — confirm before fabrication.',
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        _Quick('Shade confirmed'),
                        _Quick('Rescan needed'),
                        _Quick('Approved for fabrication'),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.attach_file),
                        ),
                        const Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Message Precision Ceramics Lab...',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {},
                          child: const Icon(Icons.send, size: 18),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thread extends StatelessWidget {
  const _Thread({
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
                      child: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                    Text(time, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
                Text(meta, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                const SizedBox(height: 2),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
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
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.mine, required this.text});

  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: mine ? AppColors.navy : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: mine ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: mine ? Colors.white : AppColors.text,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.navy)),
    );
  }
}
