import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/app_roles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/ui_kit.dart';
import '../models/chat_models.dart';
import '../services/chat_api_service.dart';
import '../state/chat_controller.dart';

const _kSeparator = Color(0xFFC6C6C8);
const _kSearchFill = Color(0xFFE5E5EA);

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

    try {
      final controller = context.read<ChatController>();
      final conversation = await controller.openOrCreateWith(user.id);
      if (!mounted) return;
      widget.onConversationOpened?.call(conversation);
      if (mounted) Navigator.of(context).pop(conversation);
    } catch (e) {
      if (!mounted) return;
      AppSnackBars.error(
        context,
        e.toString().replaceFirst('Exception: ', ''),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filterKey = _roleFilter ?? 'all';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        foregroundColor: AppColors.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Icon(
            CupertinoIcons.back,
            color: AppColors.dentalBlue,
            size: 22,
          ),
        ),
        title: const Text(
          'New Message',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -0.2,
            color: AppColors.navy,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: _kSeparator),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CupertinoSearchTextField(
                  controller: _search,
                  placeholder: 'Search',
                  backgroundColor: _kSearchFill,
                  style: const TextStyle(fontSize: 16, color: AppColors.navy),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: filterKey,
                    backgroundColor: const Color(0xFFE5E5EA),
                    thumbColor: Colors.white,
                    children: const {
                      'all': Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('All'),
                      ),
                      AppRoles.dentist: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Dentists'),
                      ),
                      AppRoles.laboratory: Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Laboratories'),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _roleFilter = value == 'all' ? null : value;
                        _users = _applyFilters(_allUsers);
                      });
                    },
                  ),
                ),
                if (_creating)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        ToothLoadingIndicator(
                          size: 16,
                          compact: true,
                          color: kToothLoaderBlue,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Opening conversation…',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AppSwitcher(
                        child: KeyedSubtree(
                          key: ValueKey(
                            _loading
                                ? 'loading'
                                : '$filterKey-${_users.length}',
                          ),
                          child: _loading
                          ? const ToothPageLoader(message: 'Loading contacts…')
                          : _users.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          CupertinoIcons.person_2,
                                          size: 36,
                                          color: Color(0xFFC7C7CC),
                                        ),
                                        SizedBox(height: 10),
                                        Text(
                                          'No contacts found.',
                                          style: TextStyle(
                                            color: AppColors.muted,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _users.length,
                                  itemBuilder: (context, i) {
                                    final user = _users[i];
                                    return _ContactTile(
                                      user: user,
                                      showDivider: i < _users.length - 1,
                                      onTap: _creating
                                          ? null
                                          : () => _select(user),
                                    );
                                  },
                                ),
                        ),
                      ),
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

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.user,
    required this.showDivider,
    this.onTap,
  });

  final UserProfile user;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.isNotEmpty
        ? user.displayName.characters.first.toUpperCase()
        : '?';
    final details = [
      if (user.clinicName != null && user.clinicName!.isNotEmpty)
        user.clinicName!,
      if (user.phone != null && user.phone!.isNotEmpty) user.phone!,
    ].join(' · ');
    final role = user.role == null || user.role!.isEmpty
        ? null
        : AppRoles.label(user.role);

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.dentalBlue.withValues(alpha: 0.08),
        highlightColor: AppColors.dentalBlue.withValues(alpha: 0.04),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor:
                        AppColors.dentalBlue.withValues(alpha: 0.14),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppColors.dentalBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.navy,
                            fontSize: 17,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (role != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      role,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 14,
                    color: Color(0xFFC7C7CC),
                  ),
                ],
              ),
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(left: 64),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: _kSeparator,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
