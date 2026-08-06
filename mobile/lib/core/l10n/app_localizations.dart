import 'package:flutter/widgets.dart';

import 'locale_controller.dart';

/// Typed EN/DE strings for Elite Dent. Use [AppLocalizations.of].
class AppLocalizations {
  AppLocalizations(this.code);

  final String code;

  static AppLocalizations of(BuildContext context) {
    return AppLocalizations(LocaleScope.of(context).code);
  }

  String _t(String key) {
    if (code == 'de') return _de[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }

  String tr(String key) => _t(key);

  // ── Nav ──────────────────────────────────────────────────────────────────
  String get navDashboard => _t('nav.dashboard');
  String get navPatients => _t('nav.patients');
  String get navNewPatient => _t('nav.newPatient');
  String get navCamera => _t('nav.camera');
  String get navScans => _t('nav.scans');
  String get navShade => _t('nav.shade');
  String get navSmilePreview => _t('nav.smilePreview');
  String get navScanBody => _t('nav.scanBody');
  String get navMessages => _t('nav.messages');
  String get navLaboratories => _t('nav.laboratories');
  String get navNotifications => _t('nav.notifications');
  String get navReports => _t('nav.reports');
  String get navSettings => _t('nav.settings');
  String get navProfile => _t('nav.profile');
  String get proEdition => _t('proEdition');

  // ── Common ───────────────────────────────────────────────────────────────
  String get refresh => _t('common.refresh');
  String get save => _t('common.save');
  String get cancel => _t('common.cancel');
  String get ok => _t('common.ok');
  String get comingSoon => _t('common.comingSoon');
  String get comingSoonBody => _t('common.comingSoonBody');
  String get loading => _t('common.loading');
  String get online => _t('common.online');
  String get offline => _t('common.offline');
  String get preferenceSaved => _t('common.preferenceSaved');
  String get addPatient => _t('common.addPatient');
  String get searchPatients => _t('common.searchPatients');
  String get noPatientsYet => _t('common.noPatientsYet');

  // ── Auth ─────────────────────────────────────────────────────────────────
  String get signIn => _t('auth.signIn');
  String get signInSubtitle => _t('auth.signInSubtitle');
  String get email => _t('auth.email');
  String get password => _t('auth.password');
  String get createProfile => _t('auth.createProfile');
  String get useDemo => _t('auth.useDemo');
  String get loginHero => _t('auth.hero');
  String get registerTitle => _t('auth.registerTitle');
  String get registerSubtitle => _t('auth.registerSubtitle');
  String get fullName => _t('auth.fullName');
  String get clinic => _t('auth.clinic');
  String get phone => _t('auth.phone');
  String get confirmPassword => _t('auth.confirmPassword');
  String get roleDentist => _t('auth.roleDentist');
  String get roleLaboratory => _t('auth.roleLaboratory');
  @Deprecated('Use roleLaboratory')
  String get roleLab => roleLaboratory;
  String get alreadyHaveAccount => _t('auth.alreadyHaveAccount');
  String get errNameEmailPassword => _t('auth.errNameEmailPassword');
  String get errAllFieldsRequired => _t('auth.errAllFieldsRequired');
  String get errPasswordShort => _t('auth.errPasswordShort');
  String get errPasswordMismatch => _t('auth.errPasswordMismatch');
  String get errPhoneInvalid => _t('auth.errPhoneInvalid');
  String get errEmailRequired => _t('auth.errEmailRequired');
  String get forgotPassword => _t('auth.forgotPassword');
  String get forgotPasswordTitle => _t('auth.forgotPasswordTitle');
  String get forgotPasswordSubtitle => _t('auth.forgotPasswordSubtitle');
  String get sendResetLink => _t('auth.sendResetLink');
  String get backToSignIn => _t('auth.backToSignIn');
  String get emailConfirmationRequired => _t('auth.emailConfirmationRequired');

  // ── Settings ─────────────────────────────────────────────────────────────
  String get settingsTitle => _t('settings.title');
  String get settingsSubtitle => _t('settings.subtitle');
  String get settingsOfflineTitle => _t('settings.offlineTitle');
  String get settingsOfflineSubtitle => _t('settings.offlineSubtitle');
  String get settingsConnection => _t('settings.connection');
  String get settingsPending => _t('settings.pending');
  String get settingsAutoSync => _t('settings.autoSync');
  String get settingsAutoSyncSub => _t('settings.autoSyncSub');
  String get settingsSyncNow => _t('settings.syncNow');
  String get settingsSyncing => _t('settings.syncing');
  String get settingsClearCache => _t('settings.clearCache');
  String get settingsClearing => _t('settings.clearing');
  String get settingsClearCacheTitle => _t('settings.clearCacheTitle');
  String get settingsClearCacheBody => _t('settings.clearCacheBody');
  String get settingsNotificationsTitle => _t('settings.notificationsTitle');
  String get settingsNotificationsSub => _t('settings.notificationsSub');
  String get settingsNotifyMessages => _t('settings.notifyMessages');
  String get settingsNotifyMessagesSub => _t('settings.notifyMessagesSub');
  String get settingsNotifyCase => _t('settings.notifyCase');
  String get settingsNotifyCaseSub => _t('settings.notifyCaseSub');
  String get settingsNotifyScan => _t('settings.notifyScan');
  String get settingsNotifyScanSub => _t('settings.notifyScanSub');
  String get settingsLanguageTitle => _t('settings.languageTitle');
  String get settingsLanguageSub => _t('settings.languageSub');
  String get settingsAppLanguage => _t('settings.appLanguage');
  String get settingsAiTitle => _t('settings.aiTitle');
  String get settingsAiSub => _t('settings.aiSub');
  String get settingsAutoShade => _t('settings.autoShade');
  String get settingsAutoShadeSub => _t('settings.autoShadeSub');
  String get settingsAutoQuality => _t('settings.autoQuality');
  String get settingsAutoQualitySub => _t('settings.autoQualitySub');
  String get settingsAutoScanBody => _t('settings.autoScanBody');
  String get settingsAutoScanBodySub => _t('settings.autoScanBodySub');
  String get settingsAboutTitle => _t('settings.aboutTitle');
  String get settingsAboutSub => _t('settings.aboutSub');
  String get settingsVersion => _t('settings.version');
  String get settingsApi => _t('settings.api');
  String get settingsBaseUrl => _t('settings.baseUrl');
  String get settingsPrivacyNote => _t('settings.privacyNote');
  String get settingsOfflineError => _t('settings.offlineError');
  String get settingsQueueEmpty => _t('settings.queueEmpty');
  String settingsSynced(int n) =>
      _t('settings.synced').replaceAll('{n}', '$n');
  String settingsCleared(int n) =>
      _t('settings.cleared').replaceAll('{n}', '$n');
  String get settingsLoadError => _t('settings.loadError');
  String get languageEnglish => _t('settings.english');
  String get languageGerman => _t('settings.german');

  // ── Profile ──────────────────────────────────────────────────────────────
  String get profileTitle => _t('profile.title');
  String get profileSubtitle => _t('profile.subtitle');
  String get signOut => _t('profile.signOut');
  String get saveProfile => _t('profile.saveProfile');
  String get saving => _t('profile.saving');
  String get security => _t('profile.security');
  String get securitySub => _t('profile.securitySub');
  String get currentPassword => _t('profile.currentPassword');
  String get newPassword => _t('profile.newPassword');
  String get confirmNewPassword => _t('profile.confirmNewPassword');
  String get updatePassword => _t('profile.updatePassword');
  String get updating => _t('profile.updating');
  String get accountInfo => _t('profile.accountInfo');
  String get role => _t('profile.role');
  String get created => _t('profile.created');
  String get lastLogin => _t('profile.lastLogin');
  String get profileSaved => _t('profile.saved');
  String get passwordUpdated => _t('profile.passwordUpdated');
  String get changePasswordSuccessBody => _t('profile.changePasswordSuccessBody');
  String get errNameEmailRequired => _t('profile.errNameEmail');
  String get errEnterPasswords => _t('profile.errEnterPasswords');
  String get errNewPasswordShort => _t('profile.errNewPasswordShort');
  String get errNewPasswordMismatch => _t('profile.errNewPasswordMismatch');
  String get clinicHint => _t('profile.clinicHint');

  // ── Dashboard ────────────────────────────────────────────────────────────
  String goodMorning(String name) =>
      _t('dash.goodMorning').replaceAll('{name}', name);
  String goodAfternoon(String name) =>
      _t('dash.goodAfternoon').replaceAll('{name}', name);
  String goodEvening(String name) =>
      _t('dash.goodEvening').replaceAll('{name}', name);
  String get dashLoading => _t('dash.loading');
  String get dashNoCases => _t('dash.noCases');
  String get dashCompletedCases => _t('dash.completedCases');
  String get dashAvgProcessing => _t('dash.avgProcessing');
  String get dashPendingScans => _t('dash.pendingScans');
  String get dashRejectedScans => _t('dash.rejectedScans');
  String get dashRecentCases => _t('dash.recentCases');
  String get dashRecentActivity => _t('dash.recentActivity');
  String get dashStartScan => _t('dash.startScan');
  String get dashNoPatientsHint => _t('dash.noPatientsHint');
  String get dashBasedOnCompleted => _t('dash.basedOnCompleted');
  String get dashNoneInProgress => _t('dash.noneInProgress');
  String get dashNoRejections => _t('dash.noRejections');
  String get dashNeedRescan => _t('dash.needRescan');
  String get dashNoCasesEmpty => _t('dash.noCasesEmpty');
  String get dashActivityEmpty => _t('dash.activityEmpty');
  String get colCaseId => _t('dash.colCaseId');
  String get colPatient => _t('dash.colPatient');
  String get colDentist => _t('dash.colDentist');
  String get colStatus => _t('dash.colStatus');
  String get colUpdated => _t('dash.colUpdated');

  // ── Patients ─────────────────────────────────────────────────────────────
  String get patientsTitle => _t('patients.title');
  String get patientsSubtitle => _t('patients.subtitle');
  String get newPatientTitle => _t('patients.newTitle');
  String get newPatientSubtitle => _t('patients.newSubtitle');
  String get firstName => _t('patients.firstName');
  String get lastName => _t('patients.lastName');
  String get dateOfBirth => _t('patients.dob');
  String get address => _t('patients.address');
  String get notes => _t('patients.notes');
  String get healthInsurance => _t('patients.insurance');
  String get createPatient => _t('patients.create');
  String get filterAll => _t('patients.filterAll');

  // ── Laboratories (admin) ─────────────────────────────────────────────────
  String get labsTitle => _t('labs.title');
  String get labsSubtitle => _t('labs.subtitle');
  String get labsSearchHint => _t('labs.searchHint');
  String get labsFilterUnverified => _t('labs.filterUnverified');
  String get labsFilterVerified => _t('labs.filterVerified');
  String get labsEmpty => _t('labs.empty');
  String get labsEmptyFilter => _t('labs.emptyFilter');
  String get labsVerified => _t('labs.verified');
  String get labsUnverified => _t('labs.unverified');
  String get labsVerify => _t('labs.verify');
  String get labsDelete => _t('labs.delete');
  String get labsDeleteTitle => _t('labs.deleteTitle');
  String labsDeleteBody(String name) =>
      _t('labs.deleteBody').replaceAll('{name}', name);
  String get labsSoftDelete => _t('labs.softDelete');
  String get labsHardDelete => _t('labs.hardDelete');
  String labsCount(int shown, int total) => _t('labs.count')
      .replaceAll('{shown}', '$shown')
      .replaceAll('{total}', '$total');

  // ── Feature pages ────────────────────────────────────────────────────────
  String get cameraTitle => _t('features.camera');
  String get scansTitle => _t('features.scans');
  String get shadeTitle => _t('features.shade');
  String get smileTitle => _t('features.smile');
  String get scanBodyTitle => _t('features.scanBody');
  String get messagesTitle => _t('features.messages');
  String get notificationsTitle => _t('features.notifications');
  String get notificationsSubtitle => _t('notifications.subtitle');
  String get notificationsEmpty => _t('notifications.empty');
  String get notificationsMarkAll => _t('notifications.markAll');
  String get notificationsMarking => _t('notifications.marking');
  String get notificationsMarkRead => _t('notifications.markRead');
  String get notificationsFilterUnread => _t('notifications.filterUnread');
  String get notificationsFilterMessages => _t('notifications.filterMessages');
  String get notificationsFilterCases => _t('notifications.filterCases');
  String get notificationsFilterScans => _t('notifications.filterScans');
  String notificationsUnreadCount(int n) =>
      _t('notifications.unreadCount').replaceAll('{n}', '$n');
  String notificationTypeLabel(String type) {
    switch (type) {
      case 'message':
        return _t('notifications.typeMessage');
      case 'case_status':
        return _t('notifications.typeCase');
      case 'scan_quality':
        return _t('notifications.typeScanQuality');
      case 'shade':
        return _t('notifications.typeShade');
      case 'scan_body':
        return _t('notifications.typeScanBody');
      case 'sync':
        return _t('notifications.typeSync');
      case 'export':
        return _t('notifications.typeExport');
      default:
        return type;
    }
  }

  String get reportsTitle => _t('features.reports');
  String get selectPatient => _t('features.selectPatient');

  // ── Reports ──────────────────────────────────────────────────────────────
  String get reportsSubtitle => _t('reports.subtitle');
  String get reportsLoading => _t('reports.loading');
  String get reportsPeriod7 => _t('reports.period7');
  String get reportsPeriod30 => _t('reports.period30');
  String get reportsPeriod90 => _t('reports.period90');
  String get reportsPeriodAll => _t('reports.periodAll');
  String get reportsPatients => _t('reports.patients');
  String get reportsActiveCases => _t('reports.activeCases');
  String get reportsCompleted => _t('reports.completed');
  String get reportsAvgTime => _t('reports.avgTime');
  String get reportsRejectionRate => _t('reports.rejectionRate');
  String get reportsPipeline => _t('reports.pipeline');
  String get reportsThroughput => _t('reports.throughput');
  String get reportsCreated => _t('reports.created');
  String get reportsClinical => _t('reports.clinical');
  String get reportsCoverage => _t('reports.coverage');
  String get reportsWithScans => _t('reports.withScans');
  String get reportsWithPhotos => _t('reports.withPhotos');
  String get reportsWithShade => _t('reports.withShade');
  String get reportsWithShape => _t('reports.withShape');
  String get reportsWithScanBody => _t('reports.withScanBody');
  String get reportsTotalScans => _t('reports.totalScans');
  String get reportsTotalShades => _t('reports.totalShades');
  String get reportsLabInbox => _t('reports.labInbox');
  String get reportsUnreadMessages => _t('reports.unreadMessages');
  String get reportsThreads => _t('reports.threads');
  String get reportsUnreadNotifs => _t('reports.unreadNotifs');
  String get reportsAttention => _t('reports.attention');
  String get reportsAttentionEmpty => _t('reports.attentionEmpty');
  String get reportsTopPatients => _t('reports.topPatients');
  String get reportsTopEmpty => _t('reports.topEmpty');
  String get reportsExports => _t('reports.exports');
  String get reportsExportsHint => _t('reports.exportsHint');
  String get reportsSummaryExport => _t('reports.summaryExport');
  String get reportsSummaryTitle => _t('reports.summaryTitle');
  String get reportsClose => _t('reports.close');
  String get reportsNewInPeriod => _t('reports.newInPeriod');
  String get reportsCreatedInPeriod => _t('reports.createdInPeriod');
  String get reportsCompletedInPeriod => _t('reports.completedInPeriod');
  String get reportsOpenMessages => _t('reports.openMessages');
  String get reportsOpenPatients => _t('reports.openPatients');
  String get reportsClinicalHint => _t('reports.clinicalHint');

  String get reportsNoData => _t('reports.noData');

  String get reportsCasesCol => _t('reports.casesCol');
  String get reportsArtifacts => _t('reports.artifacts');

  // ── Case statuses ────────────────────────────────────────────────────────
  String statusLabel(String key) {
    switch (key) {
      case 'in_progress':
        return _t('status.inProgress');
      case 'pending':
      case 'awaiting_scan':
        return _t('status.awaitingScan');
      case 'in_review':
        return _t('status.inReview');
      case 'completed':
      case 'complete':
        return _t('status.complete');
      case 'rejected':
        return _t('status.rejected');
      case 'none':
      case 'no_case':
        return _t('status.noCase');
      default:
        return key;
    }
  }

  static const _en = <String, String>{
    'nav.dashboard': 'Dashboard',
    'nav.patients': 'Patients',
    'nav.newPatient': 'New Patient',
    'nav.camera': 'Camera',
    'nav.scans': 'Scans',
    'nav.shade': 'Shade Detection',
    'nav.smilePreview': 'Smile Preview',
    'nav.scanBody': 'Scan Body',
    'nav.messages': 'Messages',
    'nav.laboratories': 'Laboratories',
    'nav.notifications': 'Notifications',
    'nav.reports': 'Reports',
    'nav.settings': 'Settings',
    'nav.profile': 'Profile',
    'proEdition': 'Pro Edition',
    'common.refresh': 'Refresh',
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.ok': 'OK',
    'common.comingSoon': 'Coming soon',
    'common.comingSoonBody':
        'This section is coming soon. Navigate using the sidebar to explore available features.',
    'common.loading': 'Loading…',
    'common.online': 'Online',
    'common.offline': 'Offline',
    'common.preferenceSaved': 'Preference saved',
    'common.addPatient': 'Add patient',
    'common.searchPatients': 'Search patients…',
    'common.noPatientsYet': 'No patients yet',
    'auth.signIn': 'Sign in',
    'auth.signInSubtitle': 'Use your Elite Dent profile credentials',
    'auth.email': 'Email',
    'auth.password': 'Password',
    'auth.createProfile': 'Create a profile',
    'auth.useDemo': 'Use demo dentist account',
    'auth.hero':
        'Chairside scan validation, shade AI, and lab collaboration — designed for iPad.',
    'auth.registerTitle': 'Create profile',
    'auth.registerSubtitle':
        'Register a dentist or laboratory account for Elite Dent',
    'auth.fullName': 'Full name *',
    'auth.clinic': 'Clinic name *',
    'auth.phone': 'Phone *',
    'auth.confirmPassword': 'Confirm password',
    'auth.roleDentist': 'Dentist',
    'auth.roleLaboratory': 'Laboratory',
    'auth.roleLab': 'Laboratory',
    'auth.alreadyHaveAccount': 'Already have an account? Sign in',
    'auth.errNameEmailPassword': 'Name, email, and password are required',
    'auth.errAllFieldsRequired': 'All fields are required',
    'auth.errPasswordShort': 'Password must be at least 6 characters',
    'auth.errPasswordMismatch': 'Passwords do not match',
    'auth.errPhoneInvalid':
        'Phone must start with +49 and have exactly 11 digits after',
    'auth.errEmailRequired': 'Email is required',
    'auth.forgotPassword': 'Forgot password?',
    'auth.forgotPasswordTitle': 'Reset password',
    'auth.forgotPasswordSubtitle':
        'Enter your email and we will send a password reset link if an account exists.',
    'auth.sendResetLink': 'Send reset link',
    'auth.backToSignIn': 'Back to sign in',
    'auth.emailConfirmationRequired':
        'Account created. Confirm your email before signing in.',
    'settings.title': 'Settings',
    'settings.subtitle':
        'Clinic preferences for this device — profile & password live under Profile',
    'settings.offlineTitle': 'Offline & sync',
    'settings.offlineSubtitle': 'Chairside queue for photos and PLY scans',
    'settings.connection': 'Connection',
    'settings.pending': 'Pending',
    'settings.autoSync': 'Auto-sync when online',
    'settings.autoSyncSub': 'Flush queued uploads when the network returns',
    'settings.syncNow': 'Sync now',
    'settings.syncing': 'Syncing…',
    'settings.clearCache': 'Clear cache',
    'settings.clearing': 'Clearing…',
    'settings.clearCacheTitle': 'Clear encrypted cache?',
    'settings.clearCacheBody':
        'Removes locally encrypted photos/scans on this device. Pending sync queue items are kept. This cannot be undone.',
    'settings.notificationsTitle': 'Notifications',
    'settings.notificationsSub': 'Choose which alerts appear in the inbox badge',
    'settings.notifyMessages': 'Lab messages',
    'settings.notifyMessagesSub': 'New chat from the lab on a case',
    'settings.notifyCase': 'Case status changes',
    'settings.notifyCaseSub': 'Pending, in review, completed, rejected',
    'settings.notifyScan': 'Scan quality alerts',
    'settings.notifyScanSub': 'Grainy / distorted PLY — prompt to rescan',
    'settings.languageTitle': 'Language & region',
    'settings.languageSub': 'UI language for the whole app',
    'settings.appLanguage': 'App language',
    'settings.aiTitle': 'AI defaults',
    'settings.aiSub': 'Auto-run helpers — shade still needs manual override',
    'settings.autoShade': 'Auto shade detection',
    'settings.autoShadeSub': 'Suggest VITA Classical after photos',
    'settings.autoQuality': 'Auto scan quality check',
    'settings.autoQualitySub': 'Flag grainy or distorted PLY before leave',
    'settings.autoScanBody': 'Auto scan-body diameter',
    'settings.autoScanBodySub': 'Detect size → tooth / manufacturer hint',
    'settings.aboutTitle': 'About',
    'settings.aboutSub': 'Elite Dent · Dental Lab AI',
    'settings.version': 'Version',
    'settings.api': 'API',
    'settings.baseUrl': 'Base URL',
    'settings.privacyNote':
        'Patient data is encrypted at rest on device and in transit to the EU API.',
    'settings.offlineError': 'Device is offline — cannot sync now',
    'settings.queueEmpty': 'Queue is empty — nothing to sync',
    'settings.synced': 'Synced {n} item(s)',
    'settings.cleared': 'Cleared {n} cached file(s)',
    'settings.loadError': 'Could not load settings',
    'settings.english': 'English',
    'settings.german': 'Deutsch',
    'profile.title': 'Profile',
    'profile.subtitle': 'Your account details — not limited to demo credentials',
    'profile.signOut': 'Sign out',
    'profile.saveProfile': 'Save profile',
    'profile.saving': 'Saving…',
    'profile.security': 'Security',
    'profile.securitySub': 'Change your password for this account.',
    'profile.currentPassword': 'Current password',
    'profile.newPassword': 'New password',
    'profile.confirmNewPassword': 'Confirm new password',
    'profile.updatePassword': 'Update password',
    'profile.updating': 'Updating…',
    'profile.accountInfo': 'Account info',
    'profile.role': 'Role',
    'profile.created': 'Created',
    'profile.lastLogin': 'Last login',
    'profile.saved': 'Profile saved',
    'profile.passwordUpdated': 'Password updated',
    'profile.changePasswordSuccessBody':
        'Your password was changed successfully. Please sign in again.',
    'profile.errNameEmail': 'Name and email are required',
    'profile.errEnterPasswords': 'Enter current and new password',
    'profile.errNewPasswordShort': 'New password must be at least 6 characters',
    'profile.errNewPasswordMismatch': 'New passwords do not match',
    'profile.clinicHint': 'e.g. Elite Dent Munich',
    'dash.goodMorning': 'Good morning, Dr. {name}',
    'dash.goodAfternoon': 'Good afternoon, Dr. {name}',
    'dash.goodEvening': 'Good evening, Dr. {name}',
    'dash.loading': 'Loading clinic data…',
    'dash.noCases': 'No open cases yet — add a patient to get started.',
    'dash.completedCases': 'Completed Cases',
    'dash.avgProcessing': 'Avg. Processing',
    'dash.pendingScans': 'Pending Scans',
    'dash.rejectedScans': 'Rejected Scans',
    'dash.recentCases': 'Recent Cases',
    'dash.recentActivity': 'Recent Activity',
    'dash.startScan': 'Start Scan',
    'dash.noPatientsHint': 'No patients yet',
    'dash.basedOnCompleted': 'Based on completed cases',
    'dash.noneInProgress': 'None actively in progress',
    'dash.noRejections': 'No rejections open',
    'dash.needRescan': 'Need rescan before remake',
    'dash.noCasesEmpty': 'No cases yet. Create a patient to start.',
    'dash.activityEmpty': 'Activity from cases and messages will appear here.',
    'dash.colCaseId': 'CASE ID',
    'dash.colPatient': 'PATIENT',
    'dash.colDentist': 'DENTIST',
    'dash.colStatus': 'STATUS',
    'dash.colUpdated': 'UPDATED',
    'patients.title': 'Patients',
    'patients.subtitle': 'Manage your patient roster and open cases',
    'patients.newTitle': 'New Patient',
    'patients.newSubtitle': 'GDPR-safe patient record for this dentist',
    'patients.firstName': 'First name',
    'patients.lastName': 'Last name',
    'patients.dob': 'Date of birth',
    'patients.address': 'Address',
    'patients.notes': 'Notes',
    'patients.insurance': 'Health insurance',
    'patients.create': 'Create patient',
    'patients.filterAll': 'All',
    'labs.title': 'Laboratories',
    'labs.subtitle': 'Manage laboratory profiles — verify or remove users',
    'labs.searchHint': 'Search by name, email, clinic…',
    'labs.filterUnverified': 'Unverified',
    'labs.filterVerified': 'Verified',
    'labs.empty': 'No Laboratries found.',
    'labs.emptyFilter': 'No Laboratries match this filter.',
    'labs.verified': 'Verified',
    'labs.unverified': 'Unverified',
    'labs.verify': 'Verify user',
    'labs.delete': 'Delete user',
    'labs.deleteTitle': 'Delete user?',
    'labs.deleteBody':
        'Choose how to remove {name}. Soft delete keeps their data; hard delete permanently removes the account.',
    'labs.softDelete': 'Keep data (soft)',
    'labs.hardDelete': 'Delete forever',
    'labs.count': '{shown} shown · {total} total',
    'features.camera': 'Camera Capture',
    'features.scans': 'Scans',
    'features.shade': 'Shade Detection',
    'features.smile': 'Smile Preview',
    'features.scanBody': 'Scan Body',
    'features.messages': 'Messages',
    'features.notifications': 'Notifications',
    'features.reports': 'Reports',
    'features.selectPatient': 'Select patient',
    'reports.subtitle':
        'Clinic performance, case pipeline, and AI coverage',
    'reports.loading': 'Building clinic report…',
    'reports.period7': '7 days',
    'reports.period30': '30 days',
    'reports.period90': '90 days',
    'reports.periodAll': 'All time',
    'reports.patients': 'Patients',
    'reports.activeCases': 'Active cases',
    'reports.completed': 'Completed',
    'reports.avgTime': 'Avg. turnaround',
    'reports.rejectionRate': 'Rejection rate',
    'reports.pipeline': 'Case pipeline',
    'reports.throughput': 'Weekly throughput',
    'reports.created': 'Created',
    'reports.clinical': 'Clinical AI coverage',
    'reports.coverage': 'Cases with AI artifacts',
    'reports.withScans': 'With scans',
    'reports.withPhotos': 'With photos',
    'reports.withShade': 'Shade saved',
    'reports.withShape': 'Smile preview',
    'reports.withScanBody': 'Scan body',
    'reports.totalScans': 'Scan files',
    'reports.totalShades': 'Shade saves',
    'reports.labInbox': 'Lab communication',
    'reports.unreadMessages': 'Unread messages',
    'reports.threads': 'Active threads',
    'reports.unreadNotifs': 'Unread alerts',
    'reports.attention': 'Needs attention',
    'reports.attentionEmpty': 'No open cases need attention right now.',
    'reports.topPatients': 'Most active patients',
    'reports.topEmpty': 'No patient case volume yet.',
    'reports.exports': 'Exports',
    'reports.exportsHint':
        'A printable clinic summary for the selected period.',
    'reports.summaryExport': 'Clinic summary',
    'reports.summaryTitle': 'Clinic report summary',
    'reports.close': 'Close',
    'reports.newInPeriod': 'new in period',
    'reports.createdInPeriod': 'opened in period',
    'reports.completedInPeriod': 'finished in period',
    'reports.openMessages': 'Open messages',
    'reports.openPatients': 'Open patients',
    'reports.clinicalHint':
        'Coverage across shade, smile preview, scan body, and scan uploads',
    'reports.noData': 'No activity in this period yet.',
    'reports.casesCol': 'Cases',
    'reports.artifacts': 'Artifacts',
    'notifications.subtitle':
        'Action items from your patients — scans needed, lab review, shade confirms',
    'notifications.empty': "You're all caught up — no notifications here",
    'notifications.markAll': 'Mark all read',
    'notifications.marking': 'Updating…',
    'notifications.markRead': 'Mark as read',
    'notifications.filterUnread': 'Unread',
    'notifications.filterMessages': 'Messages',
    'notifications.filterCases': 'Cases',
    'notifications.filterScans': 'Scans / AI',
    'notifications.unreadCount': '{n} unread',
    'notifications.typeMessage': 'Message',
    'notifications.typeCase': 'Case',
    'notifications.typeScanQuality': 'Scan quality',
    'notifications.typeShade': 'Shade',
    'notifications.typeScanBody': 'Scan body',
    'notifications.typeSync': 'Sync',
    'notifications.typeExport': 'Export',
    'status.inProgress': 'In Progress',
    'status.awaitingScan': 'Awaiting Scan',
    'status.inReview': 'In Review',
    'status.complete': 'Complete',
    'status.rejected': 'Rejected',
    'status.noCase': 'No case',
  };

  static const _de = <String, String>{
    'nav.dashboard': 'Übersicht',
    'nav.patients': 'Patienten',
    'nav.newPatient': 'Neuer Patient',
    'nav.camera': 'Kamera',
    'nav.scans': 'Scans',
    'nav.shade': 'Farbbestimmung',
    'nav.smilePreview': 'Lächeln-Vorschau',
    'nav.scanBody': 'Scanbody',
    'nav.messages': 'Nachrichten',
    'nav.laboratories': 'Labore',
    'nav.notifications': 'Benachrichtigungen',
    'nav.reports': 'Berichte',
    'nav.settings': 'Einstellungen',
    'nav.profile': 'Profil',
    'proEdition': 'Pro Edition',
    'common.refresh': 'Aktualisieren',
    'common.save': 'Speichern',
    'common.cancel': 'Abbrechen',
    'common.ok': 'OK',
    'common.comingSoon': 'Demnächst verfügbar',
    'common.comingSoonBody':
        'Dieser Bereich kommt bald. Nutzen Sie die Seitenleiste für verfügbare Funktionen.',
    'common.loading': 'Laden…',
    'common.online': 'Online',
    'common.offline': 'Offline',
    'common.preferenceSaved': 'Einstellung gespeichert',
    'common.addPatient': 'Patient hinzufügen',
    'common.searchPatients': 'Patienten suchen…',
    'common.noPatientsYet': 'Noch keine Patienten',
    'auth.signIn': 'Anmelden',
    'auth.signInSubtitle': 'Mit Ihren Elite-Dent-Profildaten anmelden',
    'auth.email': 'E-Mail',
    'auth.password': 'Passwort',
    'auth.createProfile': 'Profil erstellen',
    'auth.useDemo': 'Demo-Zahnarztkonto verwenden',
    'auth.hero':
        'Scan-Prüfung am Stuhl, Farb-KI und Labor-Zusammenarbeit — fürs iPad.',
    'auth.registerTitle': 'Profil erstellen',
    'auth.registerSubtitle':
        'Zahnarzt- oder Laborkonto für Elite Dent registrieren',
    'auth.fullName': 'Vollständiger Name *',
    'auth.clinic': 'Praxisname *',
    'auth.phone': 'Telefon *',
    'auth.confirmPassword': 'Passwort bestätigen',
    'auth.roleDentist': 'Zahnarzt',
    'auth.roleLaboratory': 'Labor',
    'auth.roleLab': 'Labor',
    'auth.alreadyHaveAccount': 'Bereits ein Konto? Anmelden',
    'auth.errNameEmailPassword': 'Name, E-Mail und Passwort sind erforderlich',
    'auth.errAllFieldsRequired': 'Alle Felder sind erforderlich',
    'auth.errPasswordShort': 'Passwort muss mindestens 6 Zeichen haben',
    'auth.errPasswordMismatch': 'Passwörter stimmen nicht überein',
    'auth.errPhoneInvalid':
        'Telefonnummer muss mit +49 beginnen und genau 11 Ziffern danach haben',
    'auth.errEmailRequired': 'E-Mail ist erforderlich',
    'auth.forgotPassword': 'Passwort vergessen?',
    'auth.forgotPasswordTitle': 'Passwort zurücksetzen',
    'auth.forgotPasswordSubtitle':
        'Geben Sie Ihre E-Mail ein. Falls ein Konto existiert, senden wir einen Reset-Link.',
    'auth.sendResetLink': 'Reset-Link senden',
    'auth.backToSignIn': 'Zurück zur Anmeldung',
    'auth.emailConfirmationRequired':
        'Konto erstellt. Bitte bestätigen Sie Ihre E-Mail vor der Anmeldung.',
    'settings.title': 'Einstellungen',
    'settings.subtitle':
        'Praxis-Einstellungen für dieses Gerät — Profil & Passwort unter Profil',
    'settings.offlineTitle': 'Offline & Sync',
    'settings.offlineSubtitle': 'Warteschlange für Fotos und PLY-Scans',
    'settings.connection': 'Verbindung',
    'settings.pending': 'Ausstehend',
    'settings.autoSync': 'Auto-Sync bei Online',
    'settings.autoSyncSub':
        'Warteschlange synchronisieren, sobald das Netz zurück ist',
    'settings.syncNow': 'Jetzt synchronisieren',
    'settings.syncing': 'Synchronisiere…',
    'settings.clearCache': 'Cache leeren',
    'settings.clearing': 'Leere…',
    'settings.clearCacheTitle': 'Verschlüsselten Cache leeren?',
    'settings.clearCacheBody':
        'Entfernt lokal verschlüsselte Fotos/Scans auf diesem Gerät. Ausstehende Sync-Einträge bleiben. Nicht rückgängig zu machen.',
    'settings.notificationsTitle': 'Benachrichtigungen',
    'settings.notificationsSub':
        'Wählen Sie, welche Hinweise im Badge erscheinen',
    'settings.notifyMessages': 'Labornachrichten',
    'settings.notifyMessagesSub': 'Neuer Chat vom Labor zu einem Fall',
    'settings.notifyCase': 'Fallstatus-Änderungen',
    'settings.notifyCaseSub': 'Ausstehend, in Prüfung, abgeschlossen, abgelehnt',
    'settings.notifyScan': 'Scan-Qualitätswarnungen',
    'settings.notifyScanSub': 'Körnig / verzerrt — erneuten Scan anfordern',
    'settings.languageTitle': 'Sprache & Region',
    'settings.languageSub': 'UI-Sprache für die gesamte App',
    'settings.appLanguage': 'App-Sprache',
    'settings.aiTitle': 'KI-Standards',
    'settings.aiSub':
        'Automatische Helfer — Farbe erfordert weiterhin manuelle Bestätigung',
    'settings.autoShade': 'Automatische Farbbestimmung',
    'settings.autoShadeSub': 'VITA Classical nach Fotos vorschlagen',
    'settings.autoQuality': 'Automatische Scan-Qualitätsprüfung',
    'settings.autoQualitySub':
        'Körnige oder verzerrte PLY vor dem Verlassen markieren',
    'settings.autoScanBody': 'Automatischer Scanbody-Durchmesser',
    'settings.autoScanBodySub': 'Größe erkennen → Zahn / Hersteller-Hinweis',
    'settings.aboutTitle': 'Über',
    'settings.aboutSub': 'Elite Dent · Dental Lab AI',
    'settings.version': 'Version',
    'settings.api': 'API',
    'settings.baseUrl': 'Basis-URL',
    'settings.privacyNote':
        'Patientendaten werden auf dem Gerät und zur EU-API verschlüsselt übertragen.',
    'settings.offlineError': 'Gerät offline — Sync nicht möglich',
    'settings.queueEmpty': 'Warteschlange leer — nichts zu synchronisieren',
    'settings.synced': '{n} Eintrag/Einträge synchronisiert',
    'settings.cleared': '{n} Cache-Datei(en) gelöscht',
    'settings.loadError': 'Einstellungen konnten nicht geladen werden',
    'settings.english': 'English',
    'settings.german': 'Deutsch',
    'profile.title': 'Profil',
    'profile.subtitle':
        'Ihre Kontodaten — nicht auf Demo-Zugangsdaten beschränkt',
    'profile.signOut': 'Abmelden',
    'profile.saveProfile': 'Profil speichern',
    'profile.saving': 'Speichern…',
    'profile.security': 'Sicherheit',
    'profile.securitySub': 'Passwort für dieses Konto ändern.',
    'profile.currentPassword': 'Aktuelles Passwort',
    'profile.newPassword': 'Neues Passwort',
    'profile.confirmNewPassword': 'Neues Passwort bestätigen',
    'profile.updatePassword': 'Passwort aktualisieren',
    'profile.updating': 'Aktualisiere…',
    'profile.accountInfo': 'Kontoinformationen',
    'profile.role': 'Rolle',
    'profile.created': 'Erstellt',
    'profile.lastLogin': 'Letzte Anmeldung',
    'profile.saved': 'Profil gespeichert',
    'profile.passwordUpdated': 'Passwort aktualisiert',
    'profile.changePasswordSuccessBody':
        'Ihr Passwort wurde geändert. Bitte melden Sie sich erneut an.',
    'profile.errNameEmail': 'Name und E-Mail sind erforderlich',
    'profile.errEnterPasswords': 'Aktuelles und neues Passwort eingeben',
    'profile.errNewPasswordShort':
        'Neues Passwort muss mindestens 6 Zeichen haben',
    'profile.errNewPasswordMismatch': 'Neue Passwörter stimmen nicht überein',
    'profile.clinicHint': 'z. B. Elite Dent München',
    'dash.goodMorning': 'Guten Morgen, Dr. {name}',
    'dash.goodAfternoon': 'Guten Tag, Dr. {name}',
    'dash.goodEvening': 'Guten Abend, Dr. {name}',
    'dash.loading': 'Klinikdaten werden geladen…',
    'dash.noCases':
        'Noch keine offenen Fälle — legen Sie einen Patienten an.',
    'dash.completedCases': 'Abgeschlossene Fälle',
    'dash.avgProcessing': 'Ø Bearbeitungszeit',
    'dash.pendingScans': 'Ausstehende Scans',
    'dash.rejectedScans': 'Abgelehnte Scans',
    'dash.recentCases': 'Aktuelle Fälle',
    'dash.recentActivity': 'Letzte Aktivität',
    'dash.startScan': 'Scan starten',
    'dash.noPatientsHint': 'Noch keine Patienten',
    'dash.basedOnCompleted': 'Basierend auf abgeschlossenen Fällen',
    'dash.noneInProgress': 'Keine aktiv in Bearbeitung',
    'dash.noRejections': 'Keine offenen Ablehnungen',
    'dash.needRescan': 'Erneuter Scan vor Neuanfertigung nötig',
    'dash.noCasesEmpty': 'Noch keine Fälle. Legen Sie einen Patienten an.',
    'dash.activityEmpty':
        'Aktivität aus Fällen und Nachrichten erscheint hier.',
    'dash.colCaseId': 'FALL-ID',
    'dash.colPatient': 'PATIENT',
    'dash.colDentist': 'ZAHNARZT',
    'dash.colStatus': 'STATUS',
    'dash.colUpdated': 'AKTUALISIERT',
    'patients.title': 'Patienten',
    'patients.subtitle': 'Patientenliste und offene Fälle verwalten',
    'patients.newTitle': 'Neuer Patient',
    'patients.newSubtitle': 'DSGVO-konformer Patienteneintrag',
    'patients.firstName': 'Vorname',
    'patients.lastName': 'Nachname',
    'patients.dob': 'Geburtsdatum',
    'patients.address': 'Adresse',
    'patients.notes': 'Notizen',
    'patients.insurance': 'Krankenversicherung',
    'patients.create': 'Patient anlegen',
    'patients.filterAll': 'Alle',
    'labs.title': 'Labore',
    'labs.subtitle': 'Laborprofile verwalten — prüfen oder entfernen',
    'labs.searchHint': 'Suche nach Name, E-Mail, Praxis…',
    'labs.filterUnverified': 'Ungeprüft',
    'labs.filterVerified': 'Geprüft',
    'labs.empty': 'Keine Nutzer gefunden.',
    'labs.emptyFilter': 'Keine Nutzer entsprechen diesem Filter.',
    'labs.verified': 'Geprüft',
    'labs.unverified': 'Ungeprüft',
    'labs.verify': 'Nutzer prüfen',
    'labs.delete': 'Nutzer löschen',
    'labs.deleteTitle': 'Nutzer löschen?',
    'labs.deleteBody':
        'Wie möchten Sie {name} entfernen? Soft-Delete behält die Daten; Hard-Delete löscht das Konto dauerhaft.',
    'labs.softDelete': 'Daten behalten (soft)',
    'labs.hardDelete': 'Endgültig löschen',
    'labs.count': '{shown} angezeigt · {total} gesamt',
    'features.camera': 'Kameraaufnahme',
    'features.scans': 'Scans',
    'features.shade': 'Farbbestimmung',
    'features.smile': 'Lächeln-Vorschau',
    'features.scanBody': 'Scanbody',
    'features.messages': 'Nachrichten',
    'features.notifications': 'Benachrichtigungen',
    'features.reports': 'Berichte',
    'features.selectPatient': 'Patient wählen',
    'reports.subtitle':
        'Praxisleistung, Fall-Pipeline und KI-Abdeckung',
    'reports.loading': 'Klinikbericht wird erstellt…',
    'reports.period7': '7 Tage',
    'reports.period30': '30 Tage',
    'reports.period90': '90 Tage',
    'reports.periodAll': 'Gesamt',
    'reports.patients': 'Patienten',
    'reports.activeCases': 'Aktive Fälle',
    'reports.completed': 'Abgeschlossen',
    'reports.avgTime': 'Ø Durchlaufzeit',
    'reports.rejectionRate': 'Ablehnungsquote',
    'reports.pipeline': 'Fall-Pipeline',
    'reports.throughput': 'Wochendurchsatz',
    'reports.created': 'Erstellt',
    'reports.clinical': 'Klinische KI-Abdeckung',
    'reports.coverage': 'Fälle mit KI-Artefakten',
    'reports.withScans': 'Mit Scans',
    'reports.withPhotos': 'Mit Fotos',
    'reports.withShade': 'Farbe gespeichert',
    'reports.withShape': 'Lächeln-Vorschau',
    'reports.withScanBody': 'Scanbody',
    'reports.totalScans': 'Scan-Dateien',
    'reports.totalShades': 'Farb-Einträge',
    'reports.labInbox': 'Laborkommunikation',
    'reports.unreadMessages': 'Ungelesene Nachrichten',
    'reports.threads': 'Aktive Threads',
    'reports.unreadNotifs': 'Ungelesene Hinweise',
    'reports.attention': 'Handlungsbedarf',
    'reports.attentionEmpty': 'Keine offenen Fälle mit Handlungsbedarf.',
    'reports.topPatients': 'Aktivste Patienten',
    'reports.topEmpty': 'Noch kein Fallvolumen.',
    'reports.exports': 'Exporte',
    'reports.exportsHint':
        'Eine druckbare Klinikübersicht für den ausgewählten Zeitraum.',
    'reports.summaryExport': 'Klinikübersicht',
    'reports.summaryTitle': 'Klinikbericht',
    'reports.close': 'Schließen',
    'reports.newInPeriod': 'neu im Zeitraum',
    'reports.createdInPeriod': 'im Zeitraum geöffnet',
    'reports.completedInPeriod': 'im Zeitraum abgeschlossen',
    'reports.openMessages': 'Nachrichten öffnen',
    'reports.openPatients': 'Patienten öffnen',
    'reports.clinicalHint':
        'Abdeckung über Farbe, Lächeln-Vorschau, Scanbody und Scan-Uploads',
    'reports.noData': 'In diesem Zeitraum noch keine Aktivität.',
    'reports.casesCol': 'Fälle',
    'reports.artifacts': 'Artefakte',
    'notifications.subtitle':
        'Aufgaben zu Ihren Patienten — Scans nötig, Laborprüfung, Farbbestätigung',
    'notifications.empty': 'Alles erledigt — keine Benachrichtigungen',
    'notifications.markAll': 'Alle gelesen',
    'notifications.marking': 'Aktualisiere…',
    'notifications.markRead': 'Als gelesen markieren',
    'notifications.filterUnread': 'Ungelesen',
    'notifications.filterMessages': 'Nachrichten',
    'notifications.filterCases': 'Fälle',
    'notifications.filterScans': 'Scans / KI',
    'notifications.unreadCount': '{n} ungelesen',
    'notifications.typeMessage': 'Nachricht',
    'notifications.typeCase': 'Fall',
    'notifications.typeScanQuality': 'Scan-Qualität',
    'notifications.typeShade': 'Farbe',
    'notifications.typeScanBody': 'Scanbody',
    'notifications.typeSync': 'Sync',
    'notifications.typeExport': 'Export',
    'status.inProgress': 'In Bearbeitung',
    'status.awaitingScan': 'Wartet auf Scan',
    'status.inReview': 'In Prüfung',
    'status.complete': 'Abgeschlossen',
    'status.rejected': 'Abgelehnt',
    'status.noCase': 'Kein Fall',
  };
}
