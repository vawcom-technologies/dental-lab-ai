import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/api_client.dart';
import 'core/auth/session_coordinator.dart';
import 'core/l10n/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/touchable.dart';
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
    final theme = AppTheme.light();
    final cupertino = AppTheme.cupertino();

    return LocaleScope(
      controller: widget.localeController,
      child: ListenableBuilder(
        listenable: widget.localeController,
        builder: (context, _) {
          return MaterialApp(
            title: 'Elite Dentist Pro',
            debugShowCheckedModeBanner: false,
            navigatorKey: SessionCoordinator.navigatorKey,
            theme: theme,
            scrollBehavior: const EliteScrollBehavior(),
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
            builder: (context, child) {
              return CupertinoTheme(
                data: cupertino,
                child: DefaultTextStyle(
                  style: AppFonts.style(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: AppColors.text,
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: LoginScreen(api: _api),
          );
        },
      ),
    );
  }
}
