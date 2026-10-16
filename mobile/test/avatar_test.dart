import 'dart:convert';
import 'dart:typed_data';

import 'package:dental_lab_ai/core/api/api_client.dart';
import 'package:dental_lab_ai/core/l10n/app_localizations.dart';
import 'package:dental_lab_ai/core/l10n/locale_controller.dart';
import 'package:dental_lab_ai/core/widgets/user_avatar.dart';
import 'package:dental_lab_ai/features/chat/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('signup sends the photo as base64 with its type', () async {
    Map<String, dynamic>? sent;
    final api = ApiClient(
      baseUrl: 'http://test',
      httpClient: MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'email_confirmation_required': true}), 200);
      }),
    );
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await api.signUp(
      email: 'a@b.de',
      name: 'Dr A',
      password: 'x',
      role: 'dentist',
      avatar: (bytes: bytes, contentType: 'image/jpeg'),
    );
    expect(base64Decode(sent!['avatar'] as String), bytes);
    expect(sent!['avatar_content_type'], 'image/jpeg');
  });

  test('chat partner carries photo and lab', () {
    final u = UserProfile.fromJson({
      'id': 'd1',
      'name': 'Dr. Weiss',
      'avatar_url': '/api/media/avatars/d1.jpg',
      'lab_name': 'Dentallabor Süd',
    });
    expect(u.avatarUrl, '/api/media/avatars/d1.jpg');
    expect(u.labName, 'Dentallabor Süd');
  });

  testWidgets('no photo shows initials', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: UserAvatar(name: 'Max Mustermann')));
    expect(find.text('MM'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('cropper returns the centred square of a wide photo', (tester) async {
    // 400x200: left half red, right half blue; the centred square straddles both.
    final src = img.Image(width: 400, height: 200);
    for (var x = 0; x < 400; x++) {
      for (var y = 0; y < 200; y++) {
        src.setPixelRgb(x, y, x < 200 ? 255 : 0, 0, x < 200 ? 0 : 255);
      }
    }
    Uint8List? out;
    await tester.pumpWidget(LocaleScope(controller: LocaleController(), child: MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => out = await cropProfilePhoto(context, img.encodePng(src)),
          child: const Text('go'),
        ),
      ),
    )));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppLocalizations('de').tr('avatar.cropDone')));
    await tester.pumpAndSettle();
    final cropped = img.decodeJpg(out!)!;
    expect(cropped.width, cropped.height);
    expect(cropped.width, 200);
    // Left quarter is red, right quarter blue: the crop is centred.
    expect(cropped.getPixel(20, 100).r, greaterThan(200));
    expect(cropped.getPixel(180, 100).b, greaterThan(200));
  });
}
