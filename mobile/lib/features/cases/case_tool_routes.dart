import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/l10n/app_localizations.dart';
import '../../core/navigation/app_page_routes.dart';
import '../../core/session/patient_session.dart';
import '../../core/theme/app_theme.dart';
import '../scans/scans_page.dart';
import '../shade/shade_page.dart';
import '../shapes/shape_overlay_page.dart';

/// Open Scans / Shade / Smile for [patientId] (sidebar page when the shell provides one, else a pushed route for lab Review).
Future<void> openCaseTool(
  BuildContext context, {
  required ApiClient api,
  required PatientSession patients,
  required String patientId,
  required String tool, // scan | shade | smile
}) async {
  await patients.ensureLoaded();
  final match = patients.patients.where((p) => patients.pidOf(p) == patientId);
  if (match.isNotEmpty) {
    patients.select(match.first);
  } else {
    patients.select({'id': patientId});
  }
  if (!context.mounted) return;
  final goToSidebar = patients.openToolHandler;
  if (goToSidebar != null) {
    // Close the patient sheet if it's a popup; the embedded view stays.
    final route = ModalRoute.of(context);
    if (route != null && !route.isFirst) Navigator.of(context).pop();
    goToSidebar(tool);
    return;
  }
  final loc = AppLocalizations.of(context);
  final (title, page) = switch (tool) {
    'shade' => (
        loc.navShade,
        ShadePage(api: api, patientSession: patients, active: true),
      ),
    'smile' => (
        loc.navSmilePreview,
        ShapeOverlayPage(api: api, patientSession: patients, active: true),
      ),
    _ => (
        loc.navScans,
        ScansPage(api: api, patientSession: patients, active: true),
      ),
  };
  await Navigator.of(context).push<void>(
    AppPageRoutes.cupertino(
      Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(title: Text(title), backgroundColor: AppColors.surface),
        body: page,
      ),
    ),
  );
}
