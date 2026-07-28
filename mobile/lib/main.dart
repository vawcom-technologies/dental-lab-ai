import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DentalLabApp());
}

class DentalLabApp extends StatelessWidget {
  const DentalLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient();
    return MaterialApp(
      title: 'Elite Dent Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: LoginScreen(api: api),
    );
  }
}
