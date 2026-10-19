import 'dart:convert';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/errors/user_facing_error.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/features/chat/services/chat_api_service.dart';
import 'package:dental_lab_ai/features/chat/services/chat_socket_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('HTTP 403 CANNOT_MESSAGE becomes CannotMessage', () async {
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((_) async =>
          http.Response(jsonEncode({'code': 'CANNOT_MESSAGE', 'detail': 'whatever'}), 403)),
    );
    final call = ChatApiService(api).getOrCreateConversation('u2');
    await expectLater(call, throwsA(isA<CannotMessage>()));
    try {
      await call;
    } catch (e) {
      expect(friendlyError(e), AppLocalizations.current.tr('chat.cantMessage'));
    }
  });

  test('socket CANNOT_MESSAGE reports the conversation, matched by code', () async {
    final socket = ChatSocketService();
    final blocked = <String>[];
    final sub = socket.onBlocked.listen(blocked.add);
    socket.handleFrame(jsonEncode({'type': 'error', 'code': 'CANNOT_MESSAGE', 'detail': 'x', 'conversation_id': 'c7'}));
    // Same words without the code: just an error, not a block.
    socket.handleFrame(jsonEncode({'type': 'error', 'detail': "You can't message this person."}));
    await Future<void>.delayed(Duration.zero);
    expect(blocked, ['c7']);
    await sub.cancel();
  });
}
