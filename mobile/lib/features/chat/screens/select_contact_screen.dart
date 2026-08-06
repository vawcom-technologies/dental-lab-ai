import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../services/chat_api_service.dart';
import '../state/chat_controller.dart';

/// Pick a verified contact, then get-or-create a 1-to-1 conversation.
class SelectContactScreen extends StatefulWidget {
  const SelectContactScreen({
    super.key,
    this.onConversationOpened,
  });

  /// Called after a conversation is created/opened (before this route pops).
  final ValueChanged<Conversation>? onConversationOpened;

  @override
  State<SelectContactScreen> createState() => _SelectContactScreenState();
}

class _SelectContactScreenState extends State<SelectContactScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  List<UserProfile> _allUsers = [];
  List<UserProfile> _users = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;
  String? _roleFilter; // null = all
  String _query = '';

  static const _roleChips = <(String? value, String label)>[
    (null, 'All'),
    (AppRoles.dentist, 'Dentists'),
    (AppRoles.laboratory, 'Laboratories'),
  ];

  ChatApiService get _apiService {
    return context.read<ChatController>().apiService;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch a broad page, then filter locally so search/role work even when
      // DB still has legacy role values (admin/clinic) or PostgREST ilike is picky.
      final users = await _apiService.fetchUsers(limit: 100);
      if (!mounted) return;
      setState(() {
        _allUsers = users;
        _users = _applyFilters(users);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _refilter() {
    setState(() => _users = _applyFilters(_allUsers));
  }

  List<UserProfile> _applyFilters(List<UserProfile> source) {
    var rows = source;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((u) {
        final blob = [
          u.displayName,
          u.email,
          u.clinicName,
          u.phone,
          u.role,
          AppRoles.label(u.role),
        ].whereType<String>().join(' ').toLowerCase();
        return blob.contains(q);
      }).toList();
    }
    if (_roleFilter == AppRoles.dentist) {
      rows = rows.where((u) => AppRoles.isDentist(u.role)).toList();
    } else if (_roleFilter == AppRoles.laboratory) {
      rows = rows.where((u) => AppRoles.isLaboratory(u.role)).toList();
    }
    return rows;
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _query = value.trim();
      _refilter();
    });
  }

  Future<void> _select(UserProfile user) async {
    if (_creating) return;
    setState(() => _creating = true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );

    try {
      final controller = context.read<ChatController>();
      final conversation = await controller.openOrCreateWith(user.id);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss spinner
      widget.onConversationOpened?.call(conversation);
      if (mounted) Navigator.of(context).pop(conversation);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss spinner
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.navy,
        elevation: 0,
        title: const Text('New chat'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              depth: 0.7,
              child: TextField(
                controller: _search,
                onChanged: _onSearchChanged,
                decoration: const InputDecoration(
                  hintText: 'Search by name or clinic…',
                  prefixIcon: Icon(Icons.search, color: AppColors.muted),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in _roleChips)
                  SoftFilterChip(
                    label: chip.$2,
                    selected: _roleFilter == chip.$1,
                    onTap: () {
                      if (_roleFilter == chip.$1) return;
                      setState(() {
                        _roleFilter = chip.$1;
                        _users = _applyFilters(_allUsers);
                      });
                    },
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: SectionCard(
                padding: EdgeInsets.zero,
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'No contacts found.',
                                style: TextStyle(color: AppColors.muted),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _users.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: AppColors.border.withValues(alpha: 0.7),
                            ),
                            itemBuilder: (context, i) {
                              final user = _users[i];
                              return _ContactTile(
                                user: user,
                                onTap: _creating ? null : () => _select(user),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.user, this.onTap});

  final UserProfile user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName.characters.first.toUpperCase()
        : '?';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: AppColors.dentalBlue.withValues(alpha: 0.15),
        child: Text(
          initial,
          style: const TextStyle(
            color: AppColors.dentalBlue,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(
        user.displayName,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.clinicName != null && user.clinicName!.isNotEmpty)
            Text(
              user.clinicName!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          if (user.phone != null && user.phone!.isNotEmpty)
            Text(
              user.phone!,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
        ],
      ),
      isThreeLine: (user.clinicName?.isNotEmpty ?? false) &&
          (user.phone?.isNotEmpty ?? false),
      trailing: user.role == null || user.role!.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.sidebarActive,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                AppRoles.label(user.role),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.navy,
                ),
              ),
            ),
    );
  }
}
