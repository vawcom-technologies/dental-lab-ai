import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/chat_models.dart';

/// Persistent WebSocket client for `/ws/chat?token=...`.
///
/// Outbound: `send_message`, `mark_as_read`
/// Inbound: `new_message`, `messages_read`, `error`
class ChatSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  String? _token;
  String? _httpBaseUrl;
  bool _manualClose = false;
  bool _connecting = false;
  int _attempt = 0;

  final _messages = StreamController<Message>.broadcast();
  final _reads = StreamController<MessagesReadEvent>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  Stream<Message> get onMessage => _messages.stream;
  Stream<MessagesReadEvent> get onRead => _reads.stream;
  Stream<String> get onError => _errors.stream;
  Stream<bool> get onConnectionChanged => _connection.stream;

  bool get isConnected => _channel != null && !_connecting;

  /// [httpBaseUrl] e.g. `http://127.0.0.1:8000`
  Future<void> connect({
    required String httpBaseUrl,
    required String jwtToken,
  }) async {
    _httpBaseUrl = httpBaseUrl;
    _token = jwtToken;
    _manualClose = false;
    await _open();
  }

  Future<void> disconnect() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _tearDown();
    _connection.add(false);
  }

  void sendMessage({
    required String conversationId,
    required String content,
    String? replyToMessageId,
    String? mediaUrl,
  }) {
    _send({
      'type': 'send_message',
      'action': 'send_message',
      'conversation_id': conversationId,
      'content': content,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (mediaUrl != null) 'media_url': mediaUrl,
    });
  }

  void markAsRead(String conversationId) {
    _send({
      'type': 'mark_as_read',
      'action': 'mark_as_read',
      'conversation_id': conversationId,
    });
  }

  Future<void> _open() async {
    final token = _token;
    final base = _httpBaseUrl;
    if (token == null || token.isEmpty || base == null) return;
    if (_connecting) return;

    await _tearDown();
    _connecting = true;

    final wsBase = base
        .replaceFirst(RegExp(r'^https://', caseSensitive: false), 'wss://')
        .replaceFirst(RegExp(r'^http://', caseSensitive: false), 'ws://');
    final uri = Uri.parse('$wsBase/ws/chat').replace(
      queryParameters: {'token': token},
    );

    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready;
      _attempt = 0;
      _connecting = false;
      _connection.add(true);

      _sub = channel.stream.listen(
        _onData,
        onError: (Object e, StackTrace st) {
          debugPrint('ChatSocket error: $e');
          _scheduleReconnect();
        },
        onDone: () {
          _connection.add(false);
          if (!_manualClose) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('ChatSocket connect failed: $e');
      _connecting = false;
      _connection.add(false);
      if (!_manualClose) _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    try {
      final raw = data is String ? data : data.toString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final type = '${map['type'] ?? map['action'] ?? ''}';

      switch (type) {
        case 'new_message':
          final msgRaw = map['message'];
          if (msgRaw is Map) {
            _messages.add(
              Message.fromJson(Map<String, dynamic>.from(msgRaw)),
            );
          }
          break;
        case 'messages_read':
          _reads.add(MessagesReadEvent.fromJson(map));
          break;
        case 'error':
          final detail = '${map['detail'] ?? 'WebSocket error'}';
          _errors.add(detail);
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('ChatSocket parse error: $e');
    }
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      _errors.add('Not connected to chat');
      return;
    }
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      _errors.add('Failed to send: $e');
    }
  }

  void _scheduleReconnect() {
    if (_manualClose) return;
    _reconnectTimer?.cancel();
    _attempt += 1;
    final seconds = min(30, pow(2, min(_attempt, 5)).toInt());
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      if (!_manualClose) _open();
    });
  }

  Future<void> _tearDown() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _connecting = false;
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _reads.close();
    await _errors.close();
    await _connection.close();
  }
}
