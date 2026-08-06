import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/app_roles.dart';
import '../models/chat_models.dart';
import '../services/chat_api_service.dart';
import '../services/chat_socket_service.dart';

/// Central chat state: inbox, active thread, compose/reply, socket lifecycle.
class ChatController extends ChangeNotifier {
  ChatController({
    required ApiClient api,
    ChatApiService? apiService,
    ChatSocketService? socketService,
  })  : _api = api,
        _apiService = apiService ?? ChatApiService(api),
        _socket = socketService ?? ChatSocketService();

  final ApiClient _api;
  final ChatApiService _apiService;
  final ChatSocketService _socket;

  ApiClient get apiClient => _api;
  ChatApiService get apiService => _apiService;

  final List<Conversation> _conversations = [];
  final List<Message> _messages = []; // chronological (oldest → newest)
  Conversation? _active;
  Message? _replyTo;
  String _inboxQuery = '';
  /// True only while [ChatScreen] is mounted / visible.
  bool _viewingThread = false;

  bool _loadingInbox = false;
  bool _loadingMessages = false;
  bool _loadingOlder = false;
  bool _sending = false;
  bool _socketConnected = false;
  bool _hasMore = false;
  String? _error;
  String? _threadError;

  StreamSubscription<Message>? _msgSub;
  StreamSubscription<MessagesReadEvent>? _readSub;
  StreamSubscription<String>? _errSub;
  StreamSubscription<bool>? _connSub;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<Message> get messages => List.unmodifiable(_messages);
  Conversation? get activeConversation => _active;
  Message? get replyTo => _replyTo;
  String get inboxQuery => _inboxQuery;
  bool get viewingThread => _viewingThread;
  bool get loadingInbox => _loadingInbox;
  bool get loadingMessages => _loadingMessages;
  bool get loadingOlder => _loadingOlder;
  bool get sending => _sending;
  bool get socketConnected => _socketConnected;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String? get threadError => _threadError;
  String? get currentUserId => _api.userId;

  int get totalUnread =>
      _conversations.fold<int>(0, (sum, c) => sum + c.unreadCount);

  List<Conversation> get visibleConversations {
    final q = _inboxQuery.trim().toLowerCase();
    var rows = [..._conversations];
    if (q.isNotEmpty) {
      rows = rows.where((c) {
        final p = c.partner;
        final blob = [
          p.displayName,
          p.email,
          p.clinicName,
          p.phone,
          p.role,
          AppRoles.label(p.role),
          p.subtitle,
          c.lastMessage?.content,
        ].whereType<String>().join(' ').toLowerCase();
        return blob.contains(q);
      }).toList();
    }
    rows.sort((a, b) {
      final au = a.updatedAt ?? a.lastMessage?.createdAt ?? a.createdAt;
      final bu = b.updatedAt ?? b.lastMessage?.createdAt ?? b.createdAt;
      if (au == null && bu == null) return 0;
      if (au == null) return 1;
      if (bu == null) return -1;
      return bu.compareTo(au);
    });
    return rows;
  }

  Future<void> start() async {
    _bindSocketStreams();
    await Future.wait([
      loadInbox(),
      _connectSocket(),
    ]);
  }

  Future<void> _connectSocket() async {
    final token = _api.token;
    if (token == null || token.isEmpty) return;
    try {
      await _socket.connect(httpBaseUrl: _api.baseUrl, jwtToken: token);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void _bindSocketStreams() {
    _msgSub ??= _socket.onMessage.listen(_onSocketMessage);
    _readSub ??= _socket.onRead.listen(_onSocketRead);
    _errSub ??= _socket.onError.listen((detail) {
      _threadError = detail;
      notifyListeners();
    });
    _connSub ??= _socket.onConnectionChanged.listen((ok) {
      _socketConnected = ok;
      notifyListeners();
    });
  }

  Future<void> loadInbox() async {
    _loadingInbox = true;
    _error = null;
    notifyListeners();
    try {
      final list = await _apiService.fetchConversations();
      _conversations
        ..clear()
        ..addAll(list);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loadingInbox = false;
      notifyListeners();
    }
  }

  void setInboxQuery(String value) {
    if (value == _inboxQuery) return;
    _inboxQuery = value;
    notifyListeners();
  }

  Future<void> openConversation(Conversation conversation) async {
    if (_active?.id == conversation.id && _messages.isNotEmpty) {
      if (_viewingThread) markActiveAsRead();
      return;
    }
    _active = conversation;
    _replyTo = null;
    _messages.clear();
    _hasMore = false;
    _threadError = null;
    _loadingMessages = true;
    notifyListeners();

    try {
      final page = await _apiService.fetchMessages(conversation.id);
      // API returns newest-first → reverse for chronological list.
      _messages.addAll(page.items.reversed);
      _hasMore = page.hasMore;
      if (_viewingThread) markActiveAsRead();
    } catch (e) {
      _threadError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loadingMessages = false;
      notifyListeners();
    }
  }

  /// Call when ChatScreen is shown/hidden. Read receipts only while visible.
  void setViewingThread(bool viewing) {
    if (_viewingThread == viewing) return;
    _viewingThread = viewing;
    if (viewing) {
      markActiveAsRead();
    }
    notifyListeners();
  }

  void clearActiveConversation() {
    _active = null;
    _messages.clear();
    _replyTo = null;
    _viewingThread = false;
    _threadError = null;
    notifyListeners();
  }

  Future<Conversation> openOrCreateWith(String targetUserId) async {
    _error = null;
    notifyListeners();
    try {
      final conversation =
          await _apiService.getOrCreateConversation(targetUserId);
      final i = _conversations.indexWhere((c) => c.id == conversation.id);
      if (i >= 0) {
        _conversations[i] = conversation;
      } else {
        _conversations.insert(0, conversation);
      }
      await openConversation(conversation);
      return conversation;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      rethrow;
    }
  }

  Future<void> loadOlderMessages() async {
    final active = _active;
    if (active == null || !_hasMore || _loadingOlder || _messages.isEmpty) {
      return;
    }
    final oldest = _messages.first.createdAt;
    if (oldest == null) return;

    _loadingOlder = true;
    notifyListeners();
    try {
      final page = await _apiService.fetchMessages(
        active.id,
        before: oldest.toUtc().toIso8601String(),
      );
      final older = page.items.reversed.toList();
      _messages.insertAll(0, older);
      _hasMore = page.hasMore;
    } catch (e) {
      _threadError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _loadingOlder = false;
      notifyListeners();
    }
  }

  void setReplyTo(Message? message) {
    _replyTo = message;
    notifyListeners();
  }

  void clearReply() {
    if (_replyTo == null) return;
    _replyTo = null;
    notifyListeners();
  }

  void sendText(String raw) {
    final active = _active;
    final content = raw.trim();
    if (active == null || content.isEmpty || _sending) return;

    _sending = true;
    _threadError = null;
    notifyListeners();

    try {
      _socket.sendMessage(
        conversationId: active.id,
        content: content,
        replyToMessageId: _replyTo?.id,
      );
      _replyTo = null;
    } catch (e) {
      _threadError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void markActiveAsRead() {
    if (!_viewingThread) return;
    final active = _active;
    if (active == null) return;
    _socket.markAsRead(active.id);
    _patchConversation(
      active.id,
      (c) => c.copyWith(unreadCount: 0),
    );
  }

  void _onSocketMessage(Message message) {
    final me = currentUserId;
    final isMine = me != null && message.senderId == me;
    final isOpenAndViewing =
        _viewingThread && _active?.id == message.conversationId;

    // Upsert into open thread only while the chat UI is visible
    if (isOpenAndViewing) {
      final exists = _messages.any((m) => m.id == message.id);
      if (!exists) {
        _messages.add(message);
      }
      if (!isMine) {
        _socket.markAsRead(message.conversationId);
      }
    } else if (_active?.id == message.conversationId && !isMine) {
      // Thread selected but not viewing — still append locally if loaded,
      // but do NOT mark as read.
      final exists = _messages.any((m) => m.id == message.id);
      if (!exists) {
        _messages.add(message);
      }
    }

    // Update inbox row
    final idx =
        _conversations.indexWhere((c) => c.id == message.conversationId);
    if (idx >= 0) {
      final existing = _conversations[idx];
      var unread = existing.unreadCount;
      if (!isMine) {
        if (isOpenAndViewing) {
          unread = 0;
        } else {
          unread += 1;
        }
      }
      final updated = existing.copyWith(
        lastMessage: message,
        unreadCount: unread,
        updatedAt: message.createdAt ?? DateTime.now().toUtc(),
      );
      _conversations.removeAt(idx);
      _conversations.insert(0, updated);
      if (_active?.id == updated.id) {
        _active = updated;
      }
    } else {
      // Unknown room — refresh inbox
      loadInbox();
    }
    notifyListeners();
  }

  void _onSocketRead(MessagesReadEvent event) {
    final me = currentUserId;
    final readAt = event.readAt ?? DateTime.now().toUtc();

    if (_active?.id == event.conversationId) {
      for (var i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        final match = event.messageIds.isEmpty
            ? (me != null && m.senderId == me && m.readAt == null)
            : event.messageIds.contains(m.id);
        if (match) {
          _messages[i] = m.copyWith(readAt: readAt);
        }
      }
    }

    if (event.readerId == me) {
      _patchConversation(
        event.conversationId,
        (c) => c.copyWith(unreadCount: 0),
      );
    }
    notifyListeners();
  }

  void _patchConversation(
    String id,
    Conversation Function(Conversation) transform,
  ) {
    final i = _conversations.indexWhere((c) => c.id == id);
    if (i < 0) return;
    _conversations[i] = transform(_conversations[i]);
    if (_active?.id == id) {
      _active = _conversations[i];
    }
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _readSub?.cancel();
    _errSub?.cancel();
    _connSub?.cancel();
    _socket.dispose();
    super.dispose();
  }
}
