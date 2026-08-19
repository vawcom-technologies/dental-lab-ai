import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/api/api_client.dart';
import 'core/auth/session_coordinator.dart';
import 'core/l10n/locale_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/touchable.dart';
import 'features/auth/login_screen.dart';
import 'shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeController = LocaleController();
  await localeController.load();
  final api = ApiClient();
  runApp(DentalLabApp(localeController: localeController, api: api));
}

class DentalLabApp extends StatefulWidget {
  const DentalLabApp({
    super.key,
    required this.localeController,
    required this.api,
  });

  final LocaleController localeController;
  final ApiClient api;

  @override
  State<DentalLabApp> createState() => _DentalLabAppState();
}

class _DentalLabAppState extends State<DentalLabApp> {
  bool _ready = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final ok = await widget.api.tryRestoreSession();
    if (!mounted) return;
    setState(() {
      _signedIn = ok;
      _ready = true;
    });
  }

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
            home: !_ready
                ? const _SessionRestoreSplash()
                : _signedIn
                    ? AppShell(
                        api: widget.api,
                        dentistName: widget.api.userName ?? 'Dentist',
                      )
                    : LoginScreen(api: widget.api),
          );
        },
      ),
    );
  }
}

class _SessionRestoreSplash extends StatelessWidget {
  const _SessionRestoreSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CupertinoActivityIndicator(radius: 14),
      ),
    );
  }
}
