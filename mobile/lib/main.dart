import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/api_client.dart';
import 'core/l10n/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeController = LocaleController();
  await localeController.load();
  runApp(DentalLabApp(localeController: localeController));
}

class DentalLabApp extends StatefulWidget {
  const DentalLabApp({super.key, required this.localeController});

  final LocaleController localeController;

  @override
  State<DentalLabApp> createState() => _DentalLabAppState();
}

class _DentalLabAppState extends State<DentalLabApp> {
  final ApiClient _api = ApiClient();

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: widget.localeController,
      child: ListenableBuilder(
        listenable: widget.localeController,
        builder: (context, _) {
          return MaterialApp(
            title: 'Elite Dent Pro',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            locale: widget.localeController.locale,
            supportedLocales: const [
              Locale('en'),
              Locale('de'),
            ],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: LoginScreen(api: _api),
          );
        },
      ),
    );
  }
}
