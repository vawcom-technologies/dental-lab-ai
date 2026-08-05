/// Immutable chat domain models for 1-to-1 messaging.
library;

class UserProfile {
  const UserProfile({
    required this.id,
    this.name,
    this.email,
    this.role,
    this.clinicName,
    this.phone,
  });

  final String id;
  final String? name;
  final String? email;
  final String? role;
  final String? clinicName;
  final String? phone;

  String get displayName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e;
    return 'User';
  }

  String get subtitle {
    final parts = <String>[
      if (clinicName != null && clinicName!.trim().isNotEmpty) clinicName!.trim(),
      if (role != null && role!.trim().isNotEmpty) role!.trim(),
    ];
    return parts.join(' · ');
  }

  factory UserProfile.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const UserProfile(id: '');
    }
    return UserProfile(
      id: '${json['id'] ?? ''}',
      name: _optString(json['name']),
      email: _optString(json['email']),
      role: _optString(json['role']),
      clinicName: _optString(json['clinic_name']),
      phone: _optString(json['phone']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'clinic_name': clinicName,
        'phone': phone,
      };
}

class ParentMessage {
  const ParentMessage({
    required this.id,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    this.createdAt,
  });

  final String id;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final DateTime? createdAt;

  factory ParentMessage.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ParentMessage(id: '', senderId: '', content: '');
    }
    return ParentMessage(
      id: '${json['id'] ?? ''}',
      senderId: '${json['sender_id'] ?? ''}',
      content: '${json['content'] ?? ''}',
      mediaUrl: _optString(json['media_url']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sender_id': senderId,
        'content': content,
        'media_url': mediaUrl,
        'created_at': createdAt?.toIso8601String(),
      };
}

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    this.replyToMessageId,
    this.replyTo,
    this.readAt,
    this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final String? replyToMessageId;
  final ParentMessage? replyTo;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? mediaUrl,
    String? replyToMessageId,
    ParentMessage? replyTo,
    DateTime? readAt,
    bool clearReadAt = false,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyTo: replyTo ?? this.replyTo,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    final replyRaw = json['reply_to'];
    return Message(
      id: '${json['id'] ?? ''}',
      conversationId: '${json['conversation_id'] ?? ''}',
      senderId: '${json['sender_id'] ?? ''}',
      content: '${json['content'] ?? ''}',
      mediaUrl: _optString(json['media_url']),
      replyToMessageId: _optString(json['reply_to_message_id']),
      replyTo: replyRaw is Map<String, dynamic>
          ? ParentMessage.fromJson(replyRaw)
          : replyRaw is Map
              ? ParentMessage.fromJson(Map<String, dynamic>.from(replyRaw))
              : null,
      readAt: _parseDate(json['read_at']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversation_id': conversationId,
        'sender_id': senderId,
        'content': content,
        'media_url': mediaUrl,
        'reply_to_message_id': replyToMessageId,
        'reply_to': replyTo?.toJson(),
        'read_at': readAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
      };
}

class Conversation {
  const Conversation({
    required this.id,
    required this.userA,
    required this.userB,
    required this.partner,
    this.lastMessage,
    this.unreadCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String userA;
  final String userB;
  final UserProfile partner;
  final Message? lastMessage;
  final int unreadCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Conversation copyWith({
    String? id,
    String? userA,
    String? userB,
    UserProfile? partner,
    Message? lastMessage,
    bool clearLastMessage = false,
    int? unreadCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      userA: userA ?? this.userA,
      userB: userB ?? this.userB,
      partner: partner ?? this.partner,
      lastMessage:
          clearLastMessage ? null : (lastMessage ?? this.lastMessage),
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final partnerRaw = json['partner'];
    final lastRaw = json['last_message'];
    return Conversation(
      id: '${json['id'] ?? ''}',
      userA: '${json['user_a'] ?? ''}',
      userB: '${json['user_b'] ?? ''}',
      partner: partnerRaw is Map<String, dynamic>
          ? UserProfile.fromJson(partnerRaw)
          : partnerRaw is Map
              ? UserProfile.fromJson(Map<String, dynamic>.from(partnerRaw))
              : const UserProfile(id: ''),
      lastMessage: lastRaw is Map<String, dynamic>
          ? Message.fromJson(lastRaw)
          : lastRaw is Map
              ? Message.fromJson(Map<String, dynamic>.from(lastRaw))
              : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_a': userA,
        'user_b': userB,
        'partner': partner.toJson(),
        'last_message': lastMessage?.toJson(),
        'unread_count': unreadCount,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };
}

class PaginatedMessagesResponse {
  const PaginatedMessagesResponse({
    required this.items,
    required this.hasMore,
  });

  final List<Message> items;
  final bool hasMore;

  factory PaginatedMessagesResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <Message>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          items.add(Message.fromJson(item));
        } else if (item is Map) {
          items.add(Message.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return PaginatedMessagesResponse(
      items: items,
      hasMore: json['has_more'] == true,
    );
  }
}

class MessagesReadEvent {
  const MessagesReadEvent({
    required this.conversationId,
    required this.readerId,
    required this.messageIds,
    this.readAt,
  });

  final String conversationId;
  final String readerId;
  final List<String> messageIds;
  final DateTime? readAt;

  factory MessagesReadEvent.fromJson(Map<String, dynamic> json) {
    final idsRaw = json['message_ids'];
    final ids = <String>[];
    if (idsRaw is List) {
      for (final id in idsRaw) {
        ids.add('$id');
      }
    }
    return MessagesReadEvent(
      conversationId: '${json['conversation_id'] ?? ''}',
      readerId: '${json['reader_id'] ?? ''}',
      messageIds: ids,
      readAt: _parseDate(json['read_at']),
    );
  }
}

String? _optString(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
