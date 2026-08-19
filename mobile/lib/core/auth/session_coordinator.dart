import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../features/auth/login_screen.dart';
import '../api/api_client.dart';
import '../l10n/app_localizations.dart';
import '../navigation/app_page_routes.dart';
import '../offline/sync_queue.dart';
import '../widgets/app_snackbar.dart';

/// Global session-expired handling + root navigator for forced re-login.
class SessionCoordinator {
  SessionCoordinator._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static bool _handling = false;

  /// Paths that must never trigger a forced logout (wrong password, etc.).
  static bool isAuthExemptUri(Uri url) {
    final path = url.path.toLowerCase();
    return path.contains('/api/auth/signin') ||
        path.contains('/api/auth/login') ||
        path.contains('/api/auth/signup') ||
        path.contains('/api/auth/register') ||
        path.contains('/api/auth/forgot') ||
        path.contains('/api/auth/reset') ||
        path.contains('/api/auth/refresh') ||
        path.contains('/api/auth/logout');
  }

  /// Clear auth and send the user to [LoginScreen] once.
  static void onUnauthorized(ApiClient api) {
    if (_handling) return;
    // No active session → already on login / never signed in.
    if (api.token == null || api.token!.isEmpty) return;

    _handling = true;
    api.clearHttpCache();
    unawaited(LocalEncryptedStore.clearAll());
    api.logout();

    void navigate() {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        _handling = false;
        return;
      }
      nav.pushAndRemoveUntil(
        AppPageRoutes.fade(LoginScreen(api: api)),
        (_) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          AppSnackBars.error(
            ctx,
            AppLocalizations.of(ctx).errSessionExpired,
          );
        }
        // Allow a future expiry after the user signs in again.
        Future<void>.delayed(const Duration(milliseconds: 500), () {
          _handling = false;
        });
      });
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild = phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;
    if (duringBuild) {
      WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
    } else {
      navigate();
    }
  }

  /// Manual sign-out from Settings / Profile (same stack reset).
  static void signOut(ApiClient api, {String? message}) {
    unawaited(LocalEncryptedStore.clearAll());
    unawaited(api.signOutFull());
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.pushAndRemoveUntil(
      AppPageRoutes.fade(LoginScreen(api: api)),
      (_) => false,
    );
    if (message != null && message.isNotEmpty) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        AppSnackBars.success(ctx, message);
      }
    }
  }
}
