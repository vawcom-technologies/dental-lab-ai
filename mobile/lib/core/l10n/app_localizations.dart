import 'package:flutter/widgets.dart';

import 'locale_controller.dart';

/// Typed EN/DE strings for Elite Dent. Use [AppLocalizations.of].
class AppLocalizations {
  AppLocalizations(this.code);

  final String code;

  /// For code without a BuildContext; follows the current language.
  static AppLocalizations get current => AppLocalizations(LocaleController.current);

  static AppLocalizations of(BuildContext context) {
    return AppLocalizations(LocaleScope.of(context).code);
  }

  String _t(String key) {
    if (code == 'de') return _de[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }

  String tr(String key) => _t(key);

  /// Translate and fill `{name}` placeholders.
  String trp(String key, Map<String, Object?> p) => p.entries.fold(
      _t(key), (s, e) => s.replaceAll('{${e.key}}', '${e.value}'));

  // ── Nav ──────────────────────────────────────────────────────────────────
  String get navDashboard => _t('nav.dashboard');
  String get navPatients => _t('nav.patients');
  String get navNewPatient => _t('nav.newPatient');
  String get navAppointments => _t('nav.appointments');
  String get navCamera => _t('nav.camera');
  String get navScans => _t('nav.scans');
  String get navShade => _t('nav.shade');
  String get navSmilePreview => _t('nav.smilePreview');
  String get navScanBody => _t('nav.scanBody');
  String get navMessages => _t('nav.messages');
  String get navLaboratories => _t('nav.laboratories');
  String get navNotifications => _t('nav.notifications');
  String get navReports => _t('nav.reports');
  String get navSignups => _t('nav.signups');
  String get navReview => _t('nav.review');
  String get navLab => _t('nav.lab');
  String get errRegistrationRejected => _t('errors.registrationRejected');
  String get authRejectedTitle => _t('auth.rejectedTitle');
  String get navInterpreter => _t('nav.interpreter');
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
  String get errSessionExpired => _t('errors.sessionExpired');
  String get errNoPermission => _t('errors.noPermission');
  String get errNotFound => _t('errors.notFound');
  String get errValidation => _t('errors.validation');
  String get errNetwork => _t('errors.network');
  String get errTimeout => _t('errors.timeout');
  String get errServer => _t('errors.server');
  String get errGeneric => _t('errors.generic');
  String get errBadCredentials => _t('errors.badCredentials');
  String get errTooMany => _t('errors.tooMany');
  String get errConflict => _t('errors.conflict');
  String get errDownloadFailed => _t('errors.downloadFailed');

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
  String get roleAdmin => _t('auth.roleAdmin');
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
  String get settingsNotifyMaster => _t('settings.notifyMaster');
  String get settingsNotifyMasterSub => _t('settings.notifyMasterSub');
  String get settingsNotifyMessages => _t('settings.notifyMessages');
  String get settingsNotifyMessagesSub => _t('settings.notifyMessagesSub');
  String get settingsNotifyCase => _t('settings.notifyCase');
  String get settingsNotifyCaseSub => _t('settings.notifyCaseSub');
  String get settingsNotifyScan => _t('settings.notifyScan');
  String get settingsNotifyScanSub => _t('settings.notifyScanSub');
  String get settingsLanguageTitle => _t('settings.languageTitle');
  String get settingsLanguageSub => _t('settings.languageSub');
  String get settingsAppLanguage => _t('settings.appLanguage');
  String get aboutTitle => _t('about.title');
  String get aboutWhatTitle => _t('about.whatTitle');
  String get aboutWhatBody => _t('about.whatBody');
  String get aboutWhoTitle => _t('about.whoTitle');
  String get aboutWhoBody => _t('about.whoBody');
  String get aboutSupport => _t('about.support');
  String get aboutPrivacy => _t('about.privacy');
  String get aboutImprint => _t('about.imprint');
  String get aboutWebsite => _t('about.website');
  String get aboutFeaturesTitle => _t('about.featuresTitle');
  String get aboutLinksTitle => _t('about.linksTitle');
  String get aboutAccountTitle => _t('about.accountTitle');
  String get aboutUserId => _t('about.userId');
  String get aboutName => _t('about.name');
  String get aboutClinic => _t('about.clinic');
  String get aboutCredit => _t('about.credit');
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
  String settingsSynced(int n) => _t('settings.synced').replaceAll('{n}', '$n');
  String settingsCleared(int n) =>
      _t('settings.cleared').replaceAll('{n}', '$n');
  String get settingsLoadError => _t('settings.loadError');
  String get languageEnglish => _t('settings.english');
  String get languageGerman => _t('settings.german');
  String get settingsDeleteAccount => _t('settings.deleteAccount');
  String get settingsDeleteAccountBody => _t('settings.deleteAccountBody');
  String get settingsDeleteConfirmToken => _t('settings.deleteConfirmToken');
  String get settingsContinue => _t('settings.continue');
  String get settingsConfirmWithPassword => _t('settings.confirmWithPassword');
  String get settingsEnterPasswordToFinish =>
      _t('settings.enterPasswordToFinish');
  String get settingsPasswordRequired => _t('settings.passwordRequired');
  String get settingsDeletingAccount => _t('settings.deletingAccount');
  String get settingsLoading => _t('settings.loading');
  String get settingsAccountFallback => _t('settings.accountFallback');

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
  String get changePasswordSuccessBody =>
      _t('profile.changePasswordSuccessBody');
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
  String labsCount(int shown, int total) => _t(
    'labs.count',
  ).replaceAll('{shown}', '$shown').replaceAll('{total}', '$total');
  String get labsLoading => _t('labs.loading');
  String get labsOpeningChat => _t('labs.openingChat');
  String get labsVerifyBeforeMessage => _t('labs.verifyBeforeMessage');
  String get labsEmptyVerifiedHint => _t('labs.emptyVerifiedHint');
  String get labsEmptyFilterHint => _t('labs.emptyFilterHint');
  String get labsMessage => _t('labs.message');
  String get labsClinicLab => _t('labs.clinicLab');
  String get labsStatus => _t('labs.status');
  String get labsUpdated => _t('labs.updated');
  String get commonRequired => _t('common.required');
  String get commonContinue => _t('common.continue');
  String get commonCopy => _t('common.copy');
  String get commonFetchingData => _t('common.fetchingData');
  String get commonAdd => _t('common.add');
  String get commonArchive => _t('common.archive');
  String get patientsNoMatching => _t('patients.noMatching');

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
      case 'appointment':
        return _t('notifications.typeAppointment');
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
  String get reportsCopy => _t('reports.copy');
  String reportsPeriodLine(String period) =>
      _t('reports.periodLine').replaceAll('{period}', period);
  String get reportsActiveShort => _t('reports.activeShort');
  String get reportsAvgTimeShort => _t('reports.avgTimeShort');
  String get reportsInPipeline => _t('reports.inPipeline');
  String get reportsToComplete => _t('reports.toComplete');
  String reportsNewCount(int n) =>
      _t('reports.newCount').replaceAll('{n}', '$n');
  String get reportsFollowUpHint => _t('reports.followUpHint');
  String get reportsAllClear => _t('reports.allClear');
  String get reportsPatientFallback => _t('reports.patientFallback');

  // ── Case statuses ────────────────────────────────────────────────────────
  String statusLabel(String key) {
    switch (key) {
      case 'all':
        return filterAll;
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

  String appointmentStatusLabel(String key) {
    switch (key) {
      case 'all':
        return filterAll;
      case 'scheduled':
        return _t('appointments.statusScheduled');
      case 'completed':
        return _t('appointments.statusCompleted');
      case 'cancelled':
        return _t('appointments.statusCancelled');
      case 'no_show':
        return _t('appointments.statusNoShow');
      default:
        return key;
    }
  }

  String statusUpdatedTo(String label) =>
      _t('common.statusUpdated').replaceAll('{label}', label);

  // ── Appointments ─────────────────────────────────────────────────────────
  String get appointmentsTitle => _t('appointments.title');
  String get appointmentsSubtitle => _t('appointments.subtitle');
  String get appointmentsBook => _t('appointments.book');
  String get appointmentsBookTitle => _t('appointments.bookTitle');
  String get appointmentsEditTitle => _t('appointments.editTitle');
  String get appointmentsEmpty => _t('appointments.empty');
  String get appointmentsAllPatients => _t('appointments.allPatients');
  String get appointmentsSavedToast => _t('appointments.savedToast');
  String get appointmentsNotesHint => _t('appointments.notesHint');
  String get appointmentsSelectPatient => _t('appointments.selectPatient');
  String get appointmentsDate => _t('appointments.date');
  String get appointmentsTime => _t('appointments.time');
  String get appointmentsDuration => _t('appointments.duration');
  String get appointmentsNotes => _t('appointments.notes');
  String get appointmentsStatus => _t('appointments.status');
  String get appointmentsSaveChanges => _t('appointments.saveChanges');
  String get appointmentsBookSubmit => _t('appointments.bookSubmit');
  String get appointmentsStartTime => _t('appointments.startTime');
  String get appointmentsEndAfterStart => _t('appointments.endAfterStart');
  String appointmentsEndsAt(String time) =>
      _t('appointments.endsAt').replaceAll('{time}', time);
  String get appointmentsSaving => _t('appointments.saving');
  String get appointmentsFiltering => _t('appointments.filtering');
  String get appointmentsFilterEmpty => _t('appointments.filterEmpty');
  String get appointmentsFilterEmptyHint => _t('appointments.filterEmptyHint');
  String get appointmentsBookEmptyHint => _t('appointments.bookEmptyHint');
  String get appointmentsNoPatientsYet => _t('appointments.noPatientsYet');
  String appointmentsInClinic(int n) => n == 1
      ? _t('appointments.inClinicOne')
      : _t('appointments.inClinic').replaceAll('{n}', '$n');
  String appointmentsMinutesShort(int n) =>
      _t('appointments.minutesShort').replaceAll('{n}', '$n');

  // ── Messages ─────────────────────────────────────────────────────────────
  String get messagesSubtitle => _t('messages.subtitle');
  String get messagesPlaceholder => _t('messages.placeholder');
  String get messagesNewChat => _t('messages.newChat');
  String get messagesStartChat => _t('messages.startChat');
  String get messagesEmpty => _t('messages.empty');
  String get messagesSelectConversation => _t('messages.selectConversation');
  String get messagesAttach => _t('messages.attach');
  String get messagesActive => _t('messages.active');
  String get messagesReconnecting => _t('messages.reconnecting');
  String get messagesNoConversations => _t('messages.noConversations');
  String get messagesNoMatch => _t('messages.noMatch');
  String get messagesNewTitle => _t('messages.newTitle');
  String get commonSearch => _t('common.search');
  String get commonEdit => _t('common.edit');
  String get commonDelete => _t('common.delete');
  String get commonShare => _t('common.share');
  String get commonToday => _t('common.today');
  String get commonTomorrow => _t('common.tomorrow');
  String get commonInOneWeek => _t('common.inOneWeek');
  String get commonYesterday => _t('common.yesterday');
  String get commonFullscreen => _t('common.fullscreen');
  String get commonExitFullscreen => _t('common.exitFullscreen');
  String get changeStatus => _t('common.changeStatus');

  // ── Scans ────────────────────────────────────────────────────────────────
  String get scansSubtitle => _t('scans.subtitle');
  String get scansUpload => _t('scans.upload');
  String get scansUploading => _t('scans.uploading');
  String get scansDelete => _t('scans.delete');
  String get scansDeleted => _t('scans.deleted');
  String get scansNoneSelected => _t('scans.noneSelected');
  String get scansSelectPatient => _t('scans.selectPatient');
  String scansEmptyFor(String name) =>
      _t('scans.emptyFor').replaceAll('{name}', name);
  String get scansRescanNow => _t('scans.rescanNow');

  // ── Shade ────────────────────────────────────────────────────────────────
  String get shadeCancel => _t('shade.cancel');
  String get shadeReset => _t('shade.reset');
  String get shadeApply => _t('shade.apply');
  String get shadeAdjustEdges => _t('shade.adjustEdges');
  String get shadeLips => _t('shade.lips');
  String get shadeSymmetry => _t('shade.symmetry');
  String get shadeFocusTooth => _t('shade.focusTooth');
  String get shadeDelete => _t('shade.delete');
  String get shadeAddTooth => _t('shade.addTooth');
  String get shadeUpload => _t('shade.upload');
  String get shadeReupload => _t('shade.reupload');

  // ── Patients extras ──────────────────────────────────────────────────────
  String get patientsStatus => _t('patients.status');
  String get patientsEditTitle => _t('patients.editTitle');
  String get patientsSaveChanges => _t('patients.saveChanges');
  String get patientsCreatedToast => _t('patients.createdToast');
  String get patientsUpdatedToast => _t('patients.updatedToast');
  String get patientsDeleteTitle => _t('patients.deleteTitle');
  String patientsDeleteBody(String name) =>
      _t('patients.deleteBody').replaceAll('{name}', name);
  String get patientsArchiveOption => _t('patients.archiveOption');
  String get patientsArchiveOptionSub => _t('patients.archiveOptionSub');
  String get patientsHardDeleteOption => _t('patients.hardDeleteOption');
  String get patientsHardDeleteOptionSub => _t('patients.hardDeleteOptionSub');
  String get patientsTypeDeleteConfirm => _t('patients.typeDeleteConfirm');
  String get patientsOpening => _t('patients.opening');
  String patientsShownTotal(int shown, int total) => _t(
    'patients.shownTotal',
  ).replaceAll('{shown}', '$shown').replaceAll('{total}', '$total');

  // ── Bulk pass (loaders / chrome leftovers) ───────────────────────────────
  String get commonRequest => _t('common.request');
  String get commonApprove => _t('common.approve');
  String get commonReject => _t('common.reject');
  String get commonDone => _t('common.done');
  String get commonClose => _t('common.close');
  String get commonRename => _t('common.rename');
  String get commonRetry => _t('common.retry');
  String get commonUndo => _t('common.undo');
  String get commonRedo => _t('common.redo');
  String get commonWorking => _t('common.working');
  String get commonUploading => _t('common.uploading');
  String get commonTapToSelect => _t('common.tapToSelect');
  String get commonInvalidDate => _t('common.invalidDate');
  String commonYearsOld(int n) => _t('common.yearsOld').replaceAll('{n}', '$n');
  String get commonOneYearOld => _t('common.oneYearOld');
  String get commonExpandSidebar => _t('common.expandSidebar');
  String get commonCollapseSidebar => _t('common.collapseSidebar');
  String get commonMenu => _t('common.menu');
  String get commonShowPassword => _t('common.showPassword');
  String get commonHidePassword => _t('common.hidePassword');
  String get commonMinPasswordLength => _t('common.minPasswordLength');
  String get commonOpenDownload => _t('common.openDownload');
  String get dashLoadingCases => _t('dash.loadingCases');
  String get dashLoadingActivity => _t('dash.loadingActivity');
  String get patientsLoading => _t('patients.loading');
  String get patientsLoadingAccess => _t('patients.loadingAccess');
  String get patientsLoadingNotes => _t('patients.loadingNotes');
  String get patientsLoadingStaff => _t('patients.loadingStaff');
  String get patientsLoadingAccessRequests =>
      _t('patients.loadingAccessRequests');
  String get patientsEditNote => _t('patients.editNote');
  String get patientsDeleteNoteTitle => _t('patients.deleteNoteTitle');
  String get patientsDeleteNoteBody => _t('patients.deleteNoteBody');
  String get patientsNoteHint => _t('patients.noteHint');
  String get patientsNoteAdded => _t('patients.noteAdded');
  String get patientsNoteUpdated => _t('patients.noteUpdated');
  String get patientsNoteDeleted => _t('patients.noteDeleted');
  String get patientsOnlyAuthorEdit => _t('patients.onlyAuthorEdit');
  String get patientsOnlyAuthorDelete => _t('patients.onlyAuthorDelete');
  String get patientsClinicalNotePlaceholder =>
      _t('patients.clinicalNotePlaceholder');
  String get patientsPendingAccess => _t('patients.pendingAccess');
  String get patientsRevoke => _t('patients.revoke');
  String get patientsRegrant => _t('patients.regrant');
  String get patientsSavePatient => _t('patients.savePatient');
  String get patientsRefreshPatients => _t('patients.refreshPatients');
  String get appointmentsLoading => _t('appointments.loading');
  String get appointmentsSelectDate => _t('appointments.selectDate');
  String get appointmentsEditTooltip => _t('appointments.editTooltip');
  String get appointmentsStarts => _t('appointments.starts');
  String get profileLoading => _t('profile.loading');
  String get scansLoading => _t('scans.loading');
  String get scansUploadingScan => _t('scans.uploadingScan');
  String get shadeLoading => _t('shade.loading');
  String get shadeDetecting => _t('shade.detecting');

  /// Alternating tips shown while shade upload + AI suggest run.
  List<String> get shadeWaitTips => [
    _t('shade.waitTip1'),
    _t('shade.waitTip2'),
    _t('shade.waitTip3'),
    _t('shade.waitTip4'),
    _t('shade.waitTip5'),
  ];
  String get shadeUploadDetect => _t('shade.uploadDetect');
  String get shadeRemoveSave => _t('shade.removeSave');
  String shadeDeleteFromSession(String shade) =>
      _t('shade.deleteFromSession').replaceAll('{shade}', shade);
  String get shadeSimilarShades => _t('shade.similarShades');
  String get shadeBestOverall => _t('shade.bestOverall');
  String get shadeAcrossAllTeeth => _t('shade.acrossAllTeeth');
  String get shadeDeleteTooth => _t('shade.deleteTooth');
  String get shadePhotoTitle => _t('shade.photoTitle');
  String get shadePhotoMessage => _t('shade.photoMessage');
  String get shadeUploadAnother => _t('shade.uploadAnother');
  String get shadeDeletePhoto => _t('shade.deletePhoto');
  String get shadeOpenSession => _t('shade.openSession');
  String get shadeCloseSession => _t('shade.closeSession');
  String get shadeRemoveFromSession => _t('shade.removeFromSession');
  String get smileLoading => _t('smile.loading');
  String get smileLoadPhoto => _t('smile.loadPhoto');
  String get smileChangePhoto => _t('smile.changePhoto');
  String get smileLoadPatientPhoto => _t('smile.loadPatientPhoto');
  String get smileGuides => _t('smile.guides');
  String get smileSize => _t('smile.size');
  String get smileWidth => _t('smile.width');
  String get smileHeight => _t('smile.height');
  String get smileRotate => _t('smile.rotate');
  String get smileBlend => _t('smile.blend');
  String get smileScale => _t('smile.scale');
  String get smileOpacity => _t('smile.opacity');
  String smileUseShape(int n) => _t('smile.useShape').replaceAll('{n}', '$n');
  String get smileShapeSoftOval => _t('smile.shapeSoftOval');
  String get smileShapeClassicOval => _t('smile.shapeClassicOval');
  String get smileShapeRounded => _t('smile.shapeRounded');
  String get smileShapeNaturalOval => _t('smile.shapeNaturalOval');
  String get smileShapeYouthful => _t('smile.shapeYouthful');
  String get smileShapeSoftSquare => _t('smile.shapeSoftSquare');
  String get smileShapeBalanced => _t('smile.shapeBalanced');
  String get smileShapeSoftRect => _t('smile.shapeSoftRect');
  String get smileShapeHollywood => _t('smile.shapeHollywood');
  String get smileShapeStrongSquare => _t('smile.shapeStrongSquare');
  String get smileShapeTapered => _t('smile.shapeTapered');
  String get smileShapeCanineLift => _t('smile.shapeCanineLift');
  String get scanBodyLoading => _t('scanBody.loading');
  String get scanBodySaveToCase => _t('scanBody.saveToCase');
  String get scanBodyMatchTable => _t('scanBody.matchTable');
  String get scanBodyDetectFromPhoto => _t('scanBody.detectFromPhoto');
  String get scanBodyDetected => _t('scanBody.detected');
  String get scanBodyPixels => _t('scanBody.pixels');
  String get scanBodyTableMatch => _t('scanBody.tableMatch');
  String get scanBodyTooth => _t('scanBody.tooth');
  String get scanBodyManufacturer => _t('scanBody.manufacturer');
  String get scanBodyPlatform => _t('scanBody.platform');
  String get scanBodyConfidence => _t('scanBody.confidence');
  String get scanBodyDiameterHint => _t('scanBody.diameterHint');
  String get cameraDeletePhotoTitle => _t('camera.deletePhotoTitle');
  String cameraDeletePhotoBody(String angle, String name) => _t(
    'camera.deletePhotoBody',
  ).replaceAll('{angle}', angle).replaceAll('{name}', name);
  String get cameraRenamePhoto => _t('camera.renamePhoto');
  String get cameraChoosePatient => _t('camera.choosePatient');
  String get cameraChoosePatientBody => _t('camera.choosePatientBody');
  String get cameraNoPhotosYet => _t('camera.noPhotosYet');
  String cameraNoAnglePhotos(String angle) =>
      _t('camera.noAnglePhotos').replaceAll('{angle}', angle);
  String get cameraTakePhoto => _t('camera.takePhoto');
  String get cameraGallery => _t('camera.gallery');
  String get cameraPreparing => _t('camera.preparing');
  String get cameraAddPatient => _t('camera.addPatient');
  String get cameraPhotoOptions => _t('camera.photoOptions');
  String get cameraViewFullscreen => _t('camera.viewFullscreen');
  String get cameraOpenShade => _t('camera.openShade');
  String get cameraOpenSmile => _t('camera.openSmile');
  String get cameraCaptureFocus => _t('camera.captureFocus');
  String get cameraRetryCamera => _t('camera.retryCamera');
  String get cameraSwitchCamera => _t('camera.switchCamera');
  String get cameraResetOverlay => _t('camera.resetOverlay');
  String get messagesLoadingConversations =>
      _t('messages.loadingConversations');
  String get messagesLoadingChat => _t('messages.loadingChat');
  String get messagesLoadingContacts => _t('messages.loadingContacts');
  String get messagesPhotoLibrary => _t('messages.photoLibrary');
  String get messagesCamera => _t('messages.camera');
  String get messagesVideoLibrary => _t('messages.videoLibrary');
  String get messagesRecordVideo => _t('messages.recordVideo');
  String get messagesDocument => _t('messages.document');
  String get messagesFilterAll => _t('messages.filterAll');
  String get messagesFilterDentists => _t('messages.filterDentists');
  String get messagesFilterLaboratories => _t('messages.filterLaboratories');
  String get mediaUploadItem => _t('media.uploadItem');
  String get mediaDeleteItem => _t('media.deleteItem');

  String get mediaUploadBody => _t('media.uploadBody');
  String get mediaUploadConfirm => _t('media.uploadConfirm');
  String get mediaDeleteBody => _t('media.deleteBody');
  String get authPasswordUpdatedRelogin => _t('auth.passwordUpdatedRelogin');

  String get commonUseThisDate => _t('common.useThisDate');
  String get commonSelectDate => _t('common.selectDate');
  String get commonPrevMonth => _t('common.prevMonth');
  String get commonNextMonth => _t('common.nextMonth');
  String get commonMinUppercase => _t('common.minUppercase');
  String get commonMinNumber => _t('common.minNumber');
  String get shadeManualOverride => _t('shade.manualOverride');
  String get shadeAllVita => _t('shade.allVita');
  String get shadeTargetShades => _t('shade.targetShades');
  String get shadeToothSamples => _t('shade.toothSamples');
  String get shadeGumShades => _t('shade.gumShades');
  String get shadeOverrideTeeth => _t('shade.overrideTeeth');
  String get shadeOverrideGum => _t('shade.overrideGum');

  // ── Dashboard leftovers ──────────────────────────────────────────────────
  String dashPatientsOnFile(int n) => n == 1
      ? _t('dash.patientsOnFileOne')
      : _t('dash.patientsOnFile').replaceAll('{n}', '$n');
  String dashNeedsAttention(int n) => n == 1
      ? _t('dash.needsAttentionOne')
      : _t('dash.needsAttention').replaceAll('{n}', '$n');
  String dashUnreadMessages(int n) => n == 1
      ? _t('dash.unreadMessagesOne')
      : _t('dash.unreadMessages').replaceAll('{n}', '$n');
  String dashPatientsAndCasesOnFile(int patients, int cases) => _t(
    'dash.patientsAndCasesOnFile',
  ).replaceAll('{patients}', '$patients').replaceAll('{cases}', '$cases');
  String dashAcrossCompleted(int n) =>
      _t('dash.acrossCompleted').replaceAll('{n}', '$n');
  String dashInProgressInReview(int inProgress, int inReview) =>
      _t('dash.inProgressInReview')
          .replaceAll('{inProgress}', '$inProgress')
          .replaceAll('{inReview}', '$inReview');
  String dashActivityCompleted(String label, String patient) => _t(
    'dash.activityCompleted',
  ).replaceAll('{label}', label).replaceAll('{patient}', patient);
  String dashActivityRejected(String patient) =>
      _t('dash.activityRejected').replaceAll('{patient}', patient);
  String dashActivityInReview(String patient) =>
      _t('dash.activityInReview').replaceAll('{patient}', patient);
  String dashActivityInProgress(String patient) =>
      _t('dash.activityInProgress').replaceAll('{patient}', patient);
  String dashActivityPending(String patient) =>
      _t('dash.activityPending').replaceAll('{patient}', patient);
  String dashActivityUpdated(String patient) =>
      _t('dash.activityUpdated').replaceAll('{patient}', patient);
  String get commonJustNow => _t('common.justNow');
  String commonMinAgo(int n) => _t('common.minAgo').replaceAll('{n}', '$n');
  String commonHourAgo(int n) => n == 1
      ? _t('common.hourAgo')
      : _t('common.hoursAgo').replaceAll('{n}', '$n');
  String commonDaysAgo(int n) => _t('common.daysAgo').replaceAll('{n}', '$n');

  // ── Patients share / access ──────────────────────────────────────────────
  String patientsShareTitle(String patient) =>
      _t('patients.shareTitle').replaceAll('{patient}', patient);
  String get patientsGrantAccess => _t('patients.grantAccess');
  String get patientsRequestAccess => _t('patients.requestAccess');
  String get patientsAsOwnerHint => _t('patients.asOwnerHint');
  String get patientsRequestAccessHint => _t('patients.requestAccessHint');
  String get patientsAllStaffHaveAccess => _t('patients.allStaffHaveAccess');
  String get patientsNoEligibleStaff => _t('patients.noEligibleStaff');
  String get patientsAccessGranted => _t('patients.accessGranted');
  String get patientsAccessRequestSubmitted =>
      _t('patients.accessRequestSubmitted');
  String get patientsCreatedBy => _t('patients.createdBy');
  String get patientsAccessLabel => _t('patients.accessLabel');
  String get patientsCreator => _t('patients.creator');
  String get patientsShared => _t('patients.shared');
  String get patientsOwner => _t('patients.owner');
  String get patientsOnlyOwnerApprove => _t('patients.onlyOwnerApprove');
  String get patientsOnlyOwnerManage => _t('patients.onlyOwnerManage');
  String get patientsWaitingOwnerReview => _t('patients.waitingOwnerReview');

  // ── Camera leftovers ─────────────────────────────────────────────────────
  String get cameraSubtitle => _t('camera.subtitle');
  String get cameraAngle => _t('camera.angle');
  String get cameraFrontal => _t('camera.frontal');
  String get cameraLeft => _t('camera.left');
  String get cameraRight => _t('camera.right');
  String get cameraFrontalSmile => _t('camera.frontalSmile');
  String get cameraLeftProfile => _t('camera.leftProfile');
  String get cameraRightProfile => _t('camera.rightProfile');
  String get cameraClinicalPhoto => _t('camera.clinicalPhoto');
  String get cameraEmptyPhotosHint => _t('camera.emptyPhotosHint');
  String get cameraNoPatientsCaptureHint => _t('camera.noPatientsCaptureHint');
  String get cameraAddPatientCaptureHint => _t('camera.addPatientCaptureHint');
  String cameraSwitchAngleHint(String angle) =>
      _t('camera.switchAngleHint').replaceAll('{angle}', angle);
  String cameraAngleLabel(String angle) {
    switch (angle.trim().toLowerCase()) {
      case 'frontal':
        return cameraFrontal;
      case 'left':
        return cameraLeft;
      case 'right':
        return cameraRight;
      default:
        return angle;
    }
  }

  String cameraClinicalAngleLabel(String angle) {
    switch (angle.trim().toLowerCase()) {
      case 'frontal':
        return cameraFrontalSmile;
      case 'left':
        return cameraLeftProfile;
      case 'right':
        return cameraRightProfile;
      case 'other':
        return cameraClinicalPhoto;
      default:
        return angle.isEmpty ? cameraClinicalPhoto : angle;
    }
  }

  // ── Shade leftovers ──────────────────────────────────────────────────────
  String get shadeSubtitle => _t('shade.subtitle');
  String get shadeUploadCloseUp => _t('shade.uploadCloseUp');
  String get shadeUploadToothPhoto => _t('shade.uploadToothPhoto');
  String get shadeAnalyzing => _t('shade.analyzing');
  String get shadeSession => _t('shade.session');
  String get shadeSavedShadesHint => _t('shade.savedShadesHint');
  String get shadeNoSavesYet => _t('shade.noSavesYet');
  String get shadeNoDetectionYet => _t('shade.noDetectionYet');
  String get shadeUploadToAnalyze => _t('shade.uploadToAnalyze');
  String get shadeAcceptAi => _t('shade.acceptAi');
  String shadeAcceptShade(String shade) =>
      _t('shade.acceptShade').replaceAll('{shade}', shade);
  String get shadeSaveOverride => _t('shade.saveOverride');
  String shadeSaveOverrideShade(String shade) =>
      _t('shade.saveOverrideShade').replaceAll('{shade}', shade);
  String get shadeResult => _t('shade.result');
  String get shadeToothSelection => _t('shade.toothSelection');
  String get shadeOverride => _t('shade.override');
  String shadeOverrideSelected(String shade) =>
      _t('shade.overrideSelected').replaceAll('{shade}', shade);
  String get shadeSelected => _t('shade.selected');
  String get shadeUploadToothFirst => _t('shade.uploadToothFirst');
  String get shadeGumShade => _t('shade.gumShade');
  String get shadeGumNotVita => _t('shade.gumNotVita');
  String get shadeNoGumDetected => _t('shade.noGumDetected');

  // ── Smile leftovers ──────────────────────────────────────────────────────
  String get smilePageSubtitle => _t('smile.pageSubtitle');
  String get smileLoadSmilePhoto => _t('smile.loadSmilePhoto');
  String get smileLoadSmileHint => _t('smile.loadSmileHint');
  String get smileLoadSmileHintPortrait => _t('smile.loadSmileHintPortrait');
  String get smilePlacement => _t('smile.placement');
  String get smileBatemModels => _t('smile.batemModels');
  String get smileModelOpen => _t('smile.modelOpen');
  String get smileModelClosed => _t('smile.modelClosed');
  String get smileUseThisModel => _t('smile.useThisModel');
  String get smileUpperJaw => _t('smile.upperJaw');
  String get smileLowerJaw => _t('smile.lowerJaw');
  String get patientsNoNotes => _t('patients.noNotes');
  String get patientsNoClinicalNotes => _t('patients.noClinicalNotes');
  String get appointmentsNoNotes => _t('appointments.noNotes');
  String get smileNudge => _t('smile.nudge');
  String get smileResetPlacement => _t('smile.resetPlacement');
  String get smileCenterShape => _t('smile.centerShape');
  String get smileSelectShapeHint => _t('smile.selectShapeHint');
  String get smileOriginalPhoto => _t('smile.originalPhoto');

  // ── Notifications leftovers ──────────────────────────────────────────────
  String get notificationsMarkedAllRead => _t('notifications.markedAllRead');
  String get notificationsNow => _t('notifications.now');
  String notificationsMinsShort(int n) =>
      _t('notifications.minsShort').replaceAll('{n}', '$n');
  String notificationsHoursShort(int n) =>
      _t('notifications.hoursShort').replaceAll('{n}', '$n');
  String notificationsDaysShort(int n) =>
      _t('notifications.daysShort').replaceAll('{n}', '$n');
  String notificationsMoreCount(int n) =>
      _t('notifications.moreCount').replaceAll('{n}', '$n');

  /// Remap known English API notification bodies to the active locale.
  String localizeNotificationMessage(
    String message, {
    String? type,
    String? patientName,
  }) {
    final msg = message.trim();
    if (msg.isEmpty) return msg;

    String fill(String key, Map<String, String> vars) {
      var out = _t(key);
      for (final e in vars.entries) {
        out = out.replaceAll('{${e.key}}', e.value);
      }
      return out;
    }

    Match? m;

    m = RegExp(
      r"^Access approved for (.+)\. You can open this patient record\.$",
    ).firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgAccessApproved', {'name': m[1]!});
    }
    m = RegExp(r"^You approved (.+)'s access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouApprovedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^Access to (.+) was declined\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgAccessDeclined', {'name': m[1]!});
    }
    m = RegExp(
      r"^You declined (.+)'s request to access (.+)\.$",
    ).firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouDeclinedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^(.+) granted you access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgGrantedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^You granted (.+) access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouGrantedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^(.+) requested access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgRequestedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^You requested access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouRequestedAccess', {'name': m[1]!});
    }
    m = RegExp(r"^Your access to (.+) was revoked\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgAccessRevoked', {'name': m[1]!});
    }
    m = RegExp(r"^You revoked (.+)'s access to (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouRevokedAccess', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }

    m = RegExp(r"^You booked an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouBookedAppt', {'name': m[1]!});
    }
    m = RegExp(r"^(.+) booked an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgBookedAppt', {'who': m[1]!, 'name': m[2]!});
    }
    m = RegExp(r"^You cancelled an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouCancelledAppt', {'name': m[1]!});
    }
    m = RegExp(r"^(.+) cancelled an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgCancelledAppt', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^You updated an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgYouUpdatedAppt', {'name': m[1]!});
    }
    m = RegExp(r"^(.+) updated an appointment for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgUpdatedAppt', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }

    m = RegExp(r"^(.+) uploaded a 3D scan for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgUploadedScan', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^(.+) saved a shade photo for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgSavedShade', {'who': m[1]!, 'name': m[2]!});
    }
    m = RegExp(r"^(.+) saved a smile preview for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgSavedSmile', {'who': m[1]!, 'name': m[2]!});
    }
    m = RegExp(r"^(.+) added a file for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgAddedFile', {'who': m[1]!, 'name': m[2]!});
    }

    m = RegExp(r"^Scan quality issue for ([^.]+)\.(.*)$").firstMatch(msg);
    if (m != null) {
      final detail = m[2]!.trim();
      if (detail.isEmpty) {
        return fill('notifications.msgScanQuality', {'name': m[1]!});
      }
      return fill('notifications.msgScanQualityDetail', {
        'name': m[1]!,
        'detail': detail,
      });
    }
    m = RegExp(r"^New scan uploaded for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgNewScan', {'name': m[1]!});
    }
    m = RegExp(
      r"^New patient on file: (.+) \(awaiting scan\)\.$",
    ).firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgNewPatient', {'name': m[1]!});
    }

    // Non-EN: type + patient fallback when body is still English/unknown.
    final name = (patientName ?? '').trim();
    if (code != 'en' && name.isNotEmpty && type != null && type.isNotEmpty) {
      switch (type) {
        case 'scan_quality':
          return fill('notifications.fallbackScanQuality', {'name': name});
        case 'shade':
          return fill('notifications.fallbackShade', {'name': name});
        case 'appointment':
          return fill('notifications.fallbackAppointment', {'name': name});
        case 'case_status':
          return fill('notifications.fallbackCase', {'name': name});
        case 'scan_body':
          return fill('notifications.fallbackScanBody', {'name': name});
        case 'sync':
          return fill('notifications.fallbackSync', {'name': name});
        case 'export':
          return fill('notifications.fallbackExport', {'name': name});
      }
    }

    return msg;
  }

  // ── Patient picker chip ──────────────────────────────────────────────────
  String get patientReadyForDetect => _t('patient.readyForDetect');
  String get patientNoneYet => _t('patient.noneYet');
  String patientAvailableCount(int n) =>
      _t('patient.availableCount').replaceAll('{n}', '$n');
  String patientCaseId(Object id) =>
      _t('patient.caseId').replaceAll('{id}', '$id');
  String patientFallbackId(Object id) =>
      _t('patient.fallbackId').replaceAll('{id}', '$id');
  String get patientEmptyHint => _t('patient.emptyHint');

  // ── Scans quality / preview hints ────────────────────────────────────────
  String get scansQualityNeedPatient => _t('scans.qualityNeedPatient');
  String get scansQualityNeedUpload => _t('scans.qualityNeedUpload');
  String get scansSimulatorPickTitle => _t('scans.simulatorPickTitle');
  String get scansSimulatorPickHint => _t('scans.simulatorPickHint');
  String get scansSimulatorPickEmpty => _t('scans.simulatorPickEmpty');
  String get scansNeedMeshFile => _t('scans.needMeshFile');
  String get scansCouldNotReadFile => _t('scans.couldNotReadFile');
  String get scansUploadPreviewHint => _t('scans.uploadPreviewHint');
  String get scansEmptyHintUpload => _t('scans.emptyHintUpload');

  // ── Chairside interpreter (doctor ↔ patient, not UI language) ────────────
  String get interpreterSubtitle => _t('interpreter.subtitle');
  String get interpreterDoctor => _t('interpreter.doctor');
  String get interpreterPatient => _t('interpreter.patient');
  String get interpreterDoctorLanguage => _t('interpreter.doctorLanguage');
  String get interpreterPatientLanguage => _t('interpreter.patientLanguage');
  String get interpreterDoctorHint => _t('interpreter.doctorHint');
  String get interpreterPatientHint => _t('interpreter.patientHint');
  String get interpreterHoldToTalk => _t('interpreter.holdToTalk');
  String get interpreterListening => _t('interpreter.listening');
  String get interpreterTypeInstead => _t('interpreter.typeInstead');
  String get interpreterAllowSpeech => _t('interpreter.allowSpeech');
  String get interpreterAppleTranslateFailed =>
      _t('interpreter.appleTranslateFailed');
  String get interpreterTypeHint => _t('interpreter.typeHint');
  String get interpreterSend => _t('interpreter.send');
  String get interpreterSpeak => _t('interpreter.speak');
  String get interpreterSwap => _t('interpreter.swap');
  String get interpreterClear => _t('interpreter.clear');
  String get interpreterHistory => _t('interpreter.history');
  String interpreterPackTitle(String lang) =>
      _t('interpreter.packTitle').replaceAll('{lang}', lang);
  String get interpreterToneUnchecked => _t('interpreter.toneUnchecked');
  String get interpreterPackBody => _t('interpreter.packBody');
  String get interpreterPackDownload => _t('interpreter.packDownload');
  String get interpreterPackOnline => _t('interpreter.packOnline');
  String get interpreterPackFailed => _t('interpreter.packFailed');
  String get interpreterAutoSpeak => _t('interpreter.autoSpeak');
  String get interpreterTtsFailed => _t('interpreter.ttsFailed');
  String get interpreterNothingHeard => _t('interpreter.nothingHeard');
  String interpreterNothingHeardLang(String lang) =>
      _t('interpreter.nothingHeardLang').replaceAll('{lang}', lang);
  String get interpreterNoVoice => _t('interpreter.noVoice');
  String get interpreterSearchLanguage => _t('interpreter.searchLanguage');
  String get interpreterClinicLanguages => _t('interpreter.clinicLanguages');
  String get interpreterAllLanguages => _t('interpreter.allLanguages');
  String get interpreterPatientOptional => _t('interpreter.patientOptional');

  static const _en = <String, String>{
    'nav.dashboard': 'Dashboard',
    'nav.patients': 'Patients',
    'nav.newPatient': 'New Patient',
    'nav.appointments': 'Appointments',
    'nav.camera': 'Camera',
    'nav.scans': 'Scans',
    'nav.shade': 'Shade Detection',
    'nav.smilePreview': 'Smile Preview',
    'nav.interpreter': 'Interpreter',
    'nav.scanBody': 'Scan Body',
    'nav.messages': 'Messages',
    'nav.laboratories': 'System Users',
    'nav.notifications': 'Notifications',
    'nav.reports': 'Reports',
    'lab.tx.ourDentistAsks': '{dentist} from your lab wants to share {p} with {to}. Forward it, or reject it.',
    'lab.tx.theirDentistAsks': '{dentist} at {from} wants to share {p} with {to}.',
    'lab.tx.waitingForThem': 'Sent to {to}. Waiting for them to accept.',
    'lab.tx.shareWithUs': '{from} wants to share {p} with your lab. Accept it and choose one of your dentists.',
    'lab.tx.handoverToUs': '{from} wants to hand {p} over to your lab. Accept it and choose one of your dentists.',
    'lab.tx.theyAccepted': '{to} accepted {p}.',
    'lab.tx.theyAcceptedFor': '{to} accepted {p} for {for}.',
    'lab.tx.weAccepted': 'Your lab accepted {p}.',
    'lab.tx.weAcceptedFor': 'Your lab accepted {p} for {for}.',
    'lab.tx.declined': 'The request for {p} was declined.',
    'lab.tx.cancelled': 'The request for {p} was cancelled.',
    'avatar.optionalLab': 'Optional for labs. You can\'t change it after signing up.',
    'chat.cantMessage': 'You can\'t message this person.',
    'join.title': 'Choose your lab',
    'join.sub': 'Ask a lab to accept you, or continue without a lab for now.',
    'join.request': 'Request to join',
    'join.confirmTitle': 'Ask {lab} to accept you?',
    'join.confirmMsg': 'The lab gets your request and decides. You can withdraw it while it\'s waiting.',
    'join.sent': 'Request sent to {lab}',
    'join.waiting': 'Waiting for {lab} to accept',
    'join.waitingSub': 'You can use the app as soon as the lab accepts you.',
    'join.sentAt': 'Sent {when}',
    'join.withdraw': 'Withdraw',
    'join.withdrawTitle': 'Withdraw your request?',
    'join.withdrawMsg': 'You can then ask this lab again, or another one.',
    'join.withdrawn': 'Request withdrawn',
    'join.checkAgain': 'Check again',
    'join.noLabs': 'No labs to choose yet',
    'join.noLabsSub': 'Ask your lab to sign up, or contact the admin.',
    'join.noLabError': 'Join a lab before adding patients.',
    'join.requestLater': 'Request later',
    'join.requestLaterTitle': 'Continue without a lab?',
    'join.requestLaterMsg': 'You can use the app and add patients now. Join a lab anytime from Settings.',
    'join.requestLaterDone': 'You can join a lab later from Settings',
    'join.bringTitle': 'Bring patients?',
    'join.bringMsg': 'Selected patients will be shared with the lab when they accept. Others stay private.',
    'join.bringNone': 'None',
    'join.bringContinue': 'Continue ({n})',
    'join.settingsSection': 'Lab',
    'join.settingsJoin': 'Join a lab',
    'join.settingsJoinSub': 'Pick a lab to request membership',
    'join.settingsLab': 'Your lab: {lab}',
    'join.pendingTitle': 'Join request pending',
    'join.transferTitle': 'Transfer to another lab',
    'join.transferSub': 'Your current lab must approve the move.',
    'join.transferRequest': 'Request transfer',
    'join.transferConfirmTitle': 'Ask to transfer to {lab}?',
    'join.transferConfirmMsg': 'Your current lab will approve or reject. If approved, you leave your lab and join the new one.',
    'join.transferSent': 'Transfer request sent (waiting on your lab)',
    'join.transferWaiting': 'Waiting for approval to join {lab}',
    'join.transferPendingTitle': 'Transfer pending',
    'join.withdrawTransferTitle': 'Withdraw transfer request?',
    'join.withdrawTransferMsg': 'You can request a transfer again later.',
    'join.transferWithdrawn': 'Transfer request withdrawn',
    'share.yourLab': 'Your lab',
    'share.yourLabHint': 'Shared right away.',
    'share.labHasAccess': 'Your lab already has access.',
    'share.colleagues': 'Colleagues in your lab',
    'share.colleaguesHint': 'Sent to your lab for approval.',
    'share.noColleagues': 'No colleagues to share with.',
    'share.alreadyShared': 'Already shared',
    'share.alreadySharedHint': 'Who has access, or is waiting for the lab to approve.',
    'share.pendingLab': 'Waiting for lab',
    'nav.lab': 'My lab',
    'lab.title': 'My lab',
    'lab.sub': 'Your dentists, requests, transfers and visibility',
    'lab.tab.dentists': 'Dentists',
    'lab.tab.requests': 'Requests',
    'lab.tab.transfers': 'Transfers',
    'lab.tab.sharing': 'Sharing',
    'lab.tab.settings': 'Settings',
    'lab.noDentists': 'No dentists yet',
    'lab.noDentistsSub': 'Dentists you accept, or the admin assigns, appear here.',
    'lab.requestRemoval': 'Request removal',
    'lab.removeTitle': 'Remove {name} from your lab?',
    'lab.removeMsg': 'The admin decides. Say why — the admin sees your reason.',
    'lab.reasonRequired': 'Reason (required)',
    'lab.removalSent': 'Removal of {name} sent to the admin',
    'lab.noRequests': 'No requests',
    'lab.noRequestsSub': 'Dentists asking to join, and your removal requests, show up here.',
    'lab.joinRequests': 'Join requests',
    'lab.transferRequests': 'Transfer requests',
    'lab.transferBadge': 'Transfer',
    'lab.transferTo': 'Wants to move to {lab}',
    'lab.bringCount': 'Bringing {n} patients',
    'lab.dentistXferAccepted': 'Transfer for {name} approved',
    'lab.dentistXferRejected': 'Transfer for {name} rejected',
    'lab.ourRemovals': 'Your removal requests',
    'lab.accept': 'Accept',
    'lab.joinAccepted': '{name} joined your lab',
    'lab.joinRejected': 'Request from {name} rejected',
    'lab.status.pending': 'Pending',
    'lab.status.approved': 'Approved',
    'lab.status.rejected': 'Rejected',
    'lab.noTransfers': 'No transfers',
    'lab.noTransfersSub': 'Patients shared or handed over between labs show up here.',
    'lab.kind.share': 'Share',
    'lab.kind.handover': 'Handover',
    'lab.transfer.awaiting_sender': 'Waiting for you to forward',
    'lab.transfer.awaiting_recipient': 'Waiting for the receiving lab',
    'lab.transfer.accepted': 'Accepted',
    'lab.transfer.rejected': 'Rejected',
    'lab.transfer.cancelled': 'Cancelled',
    'lab.requestedBy': 'by {n}',
    'lab.forDentist': 'for {n}',
    'lab.openPatient': 'Open patient',
    'lab.forward': 'Forward',
    'lab.forwarded': 'Forwarded to {lab}',
    'lab.rejectTransferTitle': 'Reject the transfer of {p}?',
    'lab.transferRejected': 'Transfer rejected',
    'lab.acceptTransfer': 'Accept and choose a dentist',
    'lab.acceptTransferMsg': 'Which of your dentists takes {p}?',
    'lab.transferAccepted': '{p} accepted for {d}',
    'lab.noTickets': 'No sharing tickets',
    'lab.noTicketsSub': 'When a dentist wants to share a patient with a colleague in your lab, you approve it here.',
    'lab.ticketLine': '{from} wants to share this patient with {to}.',
    'lab.ticketApproved': 'Sharing approved',
    'lab.ticketRejected': 'Sharing rejected',
    'lab.hideLab': 'Hide us from other labs and new dentists',
    'lab.hideLabMsg': 'Hidden labs don\'t appear when dentists pick a lab or start a transfer. You then only get dentists the admin assigns to you.',
    'lab.hideDentists': 'Hide our dentists from other labs',
    'lab.hideDentistsMsg': 'Other labs won\'t see your dentists listed under your lab.',
    'lab.patientFor': 'Who is this patient for?',
    'lab.assignDentist': 'Assign to dentist',
    'lab.sendToLab': 'Send to another lab',
    'lab.sendToLabMsg': 'The other lab accepts the patient and picks one of its dentists.',
    'lab.chooseDentist': 'Choose a dentist…',
    'lab.chooseLab': 'Choose a lab…',
    'lab.targetRequired': 'Choose a dentist or a lab for this patient.',
    'lab.assignMsg': '{p} moves to this dentist.',
    'lab.assigned': '{p} assigned to {d}',
    'lab.assignForbidden': 'Your lab wasn\'t given this patient.',
    'share.sentToLab': 'Sent to your lab for approval',
    'share.useTransfer': 'That person is in another lab — use "Share with another lab" instead.',
    'share.otherLab': 'Share with another lab',
    'share.otherLabMsg': 'Your lab forwards the request; the other lab accepts it and picks a dentist.',
    'share.transferSent': 'Request to share with {lab} sent to your lab',
    'nav.review': 'Review',
    'case.title': 'Case',
    'case.noLab': 'No lab yet',
    'case.labShared': 'Lab: {lab} · shared',
    'case.labNotShared': 'Lab: {lab} · not shared yet',
    'case.item.scan': 'Scan',
    'case.item.shade': 'Shade analysis',
    'case.item.smile': 'Smile preview',
    'case.submit': 'Submit to lab',
    'case.submitReadyTitle': 'Submit this case to the lab?',
    'case.submitReadyMsg': 'Scan, shade and smile are saved on the case and shared with your lab.',
    'case.submitted': 'Sent to the lab for review',
    'case.submitFailed': 'Couldn\'t submit',
    'case.incompleteTitle': 'Some items are missing',
    'case.incompleteMsg': 'Missing: {items}. The lab may reject an incomplete case. Submit anyway?',
    'case.submitAnyway': 'Submit anyway',
    'case.approve': 'Approve',
    'case.reject': 'Reject',
    'case.approveTitle': 'Approve this case?',
    'case.approveMsg': 'The case is marked completed and the dentist is notified.',
    'case.rejectTitle': 'Reject this case',
    'case.rejectMsg': 'Overall remarks plus per-item feedback. The dentist sees this on the patient and on scan, shade and smile.',
    'case.remarksRequired': 'Overall remarks (required)',
    'case.itemFeedback': 'Per item',
    'case.itemOk': 'Good to go',
    'case.itemNeedsWork': 'Needs work',
    'case.itemNoteHint': 'What should change?',
    'case.resubmit': 'Resubmit to lab',
    'case.resubmitReadyTitle': 'Resubmit this case to the lab?',
    'case.resubmitReadyMsg': 'You changed the case since the lab rejected it. The lab will review it again.',
    'case.resubmitUnchangedTitle': 'Nothing changed yet',
    'case.resubmitUnchangedMsg': 'You haven\'t changed anything since the lab rejected this case. Resubmit anyway?',
    'case.resolveFirst': 'Accept or dismiss the lab\'s suggestions before resubmitting.',
    'case.updatedChip': 'Updated by dentist',
    'case.suggested': '{lab} suggested a change to the {item}',
    'case.view': 'View',
    'case.accept': 'Accept',
    'case.dismiss': 'Dismiss',
    'case.dismissTitle': 'Dismiss the lab\'s suggestion?',
    'case.dismissMsg': 'Your current {item} stays on the case. The lab will see this when you resubmit.',
    'case.acceptedToast': 'Suggestion accepted — resubmit when ready',
    'case.dismissedToast': 'Suggestion dismissed',
    'case.approveBlocked': 'You suggested changes, so the dentist must confirm them — reject to send it back.',
    'case.remarksLabChanged': 'Overall remarks (optional — "Lab made changes, please confirm")',
    'case.feedbackTitle': 'Lab review · {item}',
    'case.feedbackSub': 'Mark this item, then reject or approve from the case.',
    'case.feedbackSuggested': 'You suggested a change — the dentist will confirm it.',
    'case.saveNote': 'Save note',
    'p.waitingLab': 'Waiting for lab approval',
    'p.withdraw': 'Withdraw',
    'case.event.lab_suggested': 'Lab suggested a change',
    'case.event.suggestion_accepted': 'Suggestion accepted',
    'case.event.suggestion_dismissed': 'Suggestion dismissed',
    'case.openTool': 'Open {item}',
    'case.approvedToast': 'Case approved',
    'case.rejectedToast': 'Case rejected and sent back',
    'case.rejectedBanner': 'Rejected by the lab',
    'case.reopenTitle': 'Reopen this case?',
    'case.reopenMsg': 'This reopens the case and sends it back to the lab for review.',
    'case.reopenGo': 'Reopen',
    'case.replace': 'Replace',
    'case.replaceShadeHint': 'Choose a new photo. Saving its analysis replaces the old one.',
    'case.replacingShade': 'Replacing a saved shade analysis — save the new one to swap it in.',
    'case.replacingSmile': 'Replacing a saved smile preview — save the new one to swap it in.',
    'case.history': 'Case history',
    's.formats': 'Upload a PLY, STL or OBJ file with the button above.',
    'settings.sub': 'Account, preferences and app information',
    'settings.sec.account': 'Account & security',
    'settings.sec.myLab': 'My lab',
    'settings.sec.rejectSub': 'Emails that can\'t sign up or sign in. Remove one to let them register again.',
    'pick.search': 'Search by name or clinic',
    'pick.none': 'No matches',
    'admin.chooseDentistCount': 'Choose a dentist… ({n})',
    'interpreter.loadingVoice': 'Loading voice…',
    'lab.pickItem': 'Select an item',
    'lab.pickItemSub': 'Its details and actions appear here.',
    'admin.moreCount': '+{n} more',
    'interpreter.quickPhrases': 'Quick phrases',
    'interpreter.stopSpeaking': 'Stop',
    'interpreter.hold': 'Hold',
    'ch.filterAll': 'All',
    'ch.filterLabs': 'Labs',
    'ch.filterDentists': 'Dentists',
    'lab.pickDentist': 'Select a dentist',
    'lab.pickDentistSub': 'Their contact details, patients and quick actions appear here.',
    'lab.dentistNoPatients': 'No patients from this dentist yet.',
    'p.pickTitle': 'Select a patient',
    'p.pickSub': 'Their case, records and details appear here.',
    'case.items': 'On this case',
    'case.saved': 'Saved',
    'case.missing': 'Missing',
    'case.tileSuggested': 'You suggested a change',
    'case.message': 'Message',
    'case.historyCount': 'Case history ({n})',
    'case.hintInReview': 'Waiting for your decision',
    'case.hintRejected': 'Sent back to the dentist. You can still approve it or update your feedback.',
    'case.updateFeedback': 'Update feedback',
    'case.approveRejectedMsg': 'You sent this case back earlier. Approving marks it completed and notifies the dentist.',
    'records.bestShade': 'Best match',
    'records.dentistPick': 'Chosen by dentist',
    'records.aiPick': 'AI match, confirmed',
    'records.aiWas': 'AI suggested {shade}',
    'records.preview': 'Preview',
    'records.openAll': 'Open',
    'case.event.created': 'Created',
    'case.event.scan_added': 'Scan added',
    'case.event.submitted': 'Submitted to lab',
    'case.event.updated': 'Updated',
    'case.event.reopened': 'Reopened',
    'case.event.approved': 'Approved',
    'case.event.rejected': 'Rejected',
    'case.event.admin_override': 'Status changed by admin',
    'case.event.reassigned': 'Reassigned',
    'case.event.lab_left': 'Left the lab',
    'review.title': 'Review',
    'review.sub': 'Cases waiting for your decision',
    'review.empty': 'Nothing to review',
    'review.emptySub': 'Cases your dentists submit show up here.',
    'review.pick': 'Select a case',
    'review.pickSub': 'Its records and history appear here.',
    'review.tab.in_review': 'Under review',
    'review.tab.rejected': 'Rejected',
    'review.tab.completed': 'Accepted',
    'review.emptyRejected': 'No rejected cases',
    'review.emptyRejectedSub': 'Cases you reject show up here until the dentist resubmits.',
    'review.emptyCompleted': 'No accepted cases yet',
    'review.emptyCompletedSub': 'Cases you approve show up here.',
    'c.copied': 'Copied',
    'avatar.cropTitle': 'Move and scale',
    'avatar.cropDone': 'Choose',
    'avatar.cropHint': 'Pinch to zoom and drag to position the photo inside the circle.',
    'avatar.cropFailed': 'This image couldn\'t be opened. Try another one.',
    'avatar.pickTitle': 'Profile photo',
    'avatar.takePhoto': 'Take photo',
    'avatar.chooseLibrary': 'Choose from library',
    'avatar.add': 'Add a profile photo',
    'avatar.retake': 'Change photo',
    'avatar.permanent': 'Shown to people you work with. You can\'t change it after signing up.',
    'avatar.required': 'Please add a profile photo.',
    'avatar.change': 'Change photo',
    'avatar.changed': 'Photo updated for {name}',
    'avatar.changeMine': 'Change my photo',
    'avatar.changedMine': 'Your photo was updated',
    'avatar.done': 'Done',
    'admin.chatPlaceholder': 'Message…',
    'admin.chatEmpty': 'No messages yet. Say hello.',
    'admin.send': 'Send',
    'admin.chatPhoto': 'Photo',
    'admin.chatVoice': 'Voice message',
    'admin.chatVideo': 'Video',
    'admin.chatDocument': 'Document',
    'admin.pill.removalsOne': '1 removal request',
    'admin.waitingCountOne': '1 waiting for approval',
    'admin.att.patientsOne': '1 unassigned patient',
    'admin.att.removalsOne': '1 removal request',
    'admin.att.dentistsOne': '1 dentist without a lab',
    'admin.att.rejectedOne': '1 rejected case',
    'admin.noChats': 'No conversations yet',
    'admin.openMessages': 'Open',
    'admin.unreadCount': '{n} unread',
    'admin.quickChatSub': 'Your latest conversations',
    'admin.quickChat': 'Quick chat',
    'admin.cases': 'cases',
    'admin.col.status': 'Status',
    'admin.col.patient': 'Patient',
    'admin.recentPatientsSub': 'Latest case updates across all labs',
    'admin.recentPatients': 'Recent patient activity',
    'admin.qa.rejectList': 'Reject list',
    'admin.qa.patients': 'Reassign patients',
    'admin.qa.assign': 'Assign dentists',
    'admin.qa.signups': 'Review signups',
    'admin.quickActions': 'Quick actions',
    'admin.sev.low': 'Info',
    'admin.sev.medium': 'Soon',
    'admin.sev.high': 'Urgent',
    'admin.att.none': 'Nothing needs you right now',
    'admin.att.rejectedSub': 'Waiting for the dentist to rework them.',
    'admin.att.rejected': '{n} rejected cases',
    'admin.att.dentistsSub': 'They can\'t work until they have a lab.',
    'admin.att.dentists': '{n} dentists without a lab',
    'admin.att.removalsSub': 'Labs are waiting for your decision.',
    'admin.att.removals': '{n} removal requests',
    'admin.att.patientsSub': 'Reassign them to a lab so someone owns the case.',
    'admin.att.patients': '{n} unassigned patients',
    'admin.attentionSub': 'Things only you can resolve',
    'admin.attention': 'Needs attention',
    'admin.waitingCount': '{n} waiting for approval',
    'admin.tile.openCases': 'Open cases',
    'admin.pill.inReview': '{n} in review',
    'admin.pill.removals': '{n} removal requests',
    'admin.pill.noLab': '{n} without lab',
    'admin.pill.clear': 'All clear',
    'admin.pill.review': 'Needs review',
    'admin.signOutTitle': 'Sign out of the admin account?',
    'admin.allNotifications': 'All notifications',
    'admin.markAllRead': 'Mark all read',
    'admin.showInUsers': 'Show in Users',
    'admin.searchHint': 'Search dentists, labs, clinics…',
    'admin.hiEvening': 'Good evening, {name}',
    'admin.hiAfternoon': 'Good afternoon, {name}',
    'admin.hiMorning': 'Good morning, {name}',
    'admin.since': 'since {when}',
    'admin.unassigned.no_lab': 'Approved without a lab',
    'admin.unassigned.removed': 'Removed from lab',
    'admin.unassigned.lab_deleted': 'Lab deleted',
    'admin.reassignedTo': '{name} assigned to {dentist} at {lab}',
    'admin.noDentistLabChooses': 'No dentist: {lab} chooses',
    'admin.pickDentistMsg': 'Optional. Without a dentist, the patient waits for {lab} to choose one.',
    'admin.pickDentistTitle': 'Assign to a dentist at {lab}?',
    'admin.fromOwner': 'from {name}',
    'admin.waitingFor': 'Waiting for {lab}',
    'admin.reactivated': '{name} reactivated',
    'admin.reactivateMsg': 'They can sign in again. Nothing was removed while the account was deactivated.',
    'admin.reactivateTitle': 'Reactivate {name}?',
    'admin.reactivate': 'Reactivate',
    'nav.signups': 'Signups',
    'errors.registrationRejected': 'Your registration was rejected by the administrator. You can\'t sign up or sign in with this email. Contact support if you think this is a mistake.',
    'auth.rejectedTitle': 'Registration rejected',
    'admin.dashTitle': 'Admin overview',
    'labDash.sub': 'Here\'s what\'s waiting on your lab today.',
    'labDash.searchHint': 'Search your dentists and patients',
    'labDash.tile.transfers': 'Transfers for you',
    'labDash.tile.joins': 'Join requests',
    'labDash.tile.tickets': 'Sharing requests',
    'labDash.tile.review': 'Cases to review',
    'labDash.action': 'Needs your action',
    'labDash.actionNone': 'Nothing is waiting on your lab.',
    'labDash.row.transfer': 'Patient transfer — accept or decline',
    'labDash.row.join': 'Wants to join your lab',
    'labDash.row.ticket': '{from} wants to share with {to}',
    'labDash.review': 'Review queue',
    'labDash.dentists': 'Your dentists',
    'dash.sub': 'Your chairside queue for today.',
    'dash.searchHint': 'Search your patients',
    'dash.tile.attention': 'Needs attention',
    'dash.tile.today': 'Appointments today',
    'dash.tile.messages': 'Unread messages',
    'dash.tile.rejected': 'Rejected cases',
    'dash.pill.noneToday': 'None today',
    'dash.quickActions': 'Quick actions',
    'dash.quickActionsSub': 'Jump into your daily tools',
    'dash.qa.newPatient': 'New patient',
    'dash.qa.camera': 'Camera',
    'dash.qa.shade': 'Shade detection',
    'dash.qa.scans': 'Scans',
    'dash.qa.smile': 'Smile preview',
    'dash.qa.appointments': 'Appointments',
    'dash.attention': 'Needs attention',
    'dash.attentionNone': 'Nothing needs your attention right now.',
    'dash.recentPatients': 'Recent patients',
    'dash.recentPatientsSub': 'Latest updates on your roster',
    'share.whoHasAccess': 'Who has access',
    'share.onlyOwner': 'Only the owner has access so far.',
    'share.ownerSection': 'Owner',
    'share.sharedWithSection': 'Shared with',
    'share.youHaveAccess': 'You have shared access to this patient.',
    'share.yourAccess': 'Your access',
    'appt.dentist': 'Dentist',
    'appt.assignDentist': 'Assign a dentist',
    'admin.dashSub': 'Here\'s what\'s happening across labs, dentists and cases today.',
    'admin.tile.signups': 'Pending signups',
    'admin.tile.dentists': 'Dentists',
    'admin.tile.labs': 'Labs',
    'admin.tile.unassignedDentists': 'Unassigned dentists',
    'admin.tile.unassignedPatients': 'Unassigned patients',
    'admin.tile.removals': 'Removal requests',
    'admin.casesByStatus': 'Cases by status',
    'admin.casesTotal': '{n} cases in total',
    'admin.signupQueue': 'Signup requests',
    'admin.seeAll': 'See all',
    'admin.loadFailed': 'Couldn\'t load this',
    'admin.retry': 'Try again',
    'admin.signupsTitle': 'Signups',
    'admin.signupsSub': 'Approve or reject every new account',
    'admin.pending': 'Pending',
    'admin.rejectList': 'Reject list',
    'admin.noSignups': 'No signups waiting',
    'admin.noSignupsSub': 'New dentist and lab signups show up here for approval.',
    'admin.noRejected': 'The reject list is empty',
    'admin.noRejectedSub': 'Emails you reject are listed here.',
    'admin.approve': 'Approve',
    'admin.reject': 'Reject',
    'admin.continue': 'Continue',
    'admin.approveTitle': 'Approve {name}?',
    'admin.approveDentistMsg': 'Optionally choose their lab. Without one, they pick a lab when they first sign in, and that lab has to accept them.',
    'admin.approveNoLab': 'Approve without a lab',
    'admin.approveLabMsg': 'The lab can sign in right away.',
    'admin.approved': '{name} approved',
    'admin.rejectTitle': 'Reject {name}?',
    'admin.rejectReasonMsg': 'Add a reason (optional). It is included in the email we send them.',
    'admin.reasonOptional': 'Reason (optional)',
    'admin.rejectConfirmTitle': 'Reject this signup?',
    'admin.rejectConfirmMsg': 'The account is deleted and {email} goes on the reject list. They get an email saying so, and can\'t sign up or sign in with it until you remove it from the list.',
    'admin.rejected': '{name} rejected',
    'admin.clinic': 'Clinic',
    'admin.signedUp': 'Signed up {when}',
    'admin.reason': 'Reason',
    'admin.noReason': 'none given',
    'admin.rejectedBy': 'Rejected {when} by {by}',
    'admin.unreject': 'Remove from list',
    'admin.unrejectTitle': 'Remove from the reject list?',
    'admin.unrejectMsg': '{email} will be able to sign up again. This doesn\'t approve them: a new signup still needs your approval.',
    'admin.unrejected': '{email} removed from the reject list',
    'admin.usersSub': 'Labs and their dentists',
    'admin.byLab': 'By lab',
    'admin.unassignedDentists': 'Unassigned',
    'admin.removalRequests': 'Removal requests',
    'admin.searchUsers': 'Search labs, dentists, clinics, emails…',
    'admin.noLabs': 'No labs yet',
    'admin.noLabsSub': 'Approved labs appear here with their dentists.',
    'admin.noMatches': 'No matches',
    'admin.noMatchesSub': 'Try another name, clinic or email.',
    'admin.dentistCount': '{n} dentists',
    'admin.dentistCountOne': '1 dentist',
    'admin.hidden': 'Hidden',
    'admin.hiddenFromLabs': 'Hidden from other labs',
    'admin.dentistsHidden': 'Dentists hidden',
    'admin.labNoDentists': 'No dentists in this lab yet.',
    'admin.noLab': 'No lab',
    'admin.noClinic': 'No clinic',
    'admin.deactivatedBadge': 'Deactivated',
    'admin.assignLab': 'Assign to lab',
    'admin.move': 'Move',
    'admin.more': 'More',
    'admin.deactivateOrDelete': 'Deactivate or delete…',
    'admin.moveTitle': 'Move {name}',
    'admin.moveMsg': 'Choose the lab this dentist belongs to.',
    'admin.removeFromLab': 'Remove from their lab',
    'admin.moveConfirmTitle': 'Move {name} to {lab}?',
    'admin.moveNoApproval': '{lab} doesn\'t need to approve this.',
    'admin.leaveLabEffects': '{lab} loses access to this dentist\'s open cases, and any case under review goes back to "in progress". {lab} keeps view-only access to completed cases.',
    'admin.removeEffects': 'The dentist keeps their patients and can keep using the app, but without a lab they can\'t submit cases or share through a lab. They\'re asked to choose a lab, or you can assign one from Unassigned.',
    'admin.removeTitle': 'Remove {name} from their lab?',
    'admin.remove': 'Remove',
    'admin.moved': '{name} moved to {lab}',
    'admin.removedFromLab': '{name} removed from their lab',
    'admin.deleteTitle': 'Delete {name}?',
    'admin.deleteDentistEffects': 'Deactivate: they can\'t sign in. Everything is kept, and you can reactivate the account at any time.\n\nDelete permanently: can\'t be undone. Their patients are kept and become unassigned (Patients › Unassigned).',
    'admin.deleteLabEffects': 'Deactivate: the lab can\'t sign in. Everything is kept, and you can reactivate it at any time.\n\nDelete permanently: can\'t be undone. Its {n} become unassigned, and cases it was reviewing go back to "in progress". Patients are not affected.',
    'admin.deactivate': 'Deactivate',
    'admin.deletePermanently': 'Delete permanently',
    'admin.deactivated': '{name} deactivated',
    'admin.deleted': '{name} deleted',
    'admin.noUnassignedDentists': 'Every dentist has a lab',
    'admin.noUnassignedDentistsSub': 'Dentists whose lab was deleted, who were removed, or who were approved without a lab show up here.',
    'admin.noRemovals': 'No removal requests',
    'admin.noRemovalsSub': 'When a lab asks to remove a dentist, you decide here.',
    'admin.requestedBy': 'Requested by {lab} · {when}',
    'admin.deny': 'Deny',
    'admin.approveRemovalTitle': 'Remove {name} from {lab}?',
    'admin.denyRemovalTitle': 'Keep {name} in {lab}?',
    'admin.denyRemovalMsg': 'The dentist stays in the lab and the request is closed.',
    'admin.removalApproved': 'Dentist removed from the lab',
    'admin.removalDenied': 'Request denied',
    'admin.searchLabs': 'Search labs',
    'admin.noLabsFound': 'No labs found',
    'admin.patientsSub': 'Every patient, with owner, lab and case history',
    'admin.allPatients': 'All patients',
    'admin.unassignedPatients': 'Unassigned',
    'admin.searchPatients': 'Search patients…',
    'admin.filterLab': 'Filter by lab',
    'admin.allLabs': 'All labs',
    'admin.noPatients': 'No patients found',
    'admin.noPatientsSub': 'Try another status, lab or search.',
    'admin.noUnassignedPatients': 'No unassigned patients',
    'admin.noUnassignedPatientsSub': 'Patients whose dentist was deleted, or that are waiting for a lab to choose a dentist, show up here.',
    'admin.pickPatient': 'Select a patient',
    'admin.pickPatientSub': 'Their owner, lab, records and case history appear here.',
    'admin.owner': 'Owner',
    'admin.lab': 'Lab',
    'admin.updated': 'Updated {when}',
    'admin.waitingForLab': 'Waiting for lab',
    'admin.ownerDeleted': 'Dentist deleted',
    'admin.back': 'Back',
    'admin.overrideStatus': 'Change status',
    'admin.overrideMsg': 'This overrides the case status and is logged in the case history with your note.',
    'admin.noteRequired': 'Note (required)',
    'admin.statusChanged': 'Status changed to {status}',
    'admin.reassignLab': 'Reassign to lab',
    'admin.reassignTitle': 'Reassign {name}',
    'admin.reassignMsg': 'Choose the receiving lab. Next you can pick one of its dentists, or leave that to the lab.',
    'admin.reassigned': '{name} sent to {lab}',
    'admin.sharedWith': 'Shared with',
    'admin.nobody': 'Nobody',
    'admin.lastUpdate': 'Last update',
    'admin.records': 'Records',
    'admin.shadeAnalyses': 'Shade analyses',
    'admin.none': 'None yet',
    'admin.history': 'Case history',
    'admin.noHistory': 'No events yet.',
    'admin.event.created': 'Created',
    'admin.event.submitted': 'Submitted to lab',
    'admin.event.approved': 'Approved',
    'admin.event.rejected': 'Rejected',
    'admin.event.updated': 'Updated',
    'admin.event.reassigned': 'Reassigned',
    'admin.event.admin_override': 'Status changed by admin',
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
    'common.fetchingData': 'Fetching data…',
    'common.required': 'Required',
    'common.continue': 'Continue',
    'common.copy': 'Copy',
    'common.add': 'Add',
    'common.online': 'Online',
    'common.offline': 'Offline',
    'common.preferenceSaved': 'Preference saved',
    'common.addPatient': 'Add patient',
    'errors.sessionExpired': 'Your session expired. Please sign in again.',
    'errors.noPermission': 'You do not have permission to do this.',
    'errors.notFound': 'We could not find that. It may have been removed.',
    'errors.validation':
        'Please check the information you entered and try again.',
    'errors.network':
        'Cannot reach the server. Check your connection and try again.',
    'errors.timeout': 'That took too long. Please try again.',
    'errors.server': 'Something went wrong on our side. Please try again.',
    'errors.generic': 'Something went wrong. Please try again.',
    'errors.badCredentials':
        'Email or password is incorrect. Please try again.',
    'errors.tooMany': 'Too many attempts. Please wait a moment and try again.',
    'errors.conflict':
        'That change conflicts with existing data. Please refresh and try again.',
    'errors.downloadFailed': 'Could not download the file. Please try again.',
    'common.searchPatients': 'Search patients…',
    'common.noPatientsYet': 'No patients yet',
    'common.archive': 'Archive',
    'patients.noMatching': 'No matching patients',
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
    'auth.roleAdmin': 'Admin',
    'auth.roleLaboratory': 'Laboratory',
    'auth.roleLab': 'Laboratory',
    'auth.alreadyHaveAccount': 'Already have an account? Sign in',
    'auth.errNameEmailPassword': 'Name, email, and password are required',
    'auth.errAllFieldsRequired': 'All fields are required',
    'auth.errPasswordShort':
        'Password must be at least 8 characters with 1 uppercase letter and 1 number',
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
    'settings.notificationsSub': 'Manage alert preferences for this device',
    'settings.notifyMaster': 'Enable Notifications',
    'settings.notifyMasterSub':
        'Receive alerts for lab messages, case status changes, and scan quality updates',
    'settings.notifyMessages': 'Lab messages',
    'settings.notifyMessagesSub': 'New chat from the lab on a case',
    'settings.notifyCase': 'Case status changes',
    'settings.notifyCaseSub': 'Pending, in review, completed, rejected',
    'settings.notifyScan': 'Scan quality alerts',
    'settings.notifyScanSub': 'Grainy / distorted PLY — prompt to rescan',
    'settings.languageTitle': 'Language & region',
    'settings.languageSub': 'UI language for the whole app',
    'settings.appLanguage': 'App language',
    'about.title': 'About us',
    'about.whatTitle': 'What is Elite Dent?',
    'about.whatBody': 'Elite Dent is an AI-assisted workspace that connects dental practices and laboratories. Capture photos and scans, get AI shade and scan-quality checks, manage patients and cases, and talk to your lab — all in one place.',
    'about.whoTitle': 'Who is it for?',
    'about.whoBody': 'Dentists, clinic teams and dental technicians who want faster, clearer communication and fewer remakes between practice and lab.',
    'about.support': 'Support',
    'about.privacy': 'Privacy policy',
    'about.imprint': 'Impressum',
    'about.website': 'Website',
    'about.featuresTitle': 'What you can do',
    'about.linksTitle': 'Support & legal',
    'about.accountTitle': 'Your account',
    'about.userId': 'User ID',
    'about.name': 'Name',
    'about.clinic': 'Clinic',
    'about.credit': 'Designed and developed by',
    'about.f.shade': 'AI shade matching',
    'about.f.shadeSub': 'Photograph a tooth and get a suggested shade in seconds.',
    'about.f.scans': 'Scan quality checks',
    'about.f.scansSub': 'Catch problems in intraoral scans before they reach the lab.',
    'about.f.patients': 'Patients & cases',
    'about.f.patientsSub': 'Keep patient records, photos and scans together.',
    'about.f.messages': 'Lab messaging',
    'about.f.messagesSub': 'Chat with your lab, share files and voice notes.',
    'about.f.interpreter': 'Interpreter',
    'about.f.interpreterSub': 'Talk to patients across languages, live.',
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
    'settings.deleteAccount': 'Delete account',
    'settings.deleteAccountBody':
        'This permanently removes your login and personal details. '
        'Patient records are not deleted: they stay with the practice. '
        'Type DELETE to continue.',
    'settings.deleteConfirmToken': 'DELETE',
    'settings.continue': 'Continue',
    'settings.confirmWithPassword': 'Confirm with password',
    'settings.enterPasswordToFinish': 'Enter your account password to finish.',
    'settings.passwordRequired': 'Password is required.',
    'settings.deletingAccount': 'Deleting account…',
    'settings.loading': 'Loading settings…',
    'settings.accountFallback': 'Account',
    'profile.title': 'Profile',
    'profile.subtitle':
        'Your account details — not limited to demo credentials',
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
    'profile.errNewPasswordShort':
        'New password must be at least 8 characters with 1 uppercase letter and 1 number',
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
    'labs.title': 'System Users',
    'labs.subtitle': 'Manage System User Profiles',
    'labs.searchHint': 'Search by name, email, clinic…',
    'labs.filterUnverified': 'Unverified',
    'labs.filterVerified': 'Verified',
    'labs.empty': 'No Laboratries found.',
    'labs.emptyFilter': 'No Laboratries match this filter.',
    'labs.verified': 'Verified',
    'labs.unverified': 'Unverified',
    'labs.verify': 'Verify user',
    'labs.count': '{shown} shown · {total} total',
    'labs.loading': 'Loading laboratories…',
    'labs.openingChat': 'Opening conversation…',
    'labs.verifyBeforeMessage': 'Verify this laboratory before messaging.',
    'labs.emptyVerifiedHint': 'Verified labs will appear here.',
    'labs.emptyFilterHint': 'Try another filter or search.',
    'labs.message': 'Message',
    'labs.clinicLab': 'Clinic / lab',
    'labs.status': 'Status',
    'labs.updated': 'Updated',
    'features.camera': 'Camera Capture',
    'features.scans': 'Scans',
    'features.shade': 'Shade Detection',
    'features.smile': 'Smile Preview',
    'features.scanBody': 'Scan Body',
    'features.messages': 'Messages',
    'features.notifications': 'Notifications',
    'features.reports': 'Reports',
    'features.selectPatient': 'Select patient',
    'reports.subtitle': 'Clinic performance, case pipeline, and AI coverage',
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
    'reports.copy': 'Copy',
    'reports.periodLine': 'Period: {period}',
    'reports.activeShort': 'Active',
    'reports.avgTimeShort': 'Avg. time',
    'reports.inPipeline': 'In pipeline',
    'reports.toComplete': 'To complete',
    'reports.newCount': '{n} new',
    'reports.followUpHint': 'Cases that need a follow-up',
    'reports.allClear': 'All clear',
    'reports.patientFallback': 'Patient',
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
    'notifications.typeAppointment': 'Appointment',
    'notifications.typeScanBody': 'Scan body',
    'notifications.typeSync': 'Sync',
    'notifications.typeExport': 'Export',
    'status.inProgress': 'In Progress',
    'status.awaitingScan': 'Awaiting Scan',
    'status.inReview': 'In Review',
    'status.complete': 'Complete',
    'status.rejected': 'Rejected',
    'status.noCase': 'No case',
    'common.statusUpdated': 'Status updated to {label}',
    'common.search': 'Search',
    'common.edit': 'Edit',
    'common.delete': 'Delete',
    'common.share': 'Share',
    'common.today': 'Today',
    'common.tomorrow': 'Tomorrow',
    'common.inOneWeek': 'In 1 week',
    'common.yesterday': 'Yesterday',
    'common.fullscreen': 'Fullscreen',
    'common.exitFullscreen': 'Exit fullscreen',
    'common.changeStatus': 'Change status',
    'appointments.title': 'Appointments',
    'appointments.subtitle':
        'Schedule visits and send confirmation emails to patients',
    'appointments.book': 'Book',
    'appointments.bookTitle': 'Book Appointment',
    'appointments.editTitle': 'Edit Appointment',
    'appointments.empty': 'No visits yet',
    'appointments.allPatients': 'All patients',
    'appointments.savedToast':
        'Appointment saved. Email notification sent to patient.',
    'appointments.notesHint': 'Clinical notes / visit summary',
    'appointments.selectPatient': 'Select a patient',
    'appointments.date': 'Date',
    'appointments.time': 'Time',
    'appointments.duration': 'Duration',
    'appointments.notes': 'Notes',
    'appointments.status': 'Status',
    'appointments.saveChanges': 'Save changes',
    'appointments.bookSubmit': 'Book appointment',
    'appointments.startTime': 'Start time',
    'appointments.endAfterStart': 'End time must be after start time',
    'appointments.endsAt': 'Ends at {time}',
    'appointments.saving': 'Saving appointment…',
    'appointments.filtering': 'Filtering schedule',
    'appointments.filterEmpty': 'Nothing matches this filter',
    'appointments.filterEmptyHint':
        'Try another status or patient, or book a new visit.',
    'appointments.bookEmptyHint':
        'Book a visit to send a confirmation email to the patient.',
    'appointments.noPatientsYet': 'No patients yet',
    'appointments.inClinicOne': '1 patient in clinic',
    'appointments.inClinic': '{n} patients in clinic',
    'appointments.minutesShort': '{n} min',
    'appointments.statusScheduled': 'Scheduled',
    'appointments.statusCompleted': 'Completed',
    'appointments.statusCancelled': 'Cancelled',
    'appointments.statusNoShow': 'No Show',
    'messages.subtitle': 'Inbox and conversations with the lab',
    'messages.placeholder': 'Message',
    'messages.newChat': 'New chat',
    'messages.startChat': 'Start a chat',
    'messages.empty': 'No messages yet — say hello.',
    'messages.selectConversation': 'Select a conversation to start messaging',
    'messages.attach': 'Attach',
    'messages.active': 'Active',
    'messages.reconnecting': 'Reconnecting…',
    'messages.noConversations': 'No conversations yet.',
    'messages.noMatch': 'No conversations match your search.',
    'messages.newTitle': 'New Message',
    'scans.subtitle': 'Intraoral scans for this patient, quality-checked before they go to the lab',
    'scans.upload': 'Upload scan',
    'scans.uploading': 'Uploading…',
    'scans.delete': 'Delete scan',
    'scans.deleted': 'Scan deleted',
    'scans.noneSelected': 'No scan selected',
    'scans.selectPatient': 'Select a patient',
    'scans.emptyFor': 'No scans for {name} yet',
    'scans.rescanNow': 'Rescan now — before patient leaves',
    'shade.cancel': 'Cancel',
    'shade.reset': 'Reset',
    'shade.apply': 'Apply',
    'shade.adjustEdges': 'Adjust edges',
    'shade.lips': 'Lips',
    'shade.symmetry': 'Symmetry lines',
    'shade.focusTooth': 'Selected tooth only',
    'shade.delete': 'Delete',
    'shade.addTooth': 'Add tooth',
    'shade.upload': 'Upload',
    'shade.reupload': 'Re-upload',
    'patients.status': 'Status',
    'patients.editTitle': 'Edit Patient',
    'patients.saveChanges': 'Save changes',
    'patients.createdToast': 'Patient created successfully',
    'patients.updatedToast': 'Patient updated',
    'patients.deleteTitle': 'Delete patient?',
    'patients.deleteBody': 'Choose how to remove {name}.',
    'patients.archiveOption': 'Archive patient',
    'patients.archiveOptionSub': 'Soft delete — keeps data for recovery',
    'patients.hardDeleteOption': 'Delete forever',
    'patients.hardDeleteOptionSub':
        'Hard delete — permanent GDPR Art. 17 erasure',
    'patients.typeDeleteConfirm': 'Type DELETE to confirm',
    'patients.opening': 'Opening patient…',
    'patients.shownTotal': '{shown} shown · {total} total',
    'common.request': 'Request',
    'common.approve': 'Approve',
    'common.reject': 'Reject',
    'common.done': 'Done',
    'common.close': 'Close',
    'common.rename': 'Rename',
    'common.retry': 'Retry',
    'common.undo': 'Undo',
    'common.redo': 'Redo',
    'common.working': 'Working…',
    'common.uploading': 'Uploading…',
    'common.tapToSelect': 'Tap to select',
    'common.invalidDate': 'Invalid date',
    'common.yearsOld': '{n} years old',
    'common.oneYearOld': '1 year old',
    'common.expandSidebar': 'Expand sidebar',
    'common.collapseSidebar': 'Collapse sidebar',
    'common.menu': 'Menu',
    'common.showPassword': 'Show password',
    'common.hidePassword': 'Hide password',
    'common.minPasswordLength': 'At least 8 characters',
    'common.openDownload': 'Open / download',
    'dash.loadingCases': 'Loading recent cases…',
    'dash.loadingActivity': 'Loading activity…',
    'patients.loading': 'Loading patients…',
    'patients.loadingAccess': 'Loading access…',
    'patients.loadingNotes': 'Loading notes…',
    'patients.loadingStaff': 'Loading eligible staff…',
    'patients.loadingAccessRequests': 'Loading access requests…',
    'patients.editNote': 'Edit note',
    'patients.deleteNoteTitle': 'Delete note?',
    'patients.deleteNoteBody':
        'This clinical note will be permanently removed.',
    'patients.noteHint': 'Add a clinical note…',
    'patients.noteAdded': 'Note added',
    'patients.noteUpdated': 'Note updated',
    'patients.noteDeleted': 'Note deleted',
    'patients.onlyAuthorEdit': 'Only the author can edit this clinical note.',
    'patients.onlyAuthorDelete':
        'Only the author can delete this clinical note.',
    'patients.clinicalNotePlaceholder': 'Clinical note',
    'patients.pendingAccess': 'Pending access requests',
    'patients.revoke': 'Revoke',
    'patients.regrant': 'Re-grant',
    'patients.savePatient': 'Save patient',
    'patients.refreshPatients': 'Refresh patients',
    'appointments.loading': 'Loading appointments…',
    'appointments.selectDate': 'Select Appointment Date',
    'appointments.editTooltip': 'Edit appointment',
    'appointments.starts': 'Starts',
    'profile.loading': 'Loading profile…',
    'scans.loading': 'Loading scans…',
    'scans.uploadingScan': 'Uploading scan…',
    'shade.loading': 'Loading shade detection…',
    'shade.detecting': 'Detecting…',
    'shade.waitTip1': 'Mapping teeth and contacts…',
    'shade.waitTip2': 'Matching enamel to VITA shades…',
    'shade.waitTip3': 'You can switch tabs — detection keeps running…',
    'shade.waitTip4': 'Checking smile band and gingiva…',
    'shade.waitTip5': 'Refining outlines — almost there…',
    'shade.uploadDetect': 'Upload & detect',
    'shade.removeSave': 'Remove save?',
    'shade.deleteFromSession': 'Delete {shade} from this session.',
    'shade.similarShades': 'Similar shades',
    'shade.bestOverall': 'Best overall',
    'shade.acrossAllTeeth': 'Across all teeth',
    'shade.deleteTooth': 'Delete tooth',
    'shade.photoTitle': 'Shade photo',
    'shade.photoMessage': 'Choose an action for this photo.',
    'shade.uploadAnother': 'Upload Another',
    'shade.deletePhoto': 'Delete Photo',
    'shade.openSession': 'Open session',
    'shade.closeSession': 'Close session',
    'shade.removeFromSession': 'Remove from session',
    'smile.loading': 'Loading smile preview…',
    'smile.loadPhoto': 'Load photo',
    'smile.changePhoto': 'Change photo',
    'smile.loadPatientPhoto': 'Load patient photo',
    'smile.guides': 'Guides',
    'smile.size': 'Size',
    'smile.width': 'Width',
    'smile.height': 'Height',
    'smile.rotate': 'Rotate',
    'smile.blend': 'Blend',
    'smile.scale': 'Scale',
    'smile.opacity': 'Opacity',
    'smile.useShape': 'Use shape {n}',
    'smile.shapeSoftOval': 'Soft oval',
    'smile.shapeClassicOval': 'Classic oval',
    'smile.shapeRounded': 'Rounded',
    'smile.shapeNaturalOval': 'Natural oval',
    'smile.shapeYouthful': 'Youthful',
    'smile.shapeSoftSquare': 'Soft square',
    'smile.shapeBalanced': 'Balanced',
    'smile.shapeSoftRect': 'Soft rect',
    'smile.shapeHollywood': 'Hollywood',
    'smile.shapeStrongSquare': 'Strong square',
    'smile.shapeTapered': 'Tapered',
    'smile.shapeCanineLift': 'Canine lift',
    'scanBody.loading': 'Loading scan body…',
    'scanBody.saveToCase': 'Save to case',
    'scanBody.matchTable': 'Match table',
    'scanBody.detectFromPhoto': 'Detect from photo',
    'scanBody.detected': 'Detected',
    'scanBody.pixels': 'Pixels',
    'scanBody.tableMatch': 'Table match',
    'scanBody.tooth': 'Tooth',
    'scanBody.manufacturer': 'Manufacturer',
    'scanBody.platform': 'Platform',
    'scanBody.confidence': 'Confidence',
    'scanBody.diameterHint': 'e.g. 4.1',
    'camera.deletePhotoTitle': 'Delete photo?',
    'camera.deletePhotoBody':
        'Remove this {angle} photo from {name}\'s record.',
    'camera.renamePhoto': 'Rename photo',
    'camera.choosePatient': 'Choose a patient',
    'camera.choosePatientBody':
        'Select a patient in the header to capture chairside photos.',
    'camera.noPhotosYet': 'No photos yet',
    'camera.noAnglePhotos': 'No {angle} photos',
    'camera.takePhoto': 'Take photo',
    'camera.gallery': 'Gallery',
    'camera.preparing': 'Preparing camera…',
    'camera.addPatient': 'Add a patient',
    'camera.photoOptions': 'Photo options',
    'camera.viewFullscreen': 'View full screen',
    'camera.openShade': 'Open with Shade Detection',
    'camera.openSmile': 'Open with Smile Preview',
    'camera.captureFocus': 'Capture focus',
    'camera.retryCamera': 'Retry camera',
    'camera.switchCamera': 'Switch camera',
    'camera.resetOverlay': 'Reset overlay',
    'messages.loadingConversations': 'Loading conversations…',
    'messages.loadingChat': 'Loading chat…',
    'messages.loadingContacts': 'Loading contacts…',
    'messages.photoLibrary': 'Photo Library',
    'messages.camera': 'Camera',
    'messages.videoLibrary': 'Video Library',
    'messages.recordVideo': 'Record Video',
    'messages.document': 'Document',
    'messages.filterAll': 'All',
    'messages.filterDentists': 'Dentists',
    'messages.filterLaboratories': 'Laboratories',
    'media.uploadItem': 'Upload item?',
    'media.deleteItem': 'Delete item?',
    'media.uploadBody': 'Upload and save this item to the patient record?',
    'media.uploadConfirm': 'Upload',
    'media.deleteBody':
        'Are you sure you want to delete this item? This action cannot be undone.',
    'common.useThisDate': 'Use this date',
    'common.selectDate': 'Select Date',
    'common.prevMonth': 'Previous month',
    'common.nextMonth': 'Next month',
    'common.minUppercase': 'At least one uppercase letter',
    'common.minNumber': 'At least one number',
    'shade.manualOverride': 'Manual Override — VITA Classical',
    'shade.allVita': 'All VITA Classical shades',
    'shade.targetShades': 'Target shades',
    'shade.toothSamples': 'Tooth samples',
    'shade.gumShades': 'Gum shades',
    'shade.overrideTeeth': 'Teeth',
    'shade.overrideGum': 'Gum',
    'auth.passwordUpdatedRelogin': 'Password updated. Please log in again.',
    'dash.patientsOnFile': '{n} patients on file',
    'dash.patientsOnFileOne': '1 patient on file',
    'dash.needsAttention': '{n} cases need attention',
    'dash.needsAttentionOne': '1 case needs attention',
    'dash.unreadMessages': '{n} unread messages',
    'dash.unreadMessagesOne': '1 unread message',
    'dash.patientsAndCasesOnFile':
        '{patients} patients · {cases} cases on file.',
    'dash.acrossCompleted': 'Across {n} completed',
    'dash.inProgressInReview':
        '{inProgress} in progress · {inReview} in review',
    'dash.activityCompleted': 'Case {label} marked complete — {patient}',
    'dash.activityRejected': 'Scan rejected for {patient} — rescan required',
    'dash.activityInReview': 'Case for {patient} moved to lab review',
    'dash.activityInProgress': 'Case for {patient} is in progress',
    'dash.activityPending': 'Case opened for {patient} — awaiting scan',
    'dash.activityUpdated': 'Case updated for {patient}',
    'common.justNow': 'Just now',
    'common.minAgo': '{n} min ago',
    'common.hourAgo': '1 hour ago',
    'common.hoursAgo': '{n} hours ago',
    'common.daysAgo': '{n} days ago',
    'patients.shareTitle': 'Share {patient}',
    'patients.grantAccess': 'Grant access',
    'patients.requestAccess': 'Request access',
    'patients.asOwnerHint':
        'As owner, your invitation will immediately allow access.',
    'patients.requestAccessHint':
        'This request will be sent to the patient owner for approval.',
    'patients.allStaffHaveAccess':
        'All practice staff members already have access or pending requests for this patient.',
    'patients.noEligibleStaff': 'No eligible staff available to invite.',
    'patients.accessGranted': 'Access successfully granted to staff member.',
    'patients.accessRequestSubmitted':
        'Access request submitted to patient owner for review.',
    'patients.createdBy': 'Created by',
    'patients.accessLabel': 'Access',
    'patients.creator': 'Creator',
    'patients.shared': 'Shared',
    'patients.owner': 'Owner',
    'patients.onlyOwnerApprove':
        'Only the patient owner can approve or reject access requests.',
    'patients.onlyOwnerManage':
        'Only the patient owner can view and manage full staff access permissions.',
    'patients.waitingOwnerReview': 'Waiting for owner review',
    'camera.subtitle': 'Frontal, left, and right photos · up to 12 per patient',
    'camera.angle': 'Angle',
    'camera.frontal': 'Frontal',
    'camera.left': 'Left',
    'camera.right': 'Right',
    'camera.frontalSmile': 'Frontal smile',
    'camera.leftProfile': 'Left profile',
    'camera.rightProfile': 'Right profile',
    'camera.clinicalPhoto': 'Clinical photo',
    'camera.emptyPhotosHint':
        'Take a frontal, left, or right photo — it is saved to this patient record.',
    'camera.noPatientsCaptureHint':
        'No patients yet — add one to capture photos.',
    'camera.addPatientCaptureHint':
        'Add a patient from the header to start capturing photos.',
    'camera.switchAngleHint':
        'Switch angle or take a {angle} photo for this patient.',
    'shade.subtitle':
        'Upload a tooth photo → AI detects VITA shade → confirm or override',
    'shade.uploadCloseUp': 'Upload a close-up tooth/smile photo',
    'shade.uploadToothPhoto': 'Upload tooth photo',
    'shade.analyzing': 'Analyzing shade…',
    'shade.session': 'Session',
    'shade.savedShadesHint': 'Saved shades · tap to edit',
    'shade.noSavesYet': 'No saves yet',
    'shade.noDetectionYet': 'No detection yet',
    'shade.uploadToAnalyze': 'Upload a photo to analyze',
    'shade.acceptAi': 'Accept AI',
    'shade.acceptShade': 'Accept {shade}',
    'shade.saveOverride': 'Save override',
    'shade.saveOverrideShade': 'Save override ({shade})',
    'shade.result': 'Result',
    'shade.toothSelection': 'Tooth Selection',
    'shade.override': 'Override',
    'shade.overrideSelected': 'Override selected: {shade}',
    'shade.selected': 'Selected',
    'shade.uploadToothFirst':
        'Upload a tooth photo first so AI can detect a shade.',
    'shade.gumShade': 'Gum shade',
    'shade.gumNotVita': 'Not a VITA tooth shade',
    'shade.noGumDetected': 'No gum detected',
    'smile.pageSubtitle':
        'Pick a tooth shape · place it on the patient photo · save to case',
    'smile.loadSmilePhoto': 'Load a patient smile photo',
    'smile.loadSmileHint':
        'Then tap a shape in the library on the right and place it over the teeth.',
    'smile.loadSmileHintPortrait':
        'Then tap a shape in the library below and place it over the teeth.',
    'smile.placement': 'Placement',
    'smile.batemModels': 'Batem models',
    'smile.modelOpen': 'Open',
    'smile.modelClosed': 'Closed',
    'smile.useThisModel': 'Use this model',
    'smile.upperJaw': 'Upper jaw',
    'smile.lowerJaw': 'Lower jaw',
    'patients.noNotes': 'No notes',
    'patients.noClinicalNotes': 'No clinical notes yet.',
    'appointments.noNotes': 'No notes',
    'smile.nudge': 'Nudge',
    'smile.resetPlacement': 'Reset placement',
    'smile.centerShape': 'Center shape',
    'smile.selectShapeHint':
        'Select a library shape → drag / pinch / rotate into place',
    'smile.originalPhoto': 'Original photo',
    'notifications.markedAllRead': 'All notifications marked as read',
    'notifications.now': 'now',
    'notifications.minsShort': '{n}m',
    'notifications.hoursShort': '{n}h',
    'notifications.daysShort': '{n}d',
    'notifications.moreCount': '+{n} more',
    'notifications.msgAccessApproved':
        'Access approved for {name}. You can open this patient record.',
    'notifications.msgYouApprovedAccess':
        "You approved {who}'s access to {name}.",
    'notifications.msgAccessDeclined': 'Access to {name} was declined.',
    'notifications.msgYouDeclinedAccess':
        "You declined {who}'s request to access {name}.",
    'notifications.msgGrantedAccess': '{who} granted you access to {name}.',
    'notifications.msgYouGrantedAccess': 'You granted {who} access to {name}.',
    'notifications.msgRequestedAccess': '{who} requested access to {name}.',
    'notifications.msgYouRequestedAccess': 'You requested access to {name}.',
    'notifications.msgAccessRevoked': 'Your access to {name} was revoked.',
    'notifications.msgYouRevokedAccess':
        "You revoked {who}'s access to {name}.",
    'notifications.msgYouBookedAppt': 'You booked an appointment for {name}.',
    'notifications.msgBookedAppt': '{who} booked an appointment for {name}.',
    'notifications.msgYouCancelledAppt':
        'You cancelled an appointment for {name}.',
    'notifications.msgCancelledAppt':
        '{who} cancelled an appointment for {name}.',
    'notifications.msgYouUpdatedAppt': 'You updated an appointment for {name}.',
    'notifications.msgUpdatedAppt': '{who} updated an appointment for {name}.',
    'notifications.msgUploadedScan': '{who} uploaded a 3D scan for {name}.',
    'notifications.msgSavedShade': '{who} saved a shade photo for {name}.',
    'notifications.msgSavedSmile': '{who} saved a smile preview for {name}.',
    'notifications.msgAddedFile': '{who} added a file for {name}.',
    'notifications.msgScanQuality': 'Scan quality issue for {name}.',
    'notifications.msgScanQualityDetail':
        'Scan quality issue for {name}. {detail}',
    'notifications.msgNewScan': 'New scan uploaded for {name}.',
    'notifications.msgNewPatient':
        'New patient on file: {name} (awaiting scan).',
    'notifications.fallbackScanQuality': 'Scan quality alert for {name}',
    'notifications.fallbackShade': 'Shade update for {name}',
    'notifications.fallbackAppointment': 'Appointment update for {name}',
    'notifications.fallbackCase': 'Case update for {name}',
    'notifications.fallbackScanBody': 'Scan body update for {name}',
    'notifications.fallbackSync': 'Sync update for {name}',
    'notifications.fallbackExport': 'Export update for {name}',
    'patient.readyForDetect': 'Ready for detect',
    'patient.noneYet': 'None yet',
    'patient.availableCount': '{n} available',
    'patient.caseId': 'Case #{id}',
    'patient.fallbackId': 'Patient #{id}',
    'patient.emptyHint': 'No patients yet — add one to continue.',
    'scans.qualityNeedPatient':
        'Select a patient, then upload a scan to see quality results.',
    'scans.qualityNeedUpload':
        'No scan uploaded yet — upload a PLY, STL, or OBJ to run the quality check.',
    'scans.simulatorPickTitle': 'Choose a scan from this Mac',
    'scans.simulatorPickHint':
        'The iPad Simulator cannot open Mac Downloads. Copy the PLY, STL, or OBJ into dental-lab-ai/mobile/debug_scans, then pick it here.',
    'scans.simulatorPickEmpty':
        'No mesh files found. Copy a PLY, STL, or OBJ into mobile/debug_scans and try again.',
    'scans.needMeshFile': 'Choose a PLY, STL, or OBJ scan.',
    'scans.couldNotReadFile': 'Could not read that file. Try another scan.',
    'scans.uploadPreviewHint': 'Upload a PLY / STL / OBJ to preview',
    'scans.emptyHintUpload': 'No patients yet — add one to upload scans.',
    'interpreter.subtitle':
        'Doctor ↔ patient during treatment. Does not change the app language.',
    'interpreter.doctor': 'Doctor',
    'interpreter.patient': 'Patient',
    'interpreter.doctorLanguage': 'Doctor language',
    'interpreter.patientLanguage': 'Patient language',
    'interpreter.doctorHint':
        'Hold to speak, or type. The patient pane shows the translation.',
    'interpreter.patientHint':
        'Hold for the patient to speak, or type. You will see it in your language.',
    'interpreter.holdToTalk': 'Hold to talk',
    'interpreter.listening': 'Listening…',
    'interpreter.typeInstead': 'Voice not available — type instead',
    'interpreter.allowSpeech':
        'Allow Speech Recognition and Microphone for Elite Dent, then tap Hold to talk again.',
    'interpreter.appleTranslateFailed':
        'Translation failed. On the Simulator, Apple Translate is unavailable — the app uses the server instead (start the backend on port 8000). On a real iPad, use iPadOS 18+ and allow language downloads when asked.',
    'interpreter.typeHint': 'Type a sentence…',
    'interpreter.send': 'Send',
    'interpreter.speak': 'Speak aloud',
    'interpreter.swap': 'Swap languages',
    'interpreter.clear': 'Clear this visit',
    'interpreter.history': 'Everything said this visit',
    'interpreter.packTitle': 'Download {lang} for translation?',
    'interpreter.toneUnchecked':
        'Offline translation — politeness not checked.',
    'interpreter.packBody':
        'Apple translates on this device. The language pack downloads once and then works offline.',
    'interpreter.packDownload': 'Download',
    'interpreter.packOnline': 'Use online instead',
    'interpreter.packFailed':
        'The language pack was not downloaded. Try again or use online translation.',
    'interpreter.autoSpeak': 'Read translations aloud',
    'interpreter.ttsFailed':
        'Could not play speech. Unmute the iPad (not silent) and tap Speak aloud.',
    'interpreter.nothingHeard':
        'Nothing was heard. Hold the button and speak, or type.',
    'interpreter.nothingHeardLang':
        'Nothing was heard in {lang}. Keep holding and speak that language, or type.',
    'interpreter.noVoice':
        'This device has no spoken voice for that language. The translation is on screen.',
    'interpreter.searchLanguage': 'Search languages',
    'interpreter.clinicLanguages': 'Clinic languages',
    'interpreter.allLanguages': 'All languages',
    'interpreter.patientOptional':
        'Optional — remembers this patient’s language',
    'p.onlyCreatorEdit': 'Only the person who created this patient record can edit it.',
    'p.permDenied': 'Permission denied: only the creator of this record can modify patient details.',
    'p.tryOtherStatus': 'Try another status or clear the search.',
    'p.addFirst': 'Add the first record to get started.',
    'p.accessApprovedLong': 'Access approved. Staff member can now access this patient record.',
    'p.accessRejectedDot': 'Access request rejected.',
    'p.noPending': 'No pending requests right now.',
    'p.allCaughtUp': 'All caught up.',
    'p.target': 'Target: {n}',
    'p.requestedByColon': 'Requested by: {n}',
    'p.accessRevoked': 'Access revoked',
    'p.accessApproved': 'Access approved',
    'p.accessRejected': 'Access request rejected',
    'p.onlyAuthorDelete': 'Only the author can delete this clinical note.',
    'p.noteDeleted': 'Note deleted',
    'p.tabInfo': 'Info',
    'p.tabAccess': 'Access',
    'p.export': 'Export',
    'p.exported': 'Patient data exported',
    'p.exporting': 'Preparing the export — this can take a moment for patients with many scans…',
    'p.emailRow': 'Email',
    'p.phoneRow': 'Phone',
    'p.noAccessInfo': 'No access information available.',
    'p.requestedBy': 'Requested by {n}',
    'p.staffMember': 'Staff member',
    'p.noneYet': 'No patients yet. Add the first record.',
    'p.deleted': 'Patient permanently deleted',
    'p.archived': 'Patient archived',
    'p.email': 'Email',
    'p.phone': 'Phone',
    'c.maxPhotos': 'Max {n} photos per patient',
    'c.alignHint': 'Align {a} guide for {p} — hold preview for upper/lower',
    'c.savedPhoto': 'Saved {a} photo for {p}',
    'c.deleting': 'Deleting photo…',
    'c.deleted': 'Deleted {a} photo',
    'c.renamePh': 'e.g. Upper smile',
    'c.renaming': 'Renaming photo…',
    'c.renamed': 'Renamed to {n}',
    'c.openShade': 'Opening “{n}” with Shade Detection…',
    'c.openSmile': 'Opening “{n}” with Smile Preview…',
    'c.closePhoto': 'Close photo',
    'c.takeHint': 'Take a {a} photo or pick one from the grid.',
    'c.nothingSel': 'Nothing selected',
    'c.photoUnavail': 'Photo unavailable',
    'c.refreshing': 'Refreshing…',
    'c.loadFail': 'Could not load photo',
    'c.crop': 'Crop photo',
    'c.usePhoto': 'Use photo',
    'c.addTo': 'Add to {n}',
    'c.photoAdded': 'Photo added',
    'c.savedTo': 'Saved to {n}\'s photos. Open it now?',
    'c.later': 'Later',
    'c.incoming': 'Incoming',
    'c.noIncoming': 'No incoming photos. Send photos from a PC at /scan-upload on your server.',
    'c.selPatFirst': 'Select a patient first',
    's.assignTitle': 'Assign scan',
    's.assignMsg': 'Add "{f}" to {p}?',
    's.assign': 'Assign',
    's.added': 'Scan added to {p}',
    's.noPoints': 'Preview has no points',
    's.prevUnavail': 'Scan preview unavailable',
    's.readFail': 'Could not read file bytes',
    's.incomingName': 'Incoming: {n}',
    's.assignTo': 'Assign to {p}',
    's.loading': 'Loading scans…',
    's.noIncoming': 'No incoming scans. Send scans from a PC at /scan-upload on your server (photos arrive on the Camera tab).',
    'sh.noLip': 'No lip border found in this photo — showing the midline only. Add lips in Adjust edges to place them.',
    'sh.chooseShade': 'Choose a shade first, then tap Override',
    'sh.chooseGum': 'Choose a gum shade first, then tap Override',
    'sh.gumShade': 'Gum shade → {s}',
    'sh.chooseGum5': 'Choose a gum shade (G1–G5), then tap Override',
    'sh.removed': 'Removed tooth — tap Undo to restore, or re-detect.',
    'sh.removedN': 'Removed tooth. {n} remaining — tap Undo to restore.',
    'sh.restored': 'Restored deleted tooth.',
    'sh.uploadFirst': 'Upload a photo before adding a tooth.',
    'sh.addedTooth': 'Added tooth — hold inside the outline and drag it onto the tooth, then Apply.',
    'sh.dragHelp': 'Drag inside to move · drag corners · hold mid-edge to curve · drag the midline · Apply.',
    'sh.dragLip': 'Drag the pink points onto the edge where each lip meets the skin.',
    'sh.lipRemoved': 'Lip outline removed.',
    'sh.photoRemoved': 'Photo removed',
    'sh.guidesUpdated': 'Midline and lip guides updated.',
    'sh.updating': 'Updating shade from edited outline…',
    'sh.outlineApplied': 'Outline applied — zone shades refreshed for {t}.',
    'sh.selZone': 'Select a tooth zone first',
    'sh.photoNF': 'Photo not found for this patient.',
    'sh.mapping': 'Mapping teeth…',
    'sh.noTeeth': 'No teeth detected — try another photo',
    'sh.mapped': 'Mapped {n} teeth — Accept or Save override to session',
    'sh.selPat': 'Select a patient first.',
    'sh.imgBytes': 'Could not read image bytes. Try another photo.',
    'sh.addPatFirst': 'Add a patient first, then save the shade to their record.',
    'sh.selFromList': 'Select a patient from the list first.',
    'sh.pickShade': 'Pick a shade before saving.',
    'sh.tapOverride': 'Tap Override on the zone chip to confirm {s} first.',
    'sh.savedOv': 'Saved override {s}',
    'sh.accAi': 'Accepted AI {s}',
    'sh.removedSess': 'Removed {s} from session',
    'sh.pointAdded': 'Point added — drag to refine, or curve the new edges.',
    'sh.tooth': 'Tooth {n}',
    'sh.savedOvFor': 'Saved override {s} for {w}',
    'sh.accAiFor': 'Accepted AI {s} for {w}',
    'sh.pinchTap': 'Pinch to zoom · tap a numbered circle',
    'sh.selFdi': 'Selected FDI {n} · pinch to zoom',
    'sh.uploadDetect': 'Upload & detect a smile first — only found teeth are selectable.',
    'sh.fdiND': 'FDI {n} (not detected)',
    'sh.editingTooth': 'Editing {t}',
    'sh.forZone': 'For the focused zone',
    'sh.forTooth': 'For {t}',
    'sh.holdHelp': 'Hold inside the outline and drag to move it · corners reshape · mid-edge curves · Apply.',
    'sh.pinchHelp': 'Pinch to zoom · Tap to select · Press & hold for photo actions.',
    'sh.savedFinal': 'Saved final: {s}',
    'sh.edgeView': 'Edge view',
    'sh.patient': 'Patient',
    'sh.notAnalysed': 'Not analysed yet',
    'sh.override': 'Override',
    'sh.editingNow': 'Editing now',
    'sh.hideTeeth': 'Hide',
    'sh.conf': '{n}% confidence',
    'sh.manual': 'Manual selection',
    'sh.tapEdit': 'Tap to edit',
    'sh.teeth': 'Teeth',
    'shape.Soft oval': 'Soft oval',
    'shape.Classic oval': 'Classic oval',
    'shape.Rounded': 'Rounded',
    'shape.Natural oval': 'Natural oval',
    'shape.Youthful': 'Youthful',
    'shape.Soft square': 'Soft square',
    'shape.Balanced': 'Balanced',
    'shape.Soft rect': 'Soft rect',
    'shape.Hollywood': 'Hollywood',
    'shape.Strong square': 'Strong square',
    'shape.Tapered': 'Tapered',
    'shape.Canine lift': 'Canine lift',
    'shape.Implant natural': 'Implant natural',
    'shape.Implant classic': 'Implant classic',
    'sh.rm': 'Removed {n}',
    'sh.sel': 'Selected {n}',
    'sh.restoredShape': 'Restored {n}',
    'sp.fromCam': 'Opened from Camera — select a shape from the library.',
    'sp.reopened': 'Reopened saved smile — adjust and Save changes.',
    'sp.noFile': 'This photo has no file to open.',
    'sp.bytes': 'Could not read image bytes.',
    'sp.loaded': 'Photo loaded — select a shape from the library.',
    'sp.selModel': 'Select a model first',
    'sp.savedCase': 'Saved {s} to case #{c}',
    'sp.saved': 'Smile preview saved ({s})',
    'sp.delQ': 'Delete saved smile?',
    'sp.delMsg': 'This removes it from the patient record.',
    'sp.deleted': 'Saved smile deleted',
    'sp.savedN': 'Saved smiles ({n})',
    'sp.delTip': 'Delete saved smile',
    'sp.noPat': 'No patients yet — add one to save the try-on.',
    'sp.saving': 'Saving…',
    'sp.saveChanges': 'Save changes',
    'sp.exitFs': 'Exit fullscreen',
    'sp.compare': 'Hold to compare original',
    'sp.hideOv': 'Hide overlay',
    'sp.saveToCase': 'Save to case',
    'sp.fs': 'Fullscreen',
    'sp.showOv': 'Show overlay',
    'p.emailReq': 'Email address is required',
    'p.emailInvalid': 'Enter a valid email address',
    'p.stPending': 'Pending Approval',
    'p.stActive': 'Active Access',
    'p.stDenied': 'Denied',
    'p.emailLabel': 'Email Address *',
    'p.clear': 'Clear',
    'p.saving': 'Saving…',
    'p.identity': 'Identity',
    'p.required': 'Required',
    'ch.voice': 'Voice message',
    'ch.photo': 'Photo',
    'ch.video': 'Video',
    'ch.doc': 'Document',
    'ch.attach': 'Attachment',
    'ch.sendVoice': 'Sending voice…',
    'ch.sendPhoto': 'Sending photo…',
    'ch.sendVideo': 'Sending video…',
    'ch.sendDoc': 'Sending document…',
    'ch.sending': 'Sending…',
    'ch.voiceShort': 'Voice',
    'ch.noPreview': 'Could not preview',
    'ch.openDl': 'Open / download',
    'ch.live': 'Live · {n} unread',
    'ch.noMsgs': 'No messages yet',
    'ch.newMsg': 'New Message',
    'ch.search': 'Search',
    'ch.noContacts': 'No contacts found.',
    'ch.tag': 'Tag a patient',
    'ch.match': 'Patients matching “{q}”',
    'p.noMatchP': 'No matching patients',
    'ch.errImg': 'Could not read the selected image.',
    'ch.errFile': 'Could not read the selected file.',
    'ch.errVid': 'Could not read the selected video.',
    'ch.vidBig': 'Videos must be 200 MB or smaller.',
    'ch.mic': 'Microphone permission is required for voice notes.',
    'ch.recFail': 'Recording failed — no audio captured.',
    'ch.holdLonger': 'Hold a bit longer to record a voice note.',
    'ch.errAudio': 'Could not read the recorded audio.',
    'ch.recStart': 'Could not start recording.',
    'ch.sendVN': 'Could not send the voice note. Please try again.',
    'ch.replying': 'Replying',
    'ch.vidFail': 'Could not load video',
    'p.unnamed': 'Unnamed patient',
    'p.unknownPr': 'Unknown Practitioner',
    'p.owner': 'Owner',
    'p.busy': 'Another patient change is already in progress',
    'lab.busy': 'Another laboratory action is already in progress',
    'c.uploading': 'Uploading…',
    'c.pleaseWait': 'Please wait…',
    'sb.restored': 'Restored saved match for this case.',
    'sb.restoredN': 'Restored {m} · tooth {t}',
    'sb.validMm': 'Enter a valid diameter in mm',
    'sb.circlePx': 'Circle found in pixels — enter diameter in mm (3–6), or tap a table row.',
    'sb.circleDet': 'Circle detected — calibrate scale or confirm diameter for accuracy.',
    'sb.matched': 'Matched from photo ({d} mm).',
    'sb.scaleOut': 'Scale {s} px/mm is outside 3–6 mm range — adjust or calibrate.',
    'sb.measured': 'Measured {d} mm at {s} px/mm.',
    'sb.enterMm': 'Enter the known diameter in millimetres (mm)',
    'sb.typical': 'Scan-body diameters are typically 3–6 mm (not metres). Check your value.',
    'sb.detectFirst': 'Detect a circle from a photo first',
    'sb.fromTable': 'Selected from reference table.',
    'sb.matchFirst': 'Match a diameter first',
    'sb.saved': 'Saved {m} · tooth {t} on case #{c}',
    'sb.platMm': 'Platform Ø in millimetres (mm) — typically 3–6 mm, not metres',
    'sb.provisional': 'Provisional reference table — swap for Elite Dent manufacturer data before production.',
    'sb.measurement': 'Measurement',
    'sb.platDia': 'Platform diameter (mm)',
    'sb.outer': 'Outer scan-body platform width in millimetres',
    'sb.detect': 'Detect from photo',
    'sb.newPhoto': 'New photo',
    'sb.scaleCal': 'Scale calibration',
    'sb.noScale': 'Photo has no scale yet — enter mm from a caliper, tap a table row, or calibrate.',
    'sb.locked': 'Scale locked · refine if reading looks off.',
    'sb.calib': 'Calibrate using diameter above',
    'sb.result': 'Result',
    'sb.ambig': 'Ambiguous — confirm',
    'sb.top': 'Top candidates',
    'sb.load': 'Load a scan-body photo',
    'sb.aiFinds': 'AI finds the circular platform; you enter mm (3–6) or calibrate.',
    'sb.noCircle': 'No circle',
    'sb.refTable': 'Reference table ({n})',
    'sb.noRows': 'No reference rows loaded',
    'sb.toothRow': 'Tooth {t} · {p}',
    'sb.selected': 'Selected',
    'sb.use': 'Use',
    'lc.none': 'No camera found. Use the system camera or photo library.',
    'lc.perm': 'Camera permission is off. Enable it in Settings, then retry.',
    'lc.restricted': 'Camera access is restricted on this device.',
    'lc.start': 'Could not start the camera.',
    'lc.holdPrev': 'Hold the preview to change. Default is both jaws.',
    'lc.empty': 'Camera returned an empty photo. Please try again.',
    'lc.system': 'System camera',
    'lc.processing': 'Processing photo…',
    'lc.both': 'Both jaws',
    'lc.upper': 'Upper teeth',
    'lc.lower': 'Lower teeth',
    'ms.loading': 'Loading mesh…',
    'ms.solid': 'Solid',
    'ms.colored': 'Colored',
    'ms.rough': 'Problem areas',
    's.qChecking': 'Checking scan quality…',
    's.qGood': 'No problems found — ready to send to the lab.',
    's.qError': "Couldn't check this scan.",
    's.qIncoming': 'Quality is checked once the scan is assigned to a patient.',
    'sq.unknown.t': 'Scan problem',
    'sq.point_cloud.d': 'This file only contains points, no surface, so holes and filled-in areas can\'t be checked. For a full check, export the scan as STL, or as PLY with surface.',
    'sq.point_cloud.t': 'Limited check',
    'sq.bite_overlap.d': 'In the bite position the upper and lower scans overlap (marked red), which real teeth can\'t do. Either the bite scan is wrong or one jaw scan is slightly distorted. Repeat the bite scan; if they still overlap, rescan the affected jaw.',
    'sq.bite_overlap.t': 'Upper and lower jaw don\'t fit together',
    'sq.double_layer.d': 'In some areas (marked red) the surface appears twice, slightly shifted — two scan passes were joined out of line, often because the patient moved. Delete that area in the scanner software and rescan it.',
    'sq.double_layer.t': 'Doubled surface',
    'sq.noisy_surface.d': 'The whole surface looks grainy instead of smooth. Common causes are a dirty or fogged scanner tip, or holding the scanner too far from the teeth. Clean the tip and rescan.',
    'sq.noisy_surface.t': 'Grainy scan',
    'sq.rough_surface.d': 'Some areas (marked red) look bumpy, stepped or doubled. This usually comes from movement during scanning, or from saliva or blood on the teeth. Dry the area and rescan it slowly.',
    'sq.rough_surface.t': 'Rough or uneven areas',
    'sq.patched_holes.d': 'The scanner missed some areas (marked red) and the software filled them with a guessed, smooth surface. The real shape there is unknown, so a restoration may not fit. Rescan those areas.',
    'sq.patched_holes.t': 'Gaps filled in by the software',
    'sq.holes.d': 'Some areas (marked red) were never captured, so the lab can\'t see the real shape there. Rescan them — this matters most if a hole is on a prepared tooth or its margin.',
    'sq.holes.t': 'Holes in the scan',
    'sq.broken_mesh.d': 'A few triangles in the model are malformed. Lab software normally repairs this automatically — no action needed unless the lab reports a problem.',
    'sq.broken_mesh.t': 'Small file defects',
    'sq.loose_fragments.d': 'Small pieces float next to the teeth (marked red) — usually tongue, cheek, a finger or saliva scanned by accident. Delete them in the scanner software, or rescan if they cover teeth.',
    'sq.loose_fragments.t': 'Loose bits in the scan',
    'sq.split.d': 'The scanner couldn\'t join parts of the scan together, so the surface between them is missing. Rescan the area between the pieces (marked red) so they connect.',
    'sq.split.t': 'Scan is in separate pieces',
    'sq.low_resolution.d': 'The scan was exported at reduced resolution, so fine details such as preparation margins are lost. Export it again at full resolution.',
    'sq.low_resolution.t': 'Low detail',
    'sq.flat_export.d': 'The model has no depth — something went wrong during export. Export the scan again from the scanner software.',
    'sq.flat_export.t': 'Scan is flat',
    'sq.wrong_size.d': 'The model is far too small or too large to be teeth. Either it was exported in the wrong unit (it must be millimetres) or it isn\'t a dental scan. Check the export settings and the file.',
    'sq.wrong_size.t': 'Wrong size',
    'sq.sparse.d': 'The file contains far too few points to show teeth. The export probably failed — export the scan again at full quality.',
    'sq.sparse.t': 'Almost no scan data',
    'sq.truncated.d': 'The upload or export stopped before the end, so part of the scan is missing. Upload the file again; if it happens again, export it again from the scanner software.',
    'sq.truncated.t': 'File is incomplete',
    'sq.parse_fail.d': 'The file is damaged or isn\'t a 3D scan. Export the scan again from the scanner software as STL, PLY or OBJ and upload it again.',
    'sq.parse_fail.t': 'File can\'t be opened',
    'sq.r.bad': 'Rescan',
    'sq.r.review': 'Check',
    'sq.r.good': 'Good',
    'sq.sev.low': 'Note',
    'sq.sev.medium': 'Please check',
    'sq.sev.high': 'Rescan needed',
    's.qBad': 'This scan has problems — please rescan before the patient leaves.',
    's.qReview': 'Please check the points below before sending the scan.',
    'dp.year': 'Choose birth year',
    'dp.month': 'Choose birth month · {y}',
    'dp.y': 'Year',
    'p.dentist': 'Dentist',
    'au.reset': 'If an account exists for that email, a password reset link has been sent.',
    'dp.m': 'Month',
    'dp.d': 'Day',
    'lc.align': 'Align the tooth / arch, then capture',
    'c.savingPhoto': 'Saving photo…',
    'ch.opening': 'Opening conversation…',
    'c.unknown': 'Unknown',
    'c.user': 'User',
    's.scan': 'Scan',
    'z.cervical': 'Cervical',
    'z.middle': 'Middle',
    'z.incisal': 'Incisal',
    'sh.oneTooth': '1 tooth',
    'sh.nTeeth': '{n} teeth',
    'sh.match': 'match',
    'sh.selGum': '{s} selected — tap Override on Gum shade to apply',
    'sh.chooseFor': '{t} — choose a shade, then tap Override',
    'sh.selSave': '{s} selected — tap Save override to apply',
    'sh.selOn': '{s} selected — tap Override on {t} to apply',
    'lc.holdChange': 'hold to change',
    'p.reqOne': '1 request awaiting your decision.',
    'p.reqN': '{n} requests awaiting your decision.',
    'ap.min': '{m} min',
    's.uploaded': '{f} scan uploaded',
    's.saveToCase': 'Save to case',
    's.savedToCase': '{n} scan(s) saved to the case',
    's.alreadyOnCase': 'All scans are already on the case',
    's.onCase': 'On case',
    's.libraryOnly': 'Library',
    'sb.pxEnter': 'Ø {p} px (enter mm)',
    'sb.pxEnter2': '⌀ {p} px · enter mm',
    'ms.hudTris': 'web · {n} tris · drag/pinch',
    'ms.hudPts': 'web · {n} pts · no faces · drag/pinch',
    'ms.gpuTris': 'ipad-gpu · {n} verts · {t} tris',
    'ms.gpuNoFaces': 'ipad-gpu · {n} pts · no faces',
    'ms.gpuPts': 'ipad-gpu · {n} pts',
    'img.read': 'Could not read this photo. Try another image.',
    'img.heic': 'Could not read this photo. Export it as JPEG from Photos and try again.',
    'err.unexpected': 'An unexpected error occurred.',
    'err.network': 'Connection problem. Please check your internet connection and try again.',
    'sh.dragBottomLip': 'Drag the horizontal line at the bottom lip up or down to adjust it.',
  };

  static const _de = <String, String>{
    'nav.dashboard': 'Übersicht',
    'nav.patients': 'Patienten',
    'nav.newPatient': 'Neuer Patient',
    'nav.appointments': 'Termine',
    'nav.camera': 'Kamera',
    'nav.scans': 'Scans',
    'nav.shade': 'Farbbestimmung',
    'nav.smilePreview': 'Lächeln-Vorschau',
    'nav.interpreter': 'Dolmetscher',
    'nav.scanBody': 'Scanbody',
    'nav.messages': 'Nachrichten',
    'nav.laboratories': 'Systembenutzer',
    'nav.notifications': 'Benachrichtigungen',
    'nav.reports': 'Berichte',
    'lab.tx.ourDentistAsks': '{dentist} aus Ihrem Labor möchte {p} mit {to} teilen. Leiten Sie es weiter oder lehnen Sie ab.',
    'lab.tx.theirDentistAsks': '{dentist} von {from} möchte {p} mit {to} teilen.',
    'lab.tx.waitingForThem': 'An {to} gesendet. Warten auf deren Annahme.',
    'lab.tx.shareWithUs': '{from} möchte {p} mit Ihrem Labor teilen. Nehmen Sie an und wählen Sie einen Ihrer Zahnärzte.',
    'lab.tx.handoverToUs': '{from} möchte {p} an Ihr Labor übergeben. Nehmen Sie an und wählen Sie einen Ihrer Zahnärzte.',
    'lab.tx.theyAccepted': '{to} hat {p} angenommen.',
    'lab.tx.theyAcceptedFor': '{to} hat {p} für {for} angenommen.',
    'lab.tx.weAccepted': 'Ihr Labor hat {p} angenommen.',
    'lab.tx.weAcceptedFor': 'Ihr Labor hat {p} für {for} angenommen.',
    'lab.tx.declined': 'Die Anfrage für {p} wurde abgelehnt.',
    'lab.tx.cancelled': 'Die Anfrage für {p} wurde abgebrochen.',
    'avatar.optionalLab': 'Für Labore optional. Nach der Registrierung nicht mehr änderbar.',
    'chat.cantMessage': 'Sie können dieser Person keine Nachricht senden.',
    'join.title': 'Wählen Sie Ihr Labor',
    'join.sub': 'Bitten Sie ein Labor um Aufnahme, oder nutzen Sie die App vorerst ohne Labor.',
    'join.request': 'Beitritt anfragen',
    'join.confirmTitle': '{lab} um Aufnahme bitten?',
    'join.confirmMsg': 'Das Labor erhält Ihre Anfrage und entscheidet. Solange sie offen ist, können Sie sie zurückziehen.',
    'join.sent': 'Anfrage an {lab} gesendet',
    'join.waiting': 'Warten auf Annahme durch {lab}',
    'join.waitingSub': 'Sobald das Labor Sie annimmt, können Sie die App nutzen.',
    'join.sentAt': 'Gesendet {when}',
    'join.withdraw': 'Zurückziehen',
    'join.withdrawTitle': 'Anfrage zurückziehen?',
    'join.withdrawMsg': 'Danach können Sie dieses oder ein anderes Labor anfragen.',
    'join.withdrawn': 'Anfrage zurückgezogen',
    'join.checkAgain': 'Erneut prüfen',
    'join.noLabs': 'Noch keine Labore zur Auswahl',
    'join.noLabsSub': 'Bitten Sie Ihr Labor, sich zu registrieren, oder wenden Sie sich an den Admin.',
    'join.noLabError': 'Treten Sie einem Labor bei, bevor Sie Patienten anlegen.',
    'join.requestLater': 'Später anfragen',
    'join.requestLaterTitle': 'Ohne Labor fortfahren?',
    'join.requestLaterMsg': 'Sie können die App nutzen und Patienten anlegen. Ein Labor wählen Sie später unter Einstellungen.',
    'join.requestLaterDone': 'Sie können später unter Einstellungen einem Labor beitreten',
    'join.bringTitle': 'Patienten mitnehmen?',
    'join.bringMsg': 'Ausgewählte Patienten werden bei Annahme mit dem Labor geteilt. Andere bleiben privat.',
    'join.bringNone': 'Keine',
    'join.bringContinue': 'Weiter ({n})',
    'join.settingsSection': 'Labor',
    'join.settingsJoin': 'Labor beitreten',
    'join.settingsJoinSub': 'Wählen Sie ein Labor für die Beitrittsanfrage',
    'join.settingsLab': 'Ihr Labor: {lab}',
    'join.pendingTitle': 'Beitrittsanfrage offen',
    'join.transferTitle': 'Zu anderem Labor wechseln',
    'join.transferSub': 'Ihr aktuelles Labor muss den Wechsel genehmigen.',
    'join.transferRequest': 'Wechsel anfragen',
    'join.transferConfirmTitle': 'Wechsel zu {lab} anfragen?',
    'join.transferConfirmMsg': 'Ihr aktuelles Labor entscheidet. Bei Zustimmung verlassen Sie Ihr Labor und treten dem neuen bei.',
    'join.transferSent': 'Wechselanfrage gesendet (warte auf Ihr Labor)',
    'join.transferWaiting': 'Warten auf Freigabe für {lab}',
    'join.transferPendingTitle': 'Wechsel offen',
    'join.withdrawTransferTitle': 'Wechselanfrage zurückziehen?',
    'join.withdrawTransferMsg': 'Sie können später erneut einen Wechsel anfragen.',
    'join.transferWithdrawn': 'Wechselanfrage zurückgezogen',
    'share.yourLab': 'Ihr Labor',
    'share.yourLabHint': 'Sofort geteilt.',
    'share.labHasAccess': 'Ihr Labor hat bereits Zugriff.',
    'share.colleagues': 'Kollegen in Ihrem Labor',
    'share.colleaguesHint': 'Zur Genehmigung an Ihr Labor gesendet.',
    'share.noColleagues': 'Keine Kollegen zum Teilen.',
    'share.alreadyShared': 'Bereits geteilt',
    'share.alreadySharedHint': 'Wer Zugriff hat oder auf die Genehmigung des Labors wartet.',
    'share.pendingLab': 'Wartet auf Labor',
    'nav.lab': 'Mein Labor',
    'lab.title': 'Mein Labor',
    'lab.sub': 'Ihre Zahnärzte, Anfragen, Übergaben und Sichtbarkeit',
    'lab.tab.dentists': 'Zahnärzte',
    'lab.tab.requests': 'Anfragen',
    'lab.tab.transfers': 'Übergaben',
    'lab.tab.sharing': 'Freigaben',
    'lab.tab.settings': 'Einstellungen',
    'lab.noDentists': 'Noch keine Zahnärzte',
    'lab.noDentistsSub': 'Zahnärzte, die Sie annehmen oder die der Admin zuweist, erscheinen hier.',
    'lab.requestRemoval': 'Entfernung beantragen',
    'lab.removeTitle': '{name} aus Ihrem Labor entfernen?',
    'lab.removeMsg': 'Der Admin entscheidet. Nennen Sie den Grund — der Admin sieht ihn.',
    'lab.reasonRequired': 'Grund (erforderlich)',
    'lab.removalSent': 'Entfernung von {name} an den Admin gesendet',
    'lab.noRequests': 'Keine Anfragen',
    'lab.noRequestsSub': 'Beitrittsanfragen von Zahnärzten und Ihre Entfernungsanträge erscheinen hier.',
    'lab.joinRequests': 'Beitrittsanfragen',
    'lab.transferRequests': 'Wechselanfragen',
    'lab.transferBadge': 'Wechsel',
    'lab.transferTo': 'Möchte zu {lab} wechseln',
    'lab.bringCount': 'Nimmt {n} Patienten mit',
    'lab.dentistXferAccepted': 'Wechsel für {name} genehmigt',
    'lab.dentistXferRejected': 'Wechsel für {name} abgelehnt',
    'lab.ourRemovals': 'Ihre Entfernungsanträge',
    'lab.accept': 'Annehmen',
    'lab.joinAccepted': '{name} ist Ihrem Labor beigetreten',
    'lab.joinRejected': 'Anfrage von {name} abgelehnt',
    'lab.status.pending': 'Offen',
    'lab.status.approved': 'Genehmigt',
    'lab.status.rejected': 'Abgelehnt',
    'lab.noTransfers': 'Keine Übergaben',
    'lab.noTransfersSub': 'Zwischen Laboren geteilte oder übergebene Patienten erscheinen hier.',
    'lab.kind.share': 'Teilen',
    'lab.kind.handover': 'Übergabe',
    'lab.transfer.awaiting_sender': 'Wartet auf Ihre Weiterleitung',
    'lab.transfer.awaiting_recipient': 'Wartet auf das empfangende Labor',
    'lab.transfer.accepted': 'Angenommen',
    'lab.transfer.rejected': 'Abgelehnt',
    'lab.transfer.cancelled': 'Abgebrochen',
    'lab.requestedBy': 'von {n}',
    'lab.forDentist': 'für {n}',
    'lab.openPatient': 'Patient öffnen',
    'lab.forward': 'Weiterleiten',
    'lab.forwarded': 'An {lab} weitergeleitet',
    'lab.rejectTransferTitle': 'Übergabe von {p} ablehnen?',
    'lab.transferRejected': 'Übergabe abgelehnt',
    'lab.acceptTransfer': 'Annehmen und Zahnarzt wählen',
    'lab.acceptTransferMsg': 'Welcher Ihrer Zahnärzte übernimmt {p}?',
    'lab.transferAccepted': '{p} für {d} angenommen',
    'lab.noTickets': 'Keine Freigabeanfragen',
    'lab.noTicketsSub': 'Wenn ein Zahnarzt einen Patienten mit einem Kollegen Ihres Labors teilen möchte, entscheiden Sie hier.',
    'lab.ticketLine': '{from} möchte diesen Patienten mit {to} teilen.',
    'lab.ticketApproved': 'Freigabe genehmigt',
    'lab.ticketRejected': 'Freigabe abgelehnt',
    'lab.hideLab': 'Vor anderen Laboren und neuen Zahnärzten verbergen',
    'lab.hideLabMsg': 'Verborgene Labore erscheinen nicht, wenn Zahnärzte ein Labor wählen oder eine Übergabe starten. Sie erhalten dann nur Zahnärzte, die der Admin zuweist.',
    'lab.hideDentists': 'Unsere Zahnärzte vor anderen Laboren verbergen',
    'lab.hideDentistsMsg': 'Andere Labore sehen Ihre Zahnärzte nicht unter Ihrem Labor.',
    'lab.patientFor': 'Für wen ist dieser Patient?',
    'lab.assignDentist': 'Zahnarzt zuweisen',
    'lab.sendToLab': 'An anderes Labor senden',
    'lab.sendToLabMsg': 'Das andere Labor nimmt den Patienten an und wählt einen seiner Zahnärzte.',
    'lab.chooseDentist': 'Zahnarzt wählen…',
    'lab.chooseLab': 'Labor wählen…',
    'lab.targetRequired': 'Wählen Sie einen Zahnarzt oder ein Labor für diesen Patienten.',
    'lab.assignMsg': '{p} wechselt zu diesem Zahnarzt.',
    'lab.assigned': '{p} an {d} zugewiesen',
    'lab.assignForbidden': 'Ihr Labor hat diesen Patienten nicht erhalten.',
    'share.sentToLab': 'Zur Genehmigung an Ihr Labor gesendet',
    'share.useTransfer': 'Diese Person ist in einem anderen Labor — nutzen Sie „Mit anderem Labor teilen“.',
    'share.otherLab': 'Mit anderem Labor teilen',
    'share.otherLabMsg': 'Ihr Labor leitet die Anfrage weiter; das andere Labor nimmt sie an und wählt einen Zahnarzt.',
    'share.transferSent': 'Anfrage zum Teilen mit {lab} an Ihr Labor gesendet',
    'nav.review': 'Prüfung',
    'case.title': 'Fall',
    'case.noLab': 'Noch kein Labor',
    'case.labShared': 'Labor: {lab} · geteilt',
    'case.labNotShared': 'Labor: {lab} · noch nicht geteilt',
    'case.item.scan': 'Scan',
    'case.item.shade': 'Farbanalyse',
    'case.item.smile': 'Lächeln-Vorschau',
    'case.submit': 'An Labor senden',
    'case.submitReadyTitle': 'Diesen Fall an das Labor senden?',
    'case.submitReadyMsg': 'Scan, Farbe und Lächeln sind in der Akte und mit Ihrem Labor geteilt.',
    'case.submitted': 'Zur Prüfung an das Labor gesendet',
    'case.submitFailed': 'Senden fehlgeschlagen',
    'case.incompleteTitle': 'Es fehlen Unterlagen',
    'case.incompleteMsg': 'Fehlt: {items}. Das Labor kann einen unvollständigen Fall ablehnen. Trotzdem senden?',
    'case.submitAnyway': 'Trotzdem senden',
    'case.approve': 'Freigeben',
    'case.reject': 'Ablehnen',
    'case.approveTitle': 'Diesen Fall freigeben?',
    'case.approveMsg': 'Der Fall wird als abgeschlossen markiert und der Zahnarzt benachrichtigt.',
    'case.rejectTitle': 'Fall ablehnen',
    'case.rejectMsg': 'Gesamtanmerkung plus Feedback je Unterlage. Der Zahnarzt sieht das beim Patienten und bei Scan, Farbe und Lächeln.',
    'case.remarksRequired': 'Gesamtanmerkung (erforderlich)',
    'case.itemFeedback': 'Je Unterlage',
    'case.itemOk': 'In Ordnung',
    'case.itemNeedsWork': 'Nacharbeit',
    'case.itemNoteHint': 'Was soll geändert werden?',
    'case.resubmit': 'Erneut an Labor senden',
    'case.resubmitReadyTitle': 'Fall erneut an das Labor senden?',
    'case.resubmitReadyMsg': 'Sie haben den Fall seit der Ablehnung geändert. Das Labor prüft ihn erneut.',
    'case.resubmitUnchangedTitle': 'Noch nichts geändert',
    'case.resubmitUnchangedMsg': 'Sie haben seit der Ablehnung nichts geändert. Trotzdem erneut senden?',
    'case.resolveFirst': 'Übernehmen oder verwerfen Sie zuerst die Vorschläge des Labors.',
    'case.updatedChip': 'Vom Zahnarzt geändert',
    'case.suggested': '{lab} schlägt eine Änderung an {item} vor',
    'case.view': 'Ansehen',
    'case.accept': 'Übernehmen',
    'case.dismiss': 'Verwerfen',
    'case.dismissTitle': 'Vorschlag des Labors verwerfen?',
    'case.dismissMsg': 'Ihr aktuelles Element ({item}) bleibt in der Akte. Das Labor sieht dies beim erneuten Senden.',
    'case.acceptedToast': 'Vorschlag übernommen – senden Sie den Fall erneut, wenn bereit',
    'case.dismissedToast': 'Vorschlag verworfen',
    'case.approveBlocked': 'Sie haben Änderungen vorgeschlagen; der Zahnarzt muss sie bestätigen – lehnen Sie ab, um den Fall zurückzusenden.',
    'case.remarksLabChanged': 'Gesamtanmerkung (optional – „Labor hat Änderungen vorgenommen, bitte bestätigen“)',
    'case.feedbackTitle': 'Laborprüfung · {item}',
    'case.feedbackSub': 'Bewerten Sie dieses Element und lehnen Sie dann im Fall ab oder genehmigen Sie.',
    'case.feedbackSuggested': 'Sie haben eine Änderung vorgeschlagen – der Zahnarzt bestätigt sie.',
    'case.saveNote': 'Notiz speichern',
    'p.waitingLab': 'Wartet auf Freigabe durch das Labor',
    'p.withdraw': 'Zurückziehen',
    'case.event.lab_suggested': 'Labor hat Änderung vorgeschlagen',
    'case.event.suggestion_accepted': 'Vorschlag übernommen',
    'case.event.suggestion_dismissed': 'Vorschlag verworfen',
    'case.openTool': '{item} öffnen',
    'case.approvedToast': 'Fall freigegeben',
    'case.rejectedToast': 'Fall abgelehnt und zurückgeschickt',
    'case.rejectedBanner': 'Vom Labor abgelehnt',
    'case.reopenTitle': 'Fall wieder öffnen?',
    'case.reopenMsg': 'Dadurch wird der Fall wieder geöffnet und erneut zur Prüfung an das Labor gesendet.',
    'case.reopenGo': 'Wieder öffnen',
    'case.replace': 'Ersetzen',
    'case.replaceShadeHint': 'Wählen Sie ein neues Foto. Das Speichern der Analyse ersetzt die alte.',
    'case.replacingShade': 'Gespeicherte Farbanalyse wird ersetzt — speichern Sie die neue, um sie auszutauschen.',
    'case.replacingSmile': 'Gespeicherte Lächeln-Vorschau wird ersetzt — speichern Sie die neue, um sie auszutauschen.',
    'case.history': 'Fallverlauf',
    's.formats': 'Laden Sie oben eine PLY-, STL- oder OBJ-Datei hoch.',
    'settings.sub': 'Konto, Einstellungen und App-Informationen',
    'settings.sec.account': 'Konto & Sicherheit',
    'settings.sec.myLab': 'Mein Labor',
    'settings.sec.rejectSub': 'E-Mail-Adressen, die sich nicht registrieren oder anmelden können. Entfernen Sie eine, um die Registrierung wieder zu erlauben.',
    'pick.search': 'Nach Name oder Praxis suchen',
    'pick.none': 'Keine Treffer',
    'admin.chooseDentistCount': 'Zahnarzt auswählen… ({n})',
    'interpreter.loadingVoice': 'Stimme wird geladen…',
    'lab.pickItem': 'Eintrag auswählen',
    'lab.pickItemSub': 'Details und Aktionen erscheinen hier.',
    'admin.moreCount': '+{n} weitere',
    'interpreter.quickPhrases': 'Schnellsätze',
    'interpreter.stopSpeaking': 'Stopp',
    'interpreter.hold': 'Halten',
    'ch.filterAll': 'Alle',
    'ch.filterLabs': 'Labore',
    'ch.filterDentists': 'Zahnärzte',
    'lab.pickDentist': 'Zahnarzt auswählen',
    'lab.pickDentistSub': 'Kontaktdaten, Patienten und Schnellaktionen erscheinen hier.',
    'lab.dentistNoPatients': 'Noch keine Patienten von diesem Zahnarzt.',
    'p.pickTitle': 'Patient auswählen',
    'p.pickSub': 'Fall, Unterlagen und Details erscheinen hier.',
    'case.items': 'In diesem Fall',
    'case.saved': 'Gespeichert',
    'case.missing': 'Fehlt',
    'case.tileSuggested': 'Änderung vorgeschlagen',
    'case.message': 'Nachricht',
    'case.historyCount': 'Fallverlauf ({n})',
    'case.hintInReview': 'Wartet auf Ihre Entscheidung',
    'case.hintRejected': 'An den Zahnarzt zurückgeschickt. Sie können ihn trotzdem freigeben oder Ihr Feedback ändern.',
    'case.updateFeedback': 'Feedback ändern',
    'case.approveRejectedMsg': 'Sie hatten diesen Fall zurückgeschickt. Mit der Freigabe wird er abgeschlossen und der Zahnarzt benachrichtigt.',
    'records.bestShade': 'Beste Übereinstimmung',
    'records.dentistPick': 'Vom Zahnarzt gewählt',
    'records.aiPick': 'KI-Treffer, bestätigt',
    'records.aiWas': 'KI schlug {shade} vor',
    'records.preview': 'Vorschau',
    'records.openAll': 'Öffnen',
    'case.event.created': 'Erstellt',
    'case.event.scan_added': 'Scan hinzugefügt',
    'case.event.submitted': 'An Labor gesendet',
    'case.event.updated': 'Aktualisiert',
    'case.event.reopened': 'Wieder geöffnet',
    'case.event.approved': 'Freigegeben',
    'case.event.rejected': 'Abgelehnt',
    'case.event.admin_override': 'Status vom Admin geändert',
    'case.event.reassigned': 'Neu zugewiesen',
    'case.event.lab_left': 'Labor verlassen',
    'review.title': 'Prüfung',
    'review.sub': 'Fälle, die auf Ihre Entscheidung warten',
    'review.empty': 'Nichts zu prüfen',
    'review.emptySub': 'Von Ihren Zahnärzten gesendete Fälle erscheinen hier.',
    'review.pick': 'Fall auswählen',
    'review.pickSub': 'Unterlagen und Verlauf erscheinen hier.',
    'review.tab.in_review': 'In Prüfung',
    'review.tab.rejected': 'Abgelehnt',
    'review.tab.completed': 'Freigegeben',
    'review.emptyRejected': 'Keine abgelehnten Fälle',
    'review.emptyRejectedSub': 'Abgelehnte Fälle erscheinen hier, bis der Zahnarzt erneut sendet.',
    'review.emptyCompleted': 'Noch keine freigegebenen Fälle',
    'review.emptyCompletedSub': 'Von Ihnen freigegebene Fälle erscheinen hier.',
    'c.copied': 'Kopiert',
    'avatar.cropTitle': 'Bewegen und skalieren',
    'avatar.cropDone': 'Auswählen',
    'avatar.cropHint': 'Zum Zoomen auseinanderziehen und das Foto im Kreis positionieren.',
    'avatar.cropFailed': 'Dieses Bild konnte nicht geöffnet werden. Bitte ein anderes wählen.',
    'avatar.pickTitle': 'Profilfoto',
    'avatar.takePhoto': 'Foto aufnehmen',
    'avatar.chooseLibrary': 'Aus Mediathek wählen',
    'avatar.add': 'Profilfoto hinzufügen',
    'avatar.retake': 'Foto ändern',
    'avatar.permanent': 'Sichtbar für Ihre Kontakte. Nach der Registrierung nicht mehr änderbar.',
    'avatar.required': 'Bitte fügen Sie ein Profilfoto hinzu.',
    'avatar.change': 'Foto ändern',
    'avatar.changed': 'Foto von {name} aktualisiert',
    'avatar.changeMine': 'Mein Foto ändern',
    'avatar.changedMine': 'Ihr Foto wurde aktualisiert',
    'avatar.done': 'Fertig',
    'admin.chatPlaceholder': 'Nachricht…',
    'admin.chatEmpty': 'Noch keine Nachrichten. Sagen Sie Hallo.',
    'admin.send': 'Senden',
    'admin.chatPhoto': 'Foto',
    'admin.chatVoice': 'Sprachnachricht',
    'admin.chatVideo': 'Video',
    'admin.chatDocument': 'Dokument',
    'admin.pill.removalsOne': '1 Entfernungsanfrage',
    'admin.waitingCountOne': '1 wartet auf Freigabe',
    'admin.att.patientsOne': '1 nicht zugeordneter Patient',
    'admin.att.removalsOne': '1 Entfernungsanfrage',
    'admin.att.dentistsOne': '1 Zahnarzt ohne Labor',
    'admin.att.rejectedOne': '1 abgelehnter Fall',
    'admin.noChats': 'Noch keine Unterhaltungen',
    'admin.openMessages': 'Öffnen',
    'admin.unreadCount': '{n} ungelesen',
    'admin.quickChatSub': 'Ihre letzten Unterhaltungen',
    'admin.quickChat': 'Schnell-Chat',
    'admin.cases': 'Fälle',
    'admin.col.status': 'Status',
    'admin.col.patient': 'Patient',
    'admin.recentPatientsSub': 'Neueste Fallupdates aller Labore',
    'admin.recentPatients': 'Letzte Patientenaktivität',
    'admin.qa.rejectList': 'Sperrliste',
    'admin.qa.patients': 'Patienten zuweisen',
    'admin.qa.assign': 'Zahnärzte zuweisen',
    'admin.qa.signups': 'Registrierungen prüfen',
    'admin.quickActions': 'Schnellaktionen',
    'admin.sev.low': 'Info',
    'admin.sev.medium': 'Bald',
    'admin.sev.high': 'Dringend',
    'admin.att.none': 'Gerade ist nichts zu tun',
    'admin.att.rejectedSub': 'Warten auf Überarbeitung durch den Zahnarzt.',
    'admin.att.rejected': '{n} abgelehnte Fälle',
    'admin.att.dentistsSub': 'Ohne Labor können sie nicht arbeiten.',
    'admin.att.dentists': '{n} Zahnärzte ohne Labor',
    'admin.att.removalsSub': 'Labore warten auf Ihre Entscheidung.',
    'admin.att.removals': '{n} Entfernungsanfragen',
    'admin.att.patientsSub': 'Einem Labor zuweisen, damit der Fall betreut wird.',
    'admin.att.patients': '{n} nicht zugeordnete Patienten',
    'admin.attentionSub': 'Dinge, die nur Sie lösen können',
    'admin.attention': 'Handlungsbedarf',
    'admin.waitingCount': '{n} warten auf Freigabe',
    'admin.tile.openCases': 'Offene Fälle',
    'admin.pill.inReview': '{n} in Prüfung',
    'admin.pill.removals': '{n} Entfernungsanfragen',
    'admin.pill.noLab': '{n} ohne Labor',
    'admin.pill.clear': 'Alles erledigt',
    'admin.pill.review': 'Prüfen',
    'admin.signOutTitle': 'Vom Admin-Konto abmelden?',
    'admin.allNotifications': 'Alle Benachrichtigungen',
    'admin.markAllRead': 'Alle gelesen',
    'admin.showInUsers': 'In Benutzern anzeigen',
    'admin.searchHint': 'Zahnärzte, Labore, Praxen suchen…',
    'admin.hiEvening': 'Guten Abend, {name}',
    'admin.hiAfternoon': 'Guten Tag, {name}',
    'admin.hiMorning': 'Guten Morgen, {name}',
    'admin.since': 'seit {when}',
    'admin.unassigned.no_lab': 'Ohne Labor freigegeben',
    'admin.unassigned.removed': 'Aus dem Labor entfernt',
    'admin.unassigned.lab_deleted': 'Labor gelöscht',
    'admin.reassignedTo': '{name} an {dentist} ({lab}) übergeben',
    'admin.noDentistLabChooses': 'Kein Zahnarzt: {lab} wählt aus',
    'admin.pickDentistMsg': 'Optional. Ohne Zahnarzt wartet der Patient, bis {lab} einen auswählt.',
    'admin.pickDentistTitle': 'Einem Zahnarzt von {lab} zuweisen?',
    'admin.fromOwner': 'von {name}',
    'admin.waitingFor': 'Wartet auf {lab}',
    'admin.reactivated': '{name} reaktiviert',
    'admin.reactivateMsg': 'Das Konto kann sich wieder anmelden. Während der Deaktivierung wurde nichts entfernt.',
    'admin.reactivateTitle': '{name} reaktivieren?',
    'admin.reactivate': 'Reaktivieren',
    'nav.signups': 'Registrierungen',
    'errors.registrationRejected': 'Ihre Registrierung wurde vom Administrator abgelehnt. Mit dieser E-Mail-Adresse können Sie sich weder registrieren noch anmelden. Wenden Sie sich an den Support, falls das ein Irrtum ist.',
    'auth.rejectedTitle': 'Registrierung abgelehnt',
    'admin.dashTitle': 'Admin-Übersicht',
    'labDash.sub': 'Das wartet heute auf Ihr Labor.',
    'labDash.searchHint': 'Zahnärzte und Patienten durchsuchen',
    'labDash.tile.transfers': 'Übergaben an Sie',
    'labDash.tile.joins': 'Beitrittsanfragen',
    'labDash.tile.tickets': 'Freigabeanfragen',
    'labDash.tile.review': 'Fälle zur Prüfung',
    'labDash.action': 'Wartet auf Sie',
    'labDash.actionNone': 'Nichts wartet auf Ihr Labor.',
    'labDash.row.transfer': 'Patientenübergabe — annehmen oder ablehnen',
    'labDash.row.join': 'Möchte Ihrem Labor beitreten',
    'labDash.row.ticket': '{from} möchte mit {to} teilen',
    'labDash.review': 'Prüfwarteschlange',
    'labDash.dentists': 'Ihre Zahnärzte',
    'dash.sub': 'Ihre Stuhlseite für heute.',
    'dash.searchHint': 'Patienten suchen',
    'dash.tile.attention': 'Braucht Aufmerksamkeit',
    'dash.tile.today': 'Termine heute',
    'dash.tile.messages': 'Ungelesene Nachrichten',
    'dash.tile.rejected': 'Abgelehnte Fälle',
    'dash.pill.noneToday': 'Keine heute',
    'dash.quickActions': 'Schnellaktionen',
    'dash.quickActionsSub': 'Zu den täglichen Werkzeugen',
    'dash.qa.newPatient': 'Neuer Patient',
    'dash.qa.camera': 'Kamera',
    'dash.qa.shade': 'Farbbestimmung',
    'dash.qa.scans': 'Scans',
    'dash.qa.smile': 'Smile Preview',
    'dash.qa.appointments': 'Termine',
    'dash.attention': 'Braucht Aufmerksamkeit',
    'dash.attentionNone': 'Gerade braucht nichts Ihre Aufmerksamkeit.',
    'dash.recentPatients': 'Aktuelle Patienten',
    'dash.recentPatientsSub': 'Neueste Updates in Ihrer Liste',
    'share.whoHasAccess': 'Wer hat Zugriff',
    'share.onlyOwner': 'Bisher hat nur der Eigentümer Zugriff.',
    'share.ownerSection': 'Eigentümer',
    'share.sharedWithSection': 'Geteilt mit',
    'share.youHaveAccess': 'Sie haben geteilten Zugriff auf diesen Patienten.',
    'share.yourAccess': 'Ihr Zugriff',
    'appt.dentist': 'Zahnarzt',
    'appt.assignDentist': 'Zahnarzt zuweisen',
    'admin.dashSub': 'Das passiert heute bei Laboren, Zahnärzten und Fällen.',
    'admin.tile.signups': 'Offene Registrierungen',
    'admin.tile.dentists': 'Zahnärzte',
    'admin.tile.labs': 'Labore',
    'admin.tile.unassignedDentists': 'Zahnärzte ohne Labor',
    'admin.tile.unassignedPatients': 'Nicht zugeordnete Patienten',
    'admin.tile.removals': 'Entfernungsanfragen',
    'admin.casesByStatus': 'Fälle nach Status',
    'admin.casesTotal': '{n} Fälle insgesamt',
    'admin.signupQueue': 'Registrierungsanfragen',
    'admin.seeAll': 'Alle anzeigen',
    'admin.loadFailed': 'Laden fehlgeschlagen',
    'admin.retry': 'Erneut versuchen',
    'admin.signupsTitle': 'Registrierungen',
    'admin.signupsSub': 'Jedes neue Konto freigeben oder ablehnen',
    'admin.pending': 'Offen',
    'admin.rejectList': 'Sperrliste',
    'admin.noSignups': 'Keine offenen Registrierungen',
    'admin.noSignupsSub': 'Neue Registrierungen von Zahnärzten und Laboren erscheinen hier zur Freigabe.',
    'admin.noRejected': 'Die Sperrliste ist leer',
    'admin.noRejectedSub': 'Abgelehnte E-Mail-Adressen werden hier aufgeführt.',
    'admin.approve': 'Freigeben',
    'admin.reject': 'Ablehnen',
    'admin.continue': 'Weiter',
    'admin.approveTitle': '{name} freigeben?',
    'admin.approveDentistMsg': 'Optional ein Labor zuweisen. Ohne Labor wählt der Zahnarzt bei der ersten Anmeldung eines, und dieses Labor muss ihn annehmen.',
    'admin.approveNoLab': 'Ohne Labor freigeben',
    'admin.approveLabMsg': 'Das Labor kann sich sofort anmelden.',
    'admin.approved': '{name} freigegeben',
    'admin.rejectTitle': '{name} ablehnen?',
    'admin.rejectReasonMsg': 'Optional einen Grund angeben. Er steht in der E-Mail, die wir senden.',
    'admin.reasonOptional': 'Grund (optional)',
    'admin.rejectConfirmTitle': 'Registrierung ablehnen?',
    'admin.rejectConfirmMsg': 'Das Konto wird gelöscht und {email} kommt auf die Sperrliste. Die Person erhält dazu eine E-Mail. Mit dieser Adresse ist weder Registrierung noch Anmeldung möglich, bis Sie sie von der Liste entfernen.',
    'admin.rejected': '{name} abgelehnt',
    'admin.clinic': 'Praxis',
    'admin.signedUp': 'Registriert {when}',
    'admin.reason': 'Grund',
    'admin.noReason': 'keiner angegeben',
    'admin.rejectedBy': 'Abgelehnt {when} von {by}',
    'admin.unreject': 'Von Liste entfernen',
    'admin.unrejectTitle': 'Von der Sperrliste entfernen?',
    'admin.unrejectMsg': '{email} kann sich wieder registrieren. Das ist keine Freigabe: Eine neue Registrierung braucht weiterhin Ihre Zustimmung.',
    'admin.unrejected': '{email} von der Sperrliste entfernt',
    'admin.usersSub': 'Labore und ihre Zahnärzte',
    'admin.byLab': 'Nach Labor',
    'admin.unassignedDentists': 'Ohne Labor',
    'admin.removalRequests': 'Entfernungsanfragen',
    'admin.searchUsers': 'Labore, Zahnärzte, Praxen, E-Mails suchen…',
    'admin.noLabs': 'Noch keine Labore',
    'admin.noLabsSub': 'Freigegebene Labore erscheinen hier mit ihren Zahnärzten.',
    'admin.noMatches': 'Keine Treffer',
    'admin.noMatchesSub': 'Anderen Namen, andere Praxis oder E-Mail versuchen.',
    'admin.dentistCount': '{n} Zahnärzte',
    'admin.dentistCountOne': '1 Zahnarzt',
    'admin.hidden': 'Verborgen',
    'admin.hiddenFromLabs': 'Für andere Labore verborgen',
    'admin.dentistsHidden': 'Zahnärzte verborgen',
    'admin.labNoDentists': 'Noch keine Zahnärzte in diesem Labor.',
    'admin.noLab': 'Kein Labor',
    'admin.noClinic': 'Keine Praxis',
    'admin.deactivatedBadge': 'Deaktiviert',
    'admin.assignLab': 'Labor zuweisen',
    'admin.move': 'Verschieben',
    'admin.more': 'Mehr',
    'admin.deactivateOrDelete': 'Deaktivieren oder löschen…',
    'admin.moveTitle': '{name} verschieben',
    'admin.moveMsg': 'Labor wählen, zu dem dieser Zahnarzt gehört.',
    'admin.removeFromLab': 'Aus dem Labor entfernen',
    'admin.moveConfirmTitle': '{name} zu {lab} verschieben?',
    'admin.moveNoApproval': '{lab} muss nicht zustimmen.',
    'admin.leaveLabEffects': '{lab} verliert den Zugriff auf die offenen Fälle dieses Zahnarztes; Fälle in Prüfung gehen zurück auf „In Bearbeitung“. Abgeschlossene Fälle kann {lab} weiterhin ansehen.',
    'admin.removeEffects': 'Der Zahnarzt behält seine Patienten und kann die App weiter nutzen, ohne Labor aber keine Fälle einreichen und nicht über ein Labor teilen. Er wird gebeten, ein Labor zu wählen – oder Sie weisen eines unter „Ohne Labor“ zu.',
    'admin.removeTitle': '{name} aus dem Labor entfernen?',
    'admin.remove': 'Entfernen',
    'admin.moved': '{name} zu {lab} verschoben',
    'admin.removedFromLab': '{name} aus dem Labor entfernt',
    'admin.deleteTitle': '{name} löschen?',
    'admin.deleteDentistEffects': 'Deaktivieren: keine Anmeldung mehr möglich. Alles bleibt erhalten, und Sie können das Konto jederzeit reaktivieren.\n\nEndgültig löschen: kann nicht rückgängig gemacht werden. Die Patienten bleiben erhalten und werden nicht zugeordnet (Patienten › Ohne Zuordnung).',
    'admin.deleteLabEffects': 'Deaktivieren: Das Labor kann sich nicht mehr anmelden. Alles bleibt erhalten, und Sie können es jederzeit reaktivieren.\n\nEndgültig löschen: kann nicht rückgängig gemacht werden. Seine {n} werden nicht zugeordnet, und Fälle in Prüfung gehen zurück auf „In Bearbeitung“. Patienten sind nicht betroffen.',
    'admin.deactivate': 'Deaktivieren',
    'admin.deletePermanently': 'Endgültig löschen',
    'admin.deactivated': '{name} deaktiviert',
    'admin.deleted': '{name} gelöscht',
    'admin.noUnassignedDentists': 'Jeder Zahnarzt hat ein Labor',
    'admin.noUnassignedDentistsSub': 'Hier erscheinen Zahnärzte, deren Labor gelöscht wurde, die entfernt wurden oder ohne Labor freigegeben wurden.',
    'admin.noRemovals': 'Keine Entfernungsanfragen',
    'admin.noRemovalsSub': 'Wenn ein Labor einen Zahnarzt entfernen möchte, entscheiden Sie hier.',
    'admin.requestedBy': 'Angefragt von {lab} · {when}',
    'admin.deny': 'Ablehnen',
    'admin.approveRemovalTitle': '{name} aus {lab} entfernen?',
    'admin.denyRemovalTitle': '{name} in {lab} behalten?',
    'admin.denyRemovalMsg': 'Der Zahnarzt bleibt im Labor und die Anfrage wird geschlossen.',
    'admin.removalApproved': 'Zahnarzt aus dem Labor entfernt',
    'admin.removalDenied': 'Anfrage abgelehnt',
    'admin.searchLabs': 'Labore suchen',
    'admin.noLabsFound': 'Keine Labore gefunden',
    'admin.patientsSub': 'Alle Patienten mit Besitzer, Labor und Fallverlauf',
    'admin.allPatients': 'Alle Patienten',
    'admin.unassignedPatients': 'Ohne Zuordnung',
    'admin.searchPatients': 'Patienten suchen…',
    'admin.filterLab': 'Nach Labor filtern',
    'admin.allLabs': 'Alle Labore',
    'admin.noPatients': 'Keine Patienten gefunden',
    'admin.noPatientsSub': 'Anderen Status, anderes Labor oder andere Suche versuchen.',
    'admin.noUnassignedPatients': 'Keine nicht zugeordneten Patienten',
    'admin.noUnassignedPatientsSub': 'Hier erscheinen Patienten, deren Zahnarzt gelöscht wurde oder für die ein Labor noch einen Zahnarzt wählen muss.',
    'admin.pickPatient': 'Patienten auswählen',
    'admin.pickPatientSub': 'Besitzer, Labor, Unterlagen und Fallverlauf erscheinen hier.',
    'admin.owner': 'Besitzer',
    'admin.lab': 'Labor',
    'admin.updated': 'Aktualisiert {when}',
    'admin.waitingForLab': 'Wartet auf Labor',
    'admin.ownerDeleted': 'Zahnarzt gelöscht',
    'admin.back': 'Zurück',
    'admin.overrideStatus': 'Status ändern',
    'admin.overrideMsg': 'Das überschreibt den Fallstatus und wird mit Ihrer Notiz im Fallverlauf protokolliert.',
    'admin.noteRequired': 'Notiz (erforderlich)',
    'admin.statusChanged': 'Status auf {status} geändert',
    'admin.reassignLab': 'Labor neu zuweisen',
    'admin.reassignTitle': '{name} neu zuweisen',
    'admin.reassignMsg': 'Empfangendes Labor wählen. Danach können Sie einen seiner Zahnärzte auswählen oder das dem Labor überlassen.',
    'admin.reassigned': '{name} an {lab} übergeben',
    'admin.sharedWith': 'Geteilt mit',
    'admin.nobody': 'Niemandem',
    'admin.lastUpdate': 'Letzte Änderung',
    'admin.records': 'Unterlagen',
    'admin.shadeAnalyses': 'Farbanalysen',
    'admin.none': 'Noch keine',
    'admin.history': 'Fallverlauf',
    'admin.noHistory': 'Noch keine Ereignisse.',
    'admin.event.created': 'Erstellt',
    'admin.event.submitted': 'An Labor übermittelt',
    'admin.event.approved': 'Freigegeben',
    'admin.event.rejected': 'Abgelehnt',
    'admin.event.updated': 'Aktualisiert',
    'admin.event.reassigned': 'Neu zugewiesen',
    'admin.event.admin_override': 'Status vom Admin geändert',
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
    'common.fetchingData': 'Daten werden geladen…',
    'common.required': 'Pflichtfeld',
    'common.continue': 'Weiter',
    'common.copy': 'Kopieren',
    'common.add': 'Hinzufügen',
    'common.online': 'Online',
    'common.offline': 'Offline',
    'common.preferenceSaved': 'Einstellung gespeichert',
    'common.addPatient': 'Patient hinzufügen',
    'errors.sessionExpired':
        'Ihre Sitzung ist abgelaufen. Bitte erneut anmelden.',
    'errors.noPermission': 'Sie haben keine Berechtigung für diese Aktion.',
    'errors.notFound':
        'Der Eintrag wurde nicht gefunden. Er wurde möglicherweise entfernt.',
    'errors.validation':
        'Bitte prüfen Sie Ihre Angaben und versuchen Sie es erneut.',
    'errors.network':
        'Server nicht erreichbar. Prüfen Sie die Verbindung und versuchen Sie es erneut.',
    'errors.timeout': 'Das hat zu lange gedauert. Bitte erneut versuchen.',
    'errors.server':
        'Auf unserer Seite ist etwas schiefgelaufen. Bitte erneut versuchen.',
    'errors.generic': 'Etwas ist schiefgelaufen. Bitte erneut versuchen.',
    'errors.badCredentials':
        'E-Mail oder Passwort ist falsch. Bitte erneut versuchen.',
    'errors.tooMany':
        'Zu viele Versuche. Bitte kurz warten und erneut versuchen.',
    'errors.conflict':
        'Die Änderung steht im Konflikt mit vorhandenen Daten. Bitte aktualisieren und erneut versuchen.',
    'errors.downloadFailed':
        'Die Datei konnte nicht heruntergeladen werden. Bitte erneut versuchen.',
    'common.searchPatients': 'Patienten suchen…',
    'common.noPatientsYet': 'Noch keine Patienten',
    'common.archive': 'Archivieren',
    'patients.noMatching': 'Keine passenden Patienten',
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
    'auth.roleAdmin': 'Admin',
    'auth.roleLaboratory': 'Labor',
    'auth.roleLab': 'Labor',
    'auth.alreadyHaveAccount': 'Bereits ein Konto? Anmelden',
    'auth.errNameEmailPassword': 'Name, E-Mail und Passwort sind erforderlich',
    'auth.errAllFieldsRequired': 'Alle Felder sind erforderlich',
    'auth.errPasswordShort':
        'Passwort muss mindestens 8 Zeichen, 1 Großbuchstaben und 1 Zahl haben',
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
        'Benachrichtigungseinstellungen für dieses Gerät',
    'settings.notifyMaster': 'Benachrichtigungen aktivieren',
    'settings.notifyMasterSub':
        'Hinweise zu Labornachrichten, Fallstatus und Scanqualität erhalten',
    'settings.notifyMessages': 'Labornachrichten',
    'settings.notifyMessagesSub': 'Neuer Chat vom Labor zu einem Fall',
    'settings.notifyCase': 'Fallstatus-Änderungen',
    'settings.notifyCaseSub':
        'Ausstehend, in Prüfung, abgeschlossen, abgelehnt',
    'settings.notifyScan': 'Scan-Qualitätswarnungen',
    'settings.notifyScanSub': 'Körnig / verzerrt — erneuten Scan anfordern',
    'settings.languageTitle': 'Sprache & Region',
    'settings.languageSub': 'UI-Sprache für die gesamte App',
    'settings.appLanguage': 'App-Sprache',
    'about.title': 'Über uns',
    'about.whatTitle': 'Was ist Elite Dent?',
    'about.whatBody': 'Elite Dent ist ein KI-gestützter Arbeitsbereich, der Zahnarztpraxen und Dentallabore verbindet. Fotos und Scans erfassen, KI-Farb- und Scanqualitätsprüfungen erhalten, Patienten und Fälle verwalten und mit dem Labor kommunizieren – alles an einem Ort.',
    'about.whoTitle': 'Für wen ist es?',
    'about.whoBody': 'Für Zahnärzte, Praxisteams und Zahntechniker, die schneller und klarer kommunizieren und weniger Neuanfertigungen zwischen Praxis und Labor wollen.',
    'about.support': 'Support',
    'about.privacy': 'Datenschutzerklärung',
    'about.imprint': 'Impressum',
    'about.website': 'Website',
    'about.featuresTitle': 'Was Sie tun können',
    'about.linksTitle': 'Support & Rechtliches',
    'about.accountTitle': 'Ihr Konto',
    'about.userId': 'Benutzer-ID',
    'about.name': 'Name',
    'about.clinic': 'Praxis',
    'about.credit': 'Design und Entwicklung von',
    'about.f.shade': 'KI-Farbbestimmung',
    'about.f.shadeSub': 'Zahn fotografieren und in Sekunden eine Farbempfehlung erhalten.',
    'about.f.scans': 'Scanqualitätsprüfung',
    'about.f.scansSub': 'Probleme in Intraoralscans erkennen, bevor sie ins Labor gehen.',
    'about.f.patients': 'Patienten & Fälle',
    'about.f.patientsSub': 'Patientendaten, Fotos und Scans an einem Ort.',
    'about.f.messages': 'Labor-Chat',
    'about.f.messagesSub': 'Mit dem Labor chatten, Dateien und Sprachnachrichten teilen.',
    'about.f.interpreter': 'Dolmetscher',
    'about.f.interpreterSub': 'Live mit Patienten in verschiedenen Sprachen sprechen.',
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
    'settings.deleteAccount': 'Konto löschen',
    'settings.deleteAccountBody':
        'Dadurch werden Ihr Login und Ihre persönlichen Daten dauerhaft entfernt. '
        'Patientenakten werden nicht gelöscht, sie bleiben bei der Praxis. '
        'Geben Sie DELETE ein, um fortzufahren.',
    'settings.deleteConfirmToken': 'DELETE',
    'settings.continue': 'Weiter',
    'settings.confirmWithPassword': 'Mit Passwort bestätigen',
    'settings.enterPasswordToFinish':
        'Geben Sie Ihr Kontopasswort ein, um abzuschließen.',
    'settings.passwordRequired': 'Passwort ist erforderlich.',
    'settings.deletingAccount': 'Konto wird gelöscht…',
    'settings.loading': 'Einstellungen werden geladen…',
    'settings.accountFallback': 'Konto',
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
        'Neues Passwort muss mindestens 8 Zeichen, 1 Großbuchstaben und 1 Zahl haben',
    'profile.errNewPasswordMismatch': 'Neue Passwörter stimmen nicht überein',
    'profile.clinicHint': 'z. B. Elite Dent München',
    'dash.goodMorning': 'Guten Morgen, Dr. {name}',
    'dash.goodAfternoon': 'Guten Tag, Dr. {name}',
    'dash.goodEvening': 'Guten Abend, Dr. {name}',
    'dash.loading': 'Klinikdaten werden geladen…',
    'dash.noCases': 'Noch keine offenen Fälle — legen Sie einen Patienten an.',
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
    'labs.title': 'Systembenutzer',
    'labs.subtitle': 'Systembenutzerprofile verwalten',
    'labs.searchHint': 'Suche nach Name, E-Mail, Praxis…',
    'labs.filterUnverified': 'Ungeprüft',
    'labs.filterVerified': 'Geprüft',
    'labs.empty': 'Keine Nutzer gefunden.',
    'labs.emptyFilter': 'Keine Nutzer entsprechen diesem Filter.',
    'labs.verified': 'Geprüft',
    'labs.unverified': 'Ungeprüft',
    'labs.verify': 'Nutzer prüfen',
    'labs.count': '{shown} angezeigt · {total} gesamt',
    'labs.loading': 'Labore werden geladen…',
    'labs.openingChat': 'Unterhaltung wird geöffnet…',
    'labs.verifyBeforeMessage':
        'Prüfen Sie dieses Labor, bevor Sie Nachrichten senden.',
    'labs.emptyVerifiedHint': 'Geprüfte Labore erscheinen hier.',
    'labs.emptyFilterHint': 'Anderen Filter oder Suche versuchen.',
    'labs.message': 'Nachricht',
    'labs.clinicLab': 'Praxis / Labor',
    'labs.status': 'Status',
    'labs.updated': 'Aktualisiert',
    'features.camera': 'Kameraaufnahme',
    'features.scans': 'Scans',
    'features.shade': 'Farbbestimmung',
    'features.smile': 'Lächeln-Vorschau',
    'features.scanBody': 'Scanbody',
    'features.messages': 'Nachrichten',
    'features.notifications': 'Benachrichtigungen',
    'features.reports': 'Berichte',
    'features.selectPatient': 'Patient wählen',
    'reports.subtitle': 'Praxisleistung, Fall-Pipeline und KI-Abdeckung',
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
    'reports.copy': 'Kopieren',
    'reports.periodLine': 'Zeitraum: {period}',
    'reports.activeShort': 'Aktiv',
    'reports.avgTimeShort': 'Ø Zeit',
    'reports.inPipeline': 'In der Pipeline',
    'reports.toComplete': 'Bis Abschluss',
    'reports.newCount': '{n} neu',
    'reports.followUpHint': 'Fälle, die eine Nachverfolgung brauchen',
    'reports.allClear': 'Alles erledigt',
    'reports.patientFallback': 'Patient',
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
    'notifications.typeAppointment': 'Termin',
    'notifications.typeScanBody': 'Scanbody',
    'notifications.typeSync': 'Sync',
    'notifications.typeExport': 'Export',
    'status.inProgress': 'In Bearbeitung',
    'status.awaitingScan': 'Wartet auf Scan',
    'status.inReview': 'In Prüfung',
    'status.complete': 'Abgeschlossen',
    'status.rejected': 'Abgelehnt',
    'status.noCase': 'Kein Fall',
    'common.statusUpdated': 'Status aktualisiert: {label}',
    'common.search': 'Suchen',
    'common.edit': 'Bearbeiten',
    'common.delete': 'Löschen',
    'common.share': 'Teilen',
    'common.today': 'Heute',
    'common.tomorrow': 'Morgen',
    'common.inOneWeek': 'In 1 Woche',
    'common.yesterday': 'Gestern',
    'common.fullscreen': 'Vollbild',
    'common.exitFullscreen': 'Vollbild beenden',
    'common.changeStatus': 'Status ändern',
    'appointments.title': 'Termine',
    'appointments.subtitle':
        'Besuche planen und Bestätigungs-E-Mails an Patienten senden',
    'appointments.book': 'Buchen',
    'appointments.bookTitle': 'Termin buchen',
    'appointments.editTitle': 'Termin bearbeiten',
    'appointments.empty': 'Noch keine Termine',
    'appointments.allPatients': 'Alle Patienten',
    'appointments.savedToast':
        'Termin gespeichert. E-Mail-Benachrichtigung an den Patienten gesendet.',
    'appointments.notesHint': 'Klinische Notizen / Besuchszusammenfassung',
    'appointments.selectPatient': 'Patient auswählen',
    'appointments.date': 'Datum',
    'appointments.time': 'Uhrzeit',
    'appointments.duration': 'Dauer',
    'appointments.notes': 'Notizen',
    'appointments.status': 'Status',
    'appointments.saveChanges': 'Änderungen speichern',
    'appointments.bookSubmit': 'Termin buchen',
    'appointments.startTime': 'Startzeit',
    'appointments.endAfterStart': 'Endzeit muss nach der Startzeit liegen',
    'appointments.endsAt': 'Endet um {time}',
    'appointments.saving': 'Termin wird gespeichert…',
    'appointments.filtering': 'Terminplan wird gefiltert',
    'appointments.filterEmpty': 'Keine Treffer für diesen Filter',
    'appointments.filterEmptyHint':
        'Anderen Status oder Patienten wählen, oder neuen Termin buchen.',
    'appointments.bookEmptyHint':
        'Buchen Sie einen Termin, um eine Bestätigungs-E-Mail an den Patienten zu senden.',
    'appointments.noPatientsYet': 'Noch keine Patienten',
    'appointments.inClinicOne': '1 Patient in der Praxis',
    'appointments.inClinic': '{n} Patienten in der Praxis',
    'appointments.minutesShort': '{n} Min.',
    'appointments.statusScheduled': 'Geplant',
    'appointments.statusCompleted': 'Abgeschlossen',
    'appointments.statusCancelled': 'Abgesagt',
    'appointments.statusNoShow': 'Nicht erschienen',
    'messages.subtitle': 'Posteingang und Gespräche mit dem Labor',
    'messages.placeholder': 'Nachricht',
    'messages.newChat': 'Neuer Chat',
    'messages.startChat': 'Chat starten',
    'messages.empty': 'Noch keine Nachrichten — schreiben Sie hallo.',
    'messages.selectConversation': 'Wählen Sie eine Unterhaltung zum Schreiben',
    'messages.attach': 'Anhängen',
    'messages.active': 'Aktiv',
    'messages.reconnecting': 'Verbinde erneut…',
    'messages.noConversations': 'Noch keine Unterhaltungen.',
    'messages.noMatch': 'Keine Unterhaltungen passen zur Suche.',
    'messages.newTitle': 'Neue Nachricht',
    'scans.subtitle': 'Intraorale Scans dieses Patienten, vor dem Versand ans Labor geprüft',
    'scans.upload': 'Scan hochladen',
    'scans.uploading': 'Wird hochgeladen…',
    'scans.delete': 'Scan löschen',
    'scans.deleted': 'Scan gelöscht',
    'scans.noneSelected': 'Kein Scan ausgewählt',
    'scans.selectPatient': 'Patient auswählen',
    'scans.emptyFor': 'Noch keine Scans für {name}',
    'scans.rescanNow': 'Jetzt neu scannen — bevor der Patient geht',
    'shade.cancel': 'Abbrechen',
    'shade.reset': 'Zurücksetzen',
    'shade.apply': 'Übernehmen',
    'shade.adjustEdges': 'Ränder anpassen',
    'shade.lips': 'Lippen',
    'shade.symmetry': 'Symmetrielinien',
    'shade.focusTooth': 'Nur ausgewählter Zahn',
    'shade.delete': 'Löschen',
    'shade.addTooth': 'Zahn hinzufügen',
    'shade.upload': 'Hochladen',
    'shade.reupload': 'Erneut hochladen',
    'patients.status': 'Status',
    'patients.editTitle': 'Patient bearbeiten',
    'patients.saveChanges': 'Änderungen speichern',
    'patients.createdToast': 'Patient erfolgreich angelegt',
    'patients.updatedToast': 'Patient aktualisiert',
    'patients.deleteTitle': 'Patient löschen?',
    'patients.deleteBody': 'Wie möchten Sie {name} entfernen?',
    'patients.archiveOption': 'Patient archivieren',
    'patients.archiveOptionSub':
        'Soft-Delete — Daten bleiben zur Wiederherstellung',
    'patients.hardDeleteOption': 'Endgültig löschen',
    'patients.hardDeleteOptionSub':
        'Hard-Delete — dauerhafte Löschung nach DSGVO Art. 17',
    'patients.typeDeleteConfirm': 'DELETE eingeben zur Bestätigung',
    'patients.opening': 'Patient wird geöffnet…',
    'patients.shownTotal': '{shown} angezeigt · {total} gesamt',
    'common.request': 'Anfragen',
    'common.approve': 'Genehmigen',
    'common.reject': 'Ablehnen',
    'common.done': 'Fertig',
    'common.close': 'Schließen',
    'common.rename': 'Umbenennen',
    'common.retry': 'Erneut versuchen',
    'common.undo': 'Rückgängig',
    'common.redo': 'Wiederholen',
    'common.working': 'Wird bearbeitet…',
    'common.uploading': 'Wird hochgeladen…',
    'common.tapToSelect': 'Tippen zum Auswählen',
    'common.invalidDate': 'Ungültiges Datum',
    'common.yearsOld': '{n} Jahre alt',
    'common.oneYearOld': '1 Jahr alt',
    'common.expandSidebar': 'Seitenleiste erweitern',
    'common.collapseSidebar': 'Seitenleiste einklappen',
    'common.menu': 'Menü',
    'common.showPassword': 'Passwort anzeigen',
    'common.hidePassword': 'Passwort verbergen',
    'common.minPasswordLength': 'Mindestens 8 Zeichen',
    'common.openDownload': 'Öffnen / herunterladen',
    'dash.loadingCases': 'Aktuelle Fälle werden geladen…',
    'dash.loadingActivity': 'Aktivität wird geladen…',
    'patients.loading': 'Patienten werden geladen…',
    'patients.loadingAccess': 'Zugriff wird geladen…',
    'patients.loadingNotes': 'Notizen werden geladen…',
    'patients.loadingStaff': 'Berechtigte Mitarbeiter werden geladen…',
    'patients.loadingAccessRequests': 'Zugriffsanfragen werden geladen…',
    'patients.editNote': 'Notiz bearbeiten',
    'patients.deleteNoteTitle': 'Notiz löschen?',
    'patients.deleteNoteBody': 'Diese klinische Notiz wird dauerhaft entfernt.',
    'patients.noteHint': 'Klinische Notiz hinzufügen…',
    'patients.noteAdded': 'Notiz hinzugefügt',
    'patients.noteUpdated': 'Notiz aktualisiert',
    'patients.noteDeleted': 'Notiz gelöscht',
    'patients.onlyAuthorEdit':
        'Nur der Autor kann diese klinische Notiz bearbeiten.',
    'patients.onlyAuthorDelete':
        'Nur der Autor kann diese klinische Notiz löschen.',
    'patients.clinicalNotePlaceholder': 'Klinische Notiz',
    'patients.pendingAccess': 'Ausstehende Zugriffsanfragen',
    'patients.revoke': 'Widerrufen',
    'patients.regrant': 'Erneut gewähren',
    'patients.savePatient': 'Patient speichern',
    'patients.refreshPatients': 'Patienten aktualisieren',
    'appointments.loading': 'Termine werden geladen…',
    'appointments.selectDate': 'Termindatum auswählen',
    'appointments.editTooltip': 'Termin bearbeiten',
    'appointments.starts': 'Beginn',
    'profile.loading': 'Profil wird geladen…',
    'scans.loading': 'Scans werden geladen…',
    'scans.uploadingScan': 'Scan wird hochgeladen…',
    'shade.loading': 'Farbbestimmung wird geladen…',
    'shade.detecting': 'Wird erkannt…',
    'shade.waitTip1': 'Zähne und Kontakte werden erfasst…',
    'shade.waitTip2': 'Schmelz wird mit VITA-Farben abgeglichen…',
    'shade.waitTip3':
        'Sie können den Tab wechseln — die Erkennung läuft weiter…',
    'shade.waitTip4': 'Smile-Band und Zahnfleisch werden geprüft…',
    'shade.waitTip5': 'Umrisse werden verfeinert — gleich fertig…',
    'shade.uploadDetect': 'Hochladen & erkennen',
    'shade.removeSave': 'Speicherung entfernen?',
    'shade.deleteFromSession': '{shade} aus dieser Sitzung löschen.',
    'shade.similarShades': 'Ähnliche Farben',
    'shade.bestOverall': 'Gesamtbestes',
    'shade.acrossAllTeeth': 'Über alle Zähne',
    'shade.deleteTooth': 'Zahn löschen',
    'shade.photoTitle': 'Farbfoto',
    'shade.photoMessage': 'Aktion für dieses Foto wählen.',
    'shade.uploadAnother': 'Weiteres hochladen',
    'shade.deletePhoto': 'Foto löschen',
    'shade.openSession': 'Sitzung öffnen',
    'shade.closeSession': 'Sitzung schließen',
    'shade.removeFromSession': 'Aus Sitzung entfernen',
    'smile.loading': 'Lächeln-Vorschau wird geladen…',
    'smile.loadPhoto': 'Foto laden',
    'smile.changePhoto': 'Foto ändern',
    'smile.loadPatientPhoto': 'Patientenfoto laden',
    'smile.guides': 'Hilfslinien',
    'smile.size': 'Größe',
    'smile.width': 'Breite',
    'smile.height': 'Höhe',
    'smile.rotate': 'Drehen',
    'smile.blend': 'Überblendung',
    'smile.scale': 'Skalierung',
    'smile.opacity': 'Deckkraft',
    'smile.useShape': 'Form {n} verwenden',
    'smile.shapeSoftOval': 'Weiches Oval',
    'smile.shapeClassicOval': 'Klassisches Oval',
    'smile.shapeRounded': 'Abgerundet',
    'smile.shapeNaturalOval': 'Natürliches Oval',
    'smile.shapeYouthful': 'Jugendlich',
    'smile.shapeSoftSquare': 'Weiches Quadrat',
    'smile.shapeBalanced': 'Ausgewogen',
    'smile.shapeSoftRect': 'Weiches Rechteck',
    'smile.shapeHollywood': 'Hollywood',
    'smile.shapeStrongSquare': 'Starkes Quadrat',
    'smile.shapeTapered': 'Verjüngt',
    'smile.shapeCanineLift': 'Eckzahn-Anhebung',
    'scanBody.loading': 'Scanbody wird geladen…',
    'scanBody.saveToCase': 'Zum Fall speichern',
    'scanBody.matchTable': 'Tabelle abgleichen',
    'scanBody.detectFromPhoto': 'Aus Foto erkennen',
    'scanBody.detected': 'Erkannt',
    'scanBody.pixels': 'Pixel',
    'scanBody.tableMatch': 'Tabellen-Treffer',
    'scanBody.tooth': 'Zahn',
    'scanBody.manufacturer': 'Hersteller',
    'scanBody.platform': 'Plattform',
    'scanBody.confidence': 'Konfidenz',
    'scanBody.diameterHint': 'z. B. 4.1',
    'camera.deletePhotoTitle': 'Foto löschen?',
    'camera.deletePhotoBody':
        'Dieses {angle}-Foto aus dem Datensatz von {name} entfernen.',
    'camera.renamePhoto': 'Foto umbenennen',
    'camera.choosePatient': 'Patient auswählen',
    'camera.choosePatientBody':
        'Wählen Sie oben einen Patienten, um Stuhlseitenfotos aufzunehmen.',
    'camera.noPhotosYet': 'Noch keine Fotos',
    'camera.noAnglePhotos': 'Keine {angle}-Fotos',
    'camera.takePhoto': 'Foto aufnehmen',
    'camera.gallery': 'Galerie',
    'camera.preparing': 'Kamera wird vorbereitet…',
    'camera.addPatient': 'Patient hinzufügen',
    'camera.photoOptions': 'Foto-Optionen',
    'camera.viewFullscreen': 'Vollbild anzeigen',
    'camera.openShade': 'Mit Farbbestimmung öffnen',
    'camera.openSmile': 'Mit Lächeln-Vorschau öffnen',
    'camera.captureFocus': 'Aufnahme-Fokus',
    'camera.retryCamera': 'Kamera erneut versuchen',
    'camera.switchCamera': 'Kamera wechseln',
    'camera.resetOverlay': 'Overlay zurücksetzen',
    'messages.loadingConversations': 'Unterhaltungen werden geladen…',
    'messages.loadingChat': 'Chat wird geladen…',
    'messages.loadingContacts': 'Kontakte werden geladen…',
    'messages.photoLibrary': 'Fotomediathek',
    'messages.camera': 'Kamera',
    'messages.videoLibrary': 'Videomediathek',
    'messages.recordVideo': 'Video aufnehmen',
    'messages.document': 'Dokument',
    'messages.filterAll': 'Alle',
    'messages.filterDentists': 'Zahnärzte',
    'messages.filterLaboratories': 'Labore',
    'media.uploadItem': 'Element hochladen?',
    'media.deleteItem': 'Element löschen?',
    'media.uploadBody':
        'Dieses Element hochladen und im Patientendatensatz speichern?',
    'media.uploadConfirm': 'Hochladen',
    'media.deleteBody':
        'Möchten Sie dieses Element wirklich löschen? Dies kann nicht rückgängig gemacht werden.',
    'common.useThisDate': 'Dieses Datum verwenden',
    'common.selectDate': 'Datum auswählen',
    'common.prevMonth': 'Vorheriger Monat',
    'common.nextMonth': 'Nächster Monat',
    'common.minUppercase': 'Mindestens ein Großbuchstabe',
    'common.minNumber': 'Mindestens eine Zahl',
    'shade.manualOverride': 'Manuelle Korrektur — VITA Classical',
    'shade.allVita': 'Alle VITA Classical-Farben',
    'shade.targetShades': 'Zielfarben',
    'shade.toothSamples': 'Zahnproben',
    'shade.gumShades': 'Zahnfleischfarben',
    'shade.overrideTeeth': 'Zähne',
    'shade.overrideGum': 'Zahnfleisch',
    'auth.passwordUpdatedRelogin':
        'Passwort aktualisiert. Bitte erneut anmelden.',
    'dash.patientsOnFile': '{n} Patienten in der Akte',
    'dash.patientsOnFileOne': '1 Patient in der Akte',
    'dash.needsAttention': '{n} Fälle benötigen Aufmerksamkeit',
    'dash.needsAttentionOne': '1 Fall benötigt Aufmerksamkeit',
    'dash.unreadMessages': '{n} ungelesene Nachrichten',
    'dash.unreadMessagesOne': '1 ungelesene Nachricht',
    'dash.patientsAndCasesOnFile':
        '{patients} Patienten · {cases} Fälle in der Akte.',
    'dash.acrossCompleted': 'Über {n} abgeschlossene',
    'dash.inProgressInReview':
        '{inProgress} in Bearbeitung · {inReview} in Prüfung',
    'dash.activityCompleted':
        'Fall {label} als abgeschlossen markiert — {patient}',
    'dash.activityRejected':
        'Scan für {patient} abgelehnt — erneuter Scan erforderlich',
    'dash.activityInReview':
        'Fall für {patient} zur Laborprüfung weitergeleitet',
    'dash.activityInProgress': 'Fall für {patient} ist in Bearbeitung',
    'dash.activityPending': 'Fall für {patient} eröffnet — warte auf Scan',
    'dash.activityUpdated': 'Fall für {patient} aktualisiert',
    'common.justNow': 'Gerade eben',
    'common.minAgo': 'vor {n} Min.',
    'common.hourAgo': 'vor 1 Stunde',
    'common.hoursAgo': 'vor {n} Stunden',
    'common.daysAgo': 'vor {n} Tagen',
    'patients.shareTitle': '{patient} teilen',
    'patients.grantAccess': 'Zugriff gewähren',
    'patients.requestAccess': 'Zugriff anfordern',
    'patients.asOwnerHint':
        'Als Eigentümer erlaubt Ihre Einladung sofortigen Zugriff.',
    'patients.requestAccessHint':
        'Diese Anfrage wird an den Patienteneigentümer zur Freigabe gesendet.',
    'patients.allStaffHaveAccess':
        'Alle Praxismitarbeiter haben bereits Zugriff oder ausstehende Anfragen für diesen Patienten.',
    'patients.noEligibleStaff':
        'Keine berechtigten Mitarbeiter zum Einladen verfügbar.',
    'patients.accessGranted': 'Zugriff erfolgreich an Mitarbeiter gewährt.',
    'patients.accessRequestSubmitted':
        'Zugriffsanfrage an Patienteneigentümer zur Prüfung gesendet.',
    'patients.createdBy': 'Erstellt von',
    'patients.accessLabel': 'Zugriff',
    'patients.creator': 'Ersteller',
    'patients.shared': 'Geteilt',
    'patients.owner': 'Eigentümer',
    'patients.onlyOwnerApprove':
        'Nur der Patienteneigentümer kann Zugriffsanfragen genehmigen oder ablehnen.',
    'patients.onlyOwnerManage':
        'Nur der Patienteneigentümer kann vollständige Mitarbeiterzugriffe einsehen und verwalten.',
    'patients.waitingOwnerReview': 'Warte auf Prüfung durch Eigentümer',
    'camera.subtitle':
        'Frontal-, Links- und Rechtsfotos · bis zu 12 pro Patient',
    'camera.angle': 'Winkel',
    'camera.frontal': 'Frontal',
    'camera.left': 'Links',
    'camera.right': 'Rechts',
    'camera.frontalSmile': 'Frontales Lächeln',
    'camera.leftProfile': 'Linkes Profil',
    'camera.rightProfile': 'Rechtes Profil',
    'camera.clinicalPhoto': 'Klinisches Foto',
    'camera.emptyPhotosHint':
        'Machen Sie ein Frontal-, Links- oder Rechtsfoto — es wird im Patientendatensatz gespeichert.',
    'camera.noPatientsCaptureHint':
        'Noch keine Patienten — legen Sie einen an, um Fotos aufzunehmen.',
    'camera.addPatientCaptureHint':
        'Fügen Sie oben einen Patienten hinzu, um mit der Aufnahme zu beginnen.',
    'camera.switchAngleHint':
        'Winkel wechseln oder ein {angle}-Foto für diesen Patienten aufnehmen.',
    'shade.subtitle':
        'Zahnfoto hochladen → KI erkennt VITA-Farbe → bestätigen oder korrigieren',
    'shade.uploadCloseUp': 'Nahaufnahme von Zahn/Lächeln hochladen',
    'shade.uploadToothPhoto': 'Zahnfoto hochladen',
    'shade.analyzing': 'Farbe wird analysiert…',
    'shade.session': 'Sitzung',
    'shade.savedShadesHint': 'Gespeicherte Farben · tippen zum Bearbeiten',
    'shade.noSavesYet': 'Noch keine Speicherung',
    'shade.noDetectionYet': 'Noch keine Erkennung',
    'shade.uploadToAnalyze': 'Foto zum Analysieren hochladen',
    'shade.acceptAi': 'KI übernehmen',
    'shade.acceptShade': '{shade} übernehmen',
    'shade.saveOverride': 'Korrektur speichern',
    'shade.saveOverrideShade': 'Korrektur speichern ({shade})',
    'shade.result': 'Ergebnis',
    'shade.toothSelection': 'Zahnauswahl',
    'shade.override': 'Korrigieren',
    'shade.overrideSelected': 'Korrektur gewählt: {shade}',
    'shade.selected': 'Ausgewählt',
    'shade.uploadToothFirst':
        'Laden Sie zuerst ein Zahnfoto hoch, damit die KI eine Farbe erkennen kann.',
    'shade.gumShade': 'Zahnfleischfarbe',
    'shade.gumNotVita': 'Keine VITA-Zahnfarbe',
    'shade.noGumDetected': 'Kein Zahnfleisch erkannt',
    'smile.pageSubtitle':
        'Zahnform wählen · auf dem Patientenfoto platzieren · im Fall speichern',
    'smile.loadSmilePhoto': 'Patienten-Lächelnfoto laden',
    'smile.loadSmileHint':
        'Tippen Sie dann rechts in der Bibliothek auf eine Form und platzieren Sie sie über den Zähnen.',
    'smile.loadSmileHintPortrait':
        'Tippen Sie dann unten in der Bibliothek auf eine Form und platzieren Sie sie über den Zähnen.',
    'smile.placement': 'Platzierung',
    'smile.batemModels': 'Batem-Modelle',
    'smile.modelOpen': 'Offen',
    'smile.modelClosed': 'Geschlossen',
    'smile.useThisModel': 'Dieses Modell verwenden',
    'smile.upperJaw': 'Oberkiefer',
    'smile.lowerJaw': 'Unterkiefer',
    'patients.noNotes': 'Keine Notizen',
    'patients.noClinicalNotes': 'Noch keine klinischen Notizen.',
    'appointments.noNotes': 'Keine Notizen',
    'smile.nudge': 'Verschieben',
    'smile.resetPlacement': 'Platzierung zurücksetzen',
    'smile.centerShape': 'Form zentrieren',
    'smile.selectShapeHint':
        'Form aus der Bibliothek wählen → ziehen / zoomen / drehen',
    'smile.originalPhoto': 'Originalfoto',
    'notifications.markedAllRead':
        'Alle Benachrichtigungen als gelesen markiert',
    'notifications.now': 'jetzt',
    'notifications.minsShort': '{n}m',
    'notifications.hoursShort': '{n}h',
    'notifications.daysShort': '{n}d',
    'notifications.moreCount': '+{n} weitere',
    'notifications.msgAccessApproved':
        'Zugriff für {name} genehmigt. Sie können diesen Patienten öffnen.',
    'notifications.msgYouApprovedAccess':
        'Sie haben den Zugriff von {who} auf {name} genehmigt.',
    'notifications.msgAccessDeclined': 'Zugriff auf {name} wurde abgelehnt.',
    'notifications.msgYouDeclinedAccess':
        'Sie haben die Zugriffsanfrage von {who} für {name} abgelehnt.',
    'notifications.msgGrantedAccess':
        '{who} hat Ihnen Zugriff auf {name} gewährt.',
    'notifications.msgYouGrantedAccess':
        'Sie haben {who} Zugriff auf {name} gewährt.',
    'notifications.msgRequestedAccess':
        '{who} hat Zugriff auf {name} angefordert.',
    'notifications.msgYouRequestedAccess':
        'Sie haben Zugriff auf {name} angefordert.',
    'notifications.msgAccessRevoked': 'Ihr Zugriff auf {name} wurde entzogen.',
    'notifications.msgYouRevokedAccess':
        'Sie haben den Zugriff von {who} auf {name} entzogen.',
    'notifications.msgYouBookedAppt':
        'Sie haben einen Termin für {name} gebucht.',
    'notifications.msgBookedAppt': '{who} hat einen Termin für {name} gebucht.',
    'notifications.msgYouCancelledAppt':
        'Sie haben einen Termin für {name} storniert.',
    'notifications.msgCancelledAppt':
        '{who} hat einen Termin für {name} storniert.',
    'notifications.msgYouUpdatedAppt':
        'Sie haben einen Termin für {name} aktualisiert.',
    'notifications.msgUpdatedAppt':
        '{who} hat einen Termin für {name} aktualisiert.',
    'notifications.msgUploadedScan':
        '{who} hat einen 3D-Scan für {name} hochgeladen.',
    'notifications.msgSavedShade':
        '{who} hat ein Farbfoto für {name} gespeichert.',
    'notifications.msgSavedSmile':
        '{who} hat eine Lächeln-Vorschau für {name} gespeichert.',
    'notifications.msgAddedFile':
        '{who} hat eine Datei für {name} hinzugefügt.',
    'notifications.msgScanQuality': 'Scan-Qualitätsproblem bei {name}.',
    'notifications.msgScanQualityDetail':
        'Scan-Qualitätsproblem bei {name}. {detail}',
    'notifications.msgNewScan': 'Neuer Scan für {name} hochgeladen.',
    'notifications.msgNewPatient':
        'Neuer Patient erfasst: {name} (Scan ausstehend).',
    'notifications.fallbackScanQuality': 'Scan-Qualitätswarnung für {name}',
    'notifications.fallbackShade': 'Farb-Update für {name}',
    'notifications.fallbackAppointment': 'Termin-Update für {name}',
    'notifications.fallbackCase': 'Fall-Update für {name}',
    'notifications.fallbackScanBody': 'Scanbody-Update für {name}',
    'notifications.fallbackSync': 'Sync-Update für {name}',
    'notifications.fallbackExport': 'Export-Update für {name}',
    'patient.readyForDetect': 'Bereit zur Erkennung',
    'patient.noneYet': 'Noch keine',
    'patient.availableCount': '{n} verfügbar',
    'patient.caseId': 'Fall #{id}',
    'patient.fallbackId': 'Patient #{id}',
    'patient.emptyHint':
        'Noch keine Patienten — fügen Sie einen hinzu, um fortzufahren.',
    'scans.qualityNeedPatient':
        'Patient auswählen, dann Scan hochladen, um Qualitätsergebnisse zu sehen.',
    'scans.qualityNeedUpload':
        'Noch kein Scan hochgeladen — laden Sie eine PLY, STL oder OBJ hoch, um die Qualitätsprüfung zu starten.',
    'scans.simulatorPickTitle': 'Scan von diesem Mac wählen',
    'scans.simulatorPickHint':
        'Der iPad-Simulator kann den Mac-Ordner Downloads nicht öffnen. Kopieren Sie die PLY, STL oder OBJ nach dental-lab-ai/mobile/debug_scans und wählen Sie sie hier.',
    'scans.simulatorPickEmpty':
        'Keine Mesh-Dateien gefunden. Kopieren Sie eine PLY, STL oder OBJ nach mobile/debug_scans und versuchen Sie es erneut.',
    'scans.needMeshFile': 'Bitte eine PLY-, STL- oder OBJ-Datei wählen.',
    'scans.couldNotReadFile':
        'Datei konnte nicht gelesen werden. Bitte einen anderen Scan wählen.',
    'scans.uploadPreviewHint': 'PLY / STL / OBJ hochladen für die Vorschau',
    'scans.emptyHintUpload':
        'Noch keine Patienten — fügen Sie einen hinzu, um Scans hochzuladen.',
    'interpreter.subtitle':
        'Arzt ↔ Patient während der Behandlung. Ändert nicht die App-Sprache.',
    'interpreter.doctor': 'Arzt',
    'interpreter.patient': 'Patient',
    'interpreter.doctorLanguage': 'Arztsprache',
    'interpreter.patientLanguage': 'Patientensprache',
    'interpreter.doctorHint':
        'Halten zum Sprechen oder tippen. Die Patientenseite zeigt die Übersetzung.',
    'interpreter.patientHint':
        'Halten, damit der Patient spricht, oder tippen. Sie sehen es in Ihrer Sprache.',
    'interpreter.holdToTalk': 'Halten zum Sprechen',
    'interpreter.listening': 'Hört zu…',
    'interpreter.typeInstead': 'Sprache nicht verfügbar — bitte tippen',
    'interpreter.allowSpeech':
        'Bitte Spracheingabe und Mikrofon für Elite Dent erlauben, dann erneut Halten zum Sprechen tippen.',
    'interpreter.appleTranslateFailed':
        'Übersetzung fehlgeschlagen. Im Simulator ist Apple Übersetzen nicht verfügbar — die App nutzt den Server (Backend auf Port 8000 starten). Auf dem iPad: iPadOS 18+ und Sprachdownload erlauben.',
    'interpreter.typeHint': 'Satz eingeben…',
    'interpreter.send': 'Senden',
    'interpreter.speak': 'Vorlesen',
    'interpreter.swap': 'Sprachen tauschen',
    'interpreter.clear': 'Diesen Besuch löschen',
    'interpreter.history': 'Alles, was in diesem Besuch gesagt wurde',
    'interpreter.packTitle': '{lang} für die Übersetzung laden?',
    'interpreter.toneUnchecked':
        'Offline-Übersetzung — Höflichkeit nicht geprüft.',
    'interpreter.packBody':
        'Apple übersetzt auf diesem Gerät. Das Sprachpaket wird einmal geladen und funktioniert danach offline.',
    'interpreter.packDownload': 'Laden',
    'interpreter.packOnline': 'Stattdessen online',
    'interpreter.packFailed':
        'Das Sprachpaket wurde nicht geladen. Erneut versuchen oder Online-Übersetzung nutzen.',
    'interpreter.autoSpeak': 'Übersetzungen vorlesen',
    'interpreter.ttsFailed':
        'Sprache nicht abspielbar. iPad laut schalten (nicht lautlos) und Vorlesen tippen.',
    'interpreter.nothingHeard':
        'Nichts gehört. Taste halten und sprechen, oder tippen.',
    'interpreter.nothingHeardLang':
        'Nichts gehört auf {lang}. Taste halten und in dieser Sprache sprechen, oder tippen.',
    'interpreter.noVoice':
        'Dieses Gerät hat keine Stimme für diese Sprache. Die Übersetzung steht auf dem Bildschirm.',
    'interpreter.searchLanguage': 'Sprachen suchen',
    'interpreter.clinicLanguages': 'Praxissprachen',
    'interpreter.allLanguages': 'Alle Sprachen',
    'interpreter.patientOptional':
        'Optional — merkt sich die Sprache dieses Patienten',
    'p.onlyCreatorEdit': 'Nur die Person, die diese Patientenakte angelegt hat, kann sie bearbeiten.',
    'p.permDenied': 'Zugriff verweigert: Nur der Ersteller dieser Akte kann Patientendaten ändern.',
    'p.tryOtherStatus': 'Versuchen Sie einen anderen Status oder löschen Sie die Suche.',
    'p.addFirst': 'Fügen Sie den ersten Eintrag hinzu, um zu beginnen.',
    'p.accessApprovedLong': 'Zugriff genehmigt. Das Teammitglied kann jetzt auf diese Patientenakte zugreifen.',
    'p.accessRejectedDot': 'Zugriffsanfrage abgelehnt.',
    'p.noPending': 'Derzeit keine offenen Anfragen.',
    'p.allCaughtUp': 'Alles erledigt.',
    'p.target': 'Ziel: {n}',
    'p.requestedByColon': 'Angefragt von: {n}',
    'p.accessRevoked': 'Zugriff entzogen',
    'p.accessApproved': 'Zugriff genehmigt',
    'p.accessRejected': 'Zugriffsanfrage abgelehnt',
    'p.onlyAuthorDelete': 'Nur der Autor kann diese klinische Notiz löschen.',
    'p.noteDeleted': 'Notiz gelöscht',
    'p.tabInfo': 'Info',
    'p.tabAccess': 'Zugriff',
    'p.export': 'Exportieren',
    'p.exported': 'Patientendaten exportiert',
    'p.exporting': 'Export wird vorbereitet – bei Patienten mit vielen Scans kann das einen Moment dauern…',
    'p.emailRow': 'E-Mail',
    'p.phoneRow': 'Telefon',
    'p.noAccessInfo': 'Keine Zugriffsinformationen verfügbar.',
    'p.requestedBy': 'Angefragt von {n}',
    'p.staffMember': 'Teammitglied',
    'p.noneYet': 'Noch keine Patienten. Fügen Sie den ersten Eintrag hinzu.',
    'p.deleted': 'Patient endgültig gelöscht',
    'p.archived': 'Patient archiviert',
    'p.email': 'E-Mail',
    'p.phone': 'Telefon',
    'c.maxPhotos': 'Max. {n} Fotos pro Patient',
    'c.alignHint': '{a}-Führung für {p} ausrichten — Vorschau halten für Ober-/Unterkiefer',
    'c.savedPhoto': '{a}-Foto für {p} gespeichert',
    'c.deleting': 'Foto wird gelöscht…',
    'c.deleted': '{a}-Foto gelöscht',
    'c.renamePh': 'z. B. Oberes Lächeln',
    'c.renaming': 'Foto wird umbenannt…',
    'c.renamed': 'Umbenannt in {n}',
    'c.openShade': '„{n}“ wird mit der Farbbestimmung geöffnet…',
    'c.openSmile': '„{n}“ wird mit der Lächelvorschau geöffnet…',
    'c.closePhoto': 'Foto schließen',
    'c.takeHint': 'Machen Sie ein {a}-Foto oder wählen Sie eines aus dem Raster.',
    'c.nothingSel': 'Nichts ausgewählt',
    'c.photoUnavail': 'Foto nicht verfügbar',
    'c.refreshing': 'Wird aktualisiert…',
    'c.loadFail': 'Foto konnte nicht geladen werden',
    'c.crop': 'Foto zuschneiden',
    'c.usePhoto': 'Foto verwenden',
    'c.addTo': 'Zu {n} hinzufügen',
    'c.photoAdded': 'Foto hinzugefügt',
    'c.savedTo': 'In den Fotos von {n} gespeichert. Jetzt öffnen?',
    'c.later': 'Später',
    'c.incoming': 'Eingang',
    'c.noIncoming': 'Keine eingehenden Fotos. Senden Sie Fotos von einem PC über /scan-upload auf Ihrem Server.',
    'c.selPatFirst': 'Zuerst einen Patienten auswählen',
    's.assignTitle': 'Scan zuweisen',
    's.assignMsg': '„{f}“ zu {p} hinzufügen?',
    's.assign': 'Zuweisen',
    's.added': 'Scan zu {p} hinzugefügt',
    's.noPoints': 'Vorschau enthält keine Punkte',
    's.prevUnavail': 'Scan-Vorschau nicht verfügbar',
    's.readFail': 'Dateiinhalt konnte nicht gelesen werden',
    's.incomingName': 'Eingang: {n}',
    's.assignTo': 'Zu {p} zuweisen',
    's.loading': 'Scans werden geladen…',
    's.noIncoming': 'Keine eingehenden Scans. Senden Sie Scans von einem PC über /scan-upload auf Ihrem Server (Fotos erscheinen im Kamera-Tab).',
    'sh.noLip': 'In diesem Foto wurde keine Lippenkante gefunden — es wird nur die Mittellinie angezeigt. Fügen Sie Lippen unter „Kanten anpassen“ hinzu.',
    'sh.chooseShade': 'Wählen Sie zuerst eine Farbe und tippen Sie dann auf „Überschreiben“',
    'sh.chooseGum': 'Wählen Sie zuerst eine Zahnfleischfarbe und tippen Sie dann auf „Überschreiben“',
    'sh.gumShade': 'Zahnfleischfarbe → {s}',
    'sh.chooseGum5': 'Wählen Sie eine Zahnfleischfarbe (G1–G5) und tippen Sie dann auf „Überschreiben“',
    'sh.removed': 'Zahn entfernt — tippen Sie auf „Rückgängig“ oder erkennen Sie erneut.',
    'sh.removedN': 'Zahn entfernt. {n} übrig — tippen Sie auf „Rückgängig“ zum Wiederherstellen.',
    'sh.restored': 'Gelöschter Zahn wiederhergestellt.',
    'sh.uploadFirst': 'Laden Sie ein Foto hoch, bevor Sie einen Zahn hinzufügen.',
    'sh.addedTooth': 'Zahn hinzugefügt — halten Sie innerhalb der Kontur und ziehen Sie sie auf den Zahn, dann „Anwenden“.',
    'sh.dragHelp': 'Innen ziehen zum Verschieben · Ecken ziehen · Kantenmitte halten zum Krümmen · Mittellinie ziehen · Anwenden.',
    'sh.dragLip': 'Ziehen Sie die rosa Punkte auf die Kante, an der jede Lippe auf die Haut trifft.',
    'sh.lipRemoved': 'Lippenkontur entfernt.',
    'sh.photoRemoved': 'Foto entfernt',
    'sh.guidesUpdated': 'Mittellinie und Lippenführung aktualisiert.',
    'sh.updating': 'Farbe wird aus der bearbeiteten Kontur aktualisiert…',
    'sh.outlineApplied': 'Kontur angewendet — Zonenfarben für {t} aktualisiert.',
    'sh.selZone': 'Wählen Sie zuerst eine Zahnzone',
    'sh.photoNF': 'Foto für diesen Patienten nicht gefunden.',
    'sh.mapping': 'Zähne werden zugeordnet…',
    'sh.noTeeth': 'Keine Zähne erkannt — versuchen Sie ein anderes Foto',
    'sh.mapped': '{n} Zähne zugeordnet — übernehmen oder Überschreibung in der Sitzung speichern',
    'sh.selPat': 'Wählen Sie zuerst einen Patienten.',
    'sh.imgBytes': 'Bilddaten konnten nicht gelesen werden. Versuchen Sie ein anderes Foto.',
    'sh.addPatFirst': 'Legen Sie zuerst einen Patienten an und speichern Sie dann die Farbe in dessen Akte.',
    'sh.selFromList': 'Wählen Sie zuerst einen Patienten aus der Liste.',
    'sh.pickShade': 'Wählen Sie vor dem Speichern eine Farbe.',
    'sh.tapOverride': 'Tippen Sie zuerst auf „Überschreiben“ am Zonen-Chip, um {s} zu bestätigen.',
    'sh.savedOv': 'Überschreibung {s} gespeichert',
    'sh.accAi': 'KI-Vorschlag {s} übernommen',
    'sh.removedSess': '{s} aus der Sitzung entfernt',
    'sh.pointAdded': 'Punkt hinzugefügt — zum Verfeinern ziehen oder die neuen Kanten krümmen.',
    'sh.tooth': 'Zahn {n}',
    'sh.savedOvFor': 'Überschreibung {s} für {w} gespeichert',
    'sh.accAiFor': 'KI-Vorschlag {s} für {w} übernommen',
    'sh.pinchTap': 'Zum Zoomen zusammenziehen · nummerierten Kreis antippen',
    'sh.selFdi': 'FDI {n} ausgewählt · zum Zoomen zusammenziehen',
    'sh.uploadDetect': 'Laden Sie zuerst ein Lächeln hoch und erkennen Sie es — nur gefundene Zähne sind wählbar.',
    'sh.fdiND': 'FDI {n} (nicht erkannt)',
    'sh.editingTooth': '{t} wird bearbeitet',
    'sh.forZone': 'Für die ausgewählte Zone',
    'sh.forTooth': 'Für {t}',
    'sh.holdHelp': 'Innerhalb der Kontur halten und ziehen zum Verschieben · Ecken verformen · Kantenmitte krümmt · Anwenden.',
    'sh.pinchHelp': 'Zum Zoomen zusammenziehen · Zum Auswählen tippen · Für Foto-Aktionen gedrückt halten.',
    'sh.savedFinal': 'Endgültig gespeichert: {s}',
    'sh.edgeView': 'Kantenansicht',
    'sh.patient': 'Patient',
    'sh.notAnalysed': 'Noch nicht analysiert',
    'sh.override': 'Überschreiben',
    'sh.editingNow': 'Wird bearbeitet',
    'sh.hideTeeth': 'Ausblenden',
    'sh.conf': '{n} % Sicherheit',
    'sh.manual': 'Manuelle Auswahl',
    'sh.tapEdit': 'Zum Bearbeiten tippen',
    'sh.teeth': 'Zähne',
    'shape.Soft oval': 'Weich oval',
    'shape.Classic oval': 'Klassisch oval',
    'shape.Rounded': 'Rund',
    'shape.Natural oval': 'Natürlich oval',
    'shape.Youthful': 'Jugendlich',
    'shape.Soft square': 'Weich eckig',
    'shape.Balanced': 'Ausgewogen',
    'shape.Soft rect': 'Weich rechteckig',
    'shape.Hollywood': 'Hollywood',
    'shape.Strong square': 'Kräftig eckig',
    'shape.Tapered': 'Zulaufend',
    'shape.Canine lift': 'Eckzahn-Lift',
    'shape.Implant natural': 'Implantat natürlich',
    'shape.Implant classic': 'Implantat klassisch',
    'sh.rm': '{n} entfernt',
    'sh.sel': '{n} ausgewählt',
    'sh.restoredShape': '{n} wiederhergestellt',
    'sp.fromCam': 'Aus der Kamera geöffnet — wählen Sie eine Form aus der Bibliothek.',
    'sp.reopened': 'Gespeichertes Lächeln erneut geöffnet — anpassen und Änderungen speichern.',
    'sp.noFile': 'Dieses Foto hat keine Datei zum Öffnen.',
    'sp.bytes': 'Bilddaten konnten nicht gelesen werden.',
    'sp.loaded': 'Foto geladen — wählen Sie eine Form aus der Bibliothek.',
    'sp.selModel': 'Wählen Sie zuerst ein Modell',
    'sp.savedCase': '{s} in Fall #{c} gespeichert',
    'sp.saved': 'Lächelvorschau gespeichert ({s})',
    'sp.delQ': 'Gespeichertes Lächeln löschen?',
    'sp.delMsg': 'Dies entfernt es aus der Patientenakte.',
    'sp.deleted': 'Gespeichertes Lächeln gelöscht',
    'sp.savedN': 'Gespeicherte Lächeln ({n})',
    'sp.delTip': 'Gespeichertes Lächeln löschen',
    'sp.noPat': 'Noch keine Patienten — legen Sie einen an, um die Anprobe zu speichern.',
    'sp.saving': 'Wird gespeichert…',
    'sp.saveChanges': 'Änderungen speichern',
    'sp.exitFs': 'Vollbild beenden',
    'sp.compare': 'Gedrückt halten, um das Original zu vergleichen',
    'sp.hideOv': 'Überlagerung ausblenden',
    'sp.saveToCase': 'In Fall speichern',
    'sp.fs': 'Vollbild',
    'sp.showOv': 'Überlagerung einblenden',
    'p.emailReq': 'E-Mail-Adresse ist erforderlich',
    'p.emailInvalid': 'Geben Sie eine gültige E-Mail-Adresse ein',
    'p.stPending': 'Genehmigung ausstehend',
    'p.stActive': 'Zugriff aktiv',
    'p.stDenied': 'Abgelehnt',
    'p.emailLabel': 'E-Mail-Adresse *',
    'p.clear': 'Zurücksetzen',
    'p.saving': 'Wird gespeichert…',
    'p.identity': 'Identität',
    'p.required': 'Pflichtfeld',
    'ch.voice': 'Sprachnachricht',
    'ch.photo': 'Foto',
    'ch.video': 'Video',
    'ch.doc': 'Dokument',
    'ch.attach': 'Anhang',
    'ch.sendVoice': 'Sprachnachricht wird gesendet…',
    'ch.sendPhoto': 'Foto wird gesendet…',
    'ch.sendVideo': 'Video wird gesendet…',
    'ch.sendDoc': 'Dokument wird gesendet…',
    'ch.sending': 'Wird gesendet…',
    'ch.voiceShort': 'Sprache',
    'ch.noPreview': 'Vorschau nicht möglich',
    'ch.openDl': 'Öffnen / herunterladen',
    'ch.live': 'Live · {n} ungelesen',
    'ch.noMsgs': 'Noch keine Nachrichten',
    'ch.newMsg': 'Neue Nachricht',
    'ch.search': 'Suchen',
    'ch.noContacts': 'Keine Kontakte gefunden.',
    'ch.tag': 'Patient markieren',
    'ch.match': 'Patienten zu „{q}“',
    'p.noMatchP': 'Keine passenden Patienten',
    'ch.errImg': 'Das ausgewählte Bild konnte nicht gelesen werden.',
    'ch.errFile': 'Die ausgewählte Datei konnte nicht gelesen werden.',
    'ch.errVid': 'Das ausgewählte Video konnte nicht gelesen werden.',
    'ch.vidBig': 'Videos dürfen höchstens 200 MB groß sein.',
    'ch.mic': 'Für Sprachnachrichten wird der Mikrofonzugriff benötigt.',
    'ch.recFail': 'Aufnahme fehlgeschlagen — kein Ton aufgenommen.',
    'ch.holdLonger': 'Halten Sie etwas länger gedrückt, um eine Sprachnachricht aufzunehmen.',
    'ch.errAudio': 'Die Aufnahme konnte nicht gelesen werden.',
    'ch.recStart': 'Die Aufnahme konnte nicht gestartet werden.',
    'ch.sendVN': 'Die Sprachnachricht konnte nicht gesendet werden. Bitte erneut versuchen.',
    'ch.replying': 'Antwort auf',
    'ch.vidFail': 'Video konnte nicht geladen werden',
    'p.unnamed': 'Unbenannter Patient',
    'p.unknownPr': 'Unbekannter Behandler',
    'p.owner': 'Inhaber',
    'p.busy': 'Eine andere Patientenänderung läuft bereits',
    'lab.busy': 'Eine andere Laboraktion läuft bereits',
    'c.uploading': 'Wird hochgeladen…',
    'c.pleaseWait': 'Bitte warten…',
    'sb.restored': 'Gespeicherter Treffer für diesen Fall wiederhergestellt.',
    'sb.restoredN': '{m} wiederhergestellt · Zahn {t}',
    'sb.validMm': 'Geben Sie einen gültigen Durchmesser in mm ein',
    'sb.circlePx': 'Kreis in Pixeln gefunden — Durchmesser in mm (3–6) eingeben oder eine Tabellenzeile antippen.',
    'sb.circleDet': 'Kreis erkannt — Maßstab kalibrieren oder Durchmesser bestätigen.',
    'sb.matched': 'Aus Foto zugeordnet ({d} mm).',
    'sb.scaleOut': 'Maßstab {s} px/mm liegt außerhalb von 3–6 mm — anpassen oder kalibrieren.',
    'sb.measured': '{d} mm gemessen bei {s} px/mm.',
    'sb.enterMm': 'Geben Sie den bekannten Durchmesser in Millimetern (mm) ein',
    'sb.typical': 'Scanbody-Durchmesser liegen typischerweise bei 3–6 mm (nicht Meter). Bitte Wert prüfen.',
    'sb.detectFirst': 'Erkennen Sie zuerst einen Kreis aus einem Foto',
    'sb.fromTable': 'Aus Referenztabelle ausgewählt.',
    'sb.matchFirst': 'Ordnen Sie zuerst einen Durchmesser zu',
    'sb.saved': '{m} · Zahn {t} in Fall #{c} gespeichert',
    'sb.platMm': 'Plattform-Ø in Millimetern (mm) — typischerweise 3–6 mm, nicht Meter',
    'sb.provisional': 'Vorläufige Referenztabelle — vor dem Produktivbetrieb durch Herstellerdaten von Elite Dent ersetzen.',
    'sb.measurement': 'Messung',
    'sb.platDia': 'Plattformdurchmesser (mm)',
    'sb.outer': 'Äußere Breite der Scanbody-Plattform in Millimetern',
    'sb.detect': 'Aus Foto erkennen',
    'sb.newPhoto': 'Neues Foto',
    'sb.scaleCal': 'Maßstabskalibrierung',
    'sb.noScale': 'Das Foto hat noch keinen Maßstab — mm per Messschieber eingeben, Tabellenzeile antippen oder kalibrieren.',
    'sb.locked': 'Maßstab fixiert · bei Abweichung nachjustieren.',
    'sb.calib': 'Mit obigem Durchmesser kalibrieren',
    'sb.result': 'Ergebnis',
    'sb.ambig': 'Mehrdeutig — bestätigen',
    'sb.top': 'Beste Treffer',
    'sb.load': 'Scanbody-Foto laden',
    'sb.aiFinds': 'Die KI findet die kreisförmige Plattform; Sie geben mm (3–6) ein oder kalibrieren.',
    'sb.noCircle': 'Kein Kreis',
    'sb.refTable': 'Referenztabelle ({n})',
    'sb.noRows': 'Keine Referenzzeilen geladen',
    'sb.toothRow': 'Zahn {t} · {p}',
    'sb.selected': 'Ausgewählt',
    'sb.use': 'Verwenden',
    'lc.none': 'Keine Kamera gefunden. Verwenden Sie die System-Kamera oder die Fotomediathek.',
    'lc.perm': 'Kamerazugriff ist deaktiviert. Aktivieren Sie ihn in den Einstellungen und versuchen Sie es erneut.',
    'lc.restricted': 'Der Kamerazugriff ist auf diesem Gerät eingeschränkt.',
    'lc.start': 'Kamera konnte nicht gestartet werden.',
    'lc.holdPrev': 'Vorschau halten zum Ändern. Standard sind beide Kiefer.',
    'lc.empty': 'Die Kamera hat ein leeres Foto geliefert. Bitte erneut versuchen.',
    'lc.system': 'System-Kamera',
    'lc.processing': 'Foto wird verarbeitet…',
    'lc.both': 'Beide Kiefer',
    'lc.upper': 'Obere Zähne',
    'lc.lower': 'Untere Zähne',
    'ms.loading': '3D-Modell wird geladen…',
    'ms.solid': 'Einfarbig',
    'ms.colored': 'Farbig',
    'ms.rough': 'Problembereiche',
    's.qChecking': 'Scanqualität wird geprüft…',
    's.qGood': 'Keine Probleme gefunden – bereit für das Labor.',
    's.qError': 'Dieser Scan konnte nicht geprüft werden.',
    's.qIncoming': 'Die Qualität wird geprüft, sobald der Scan einem Patienten zugeordnet ist.',
    'sq.unknown.t': 'Scanproblem',
    'sq.point_cloud.d': 'Diese Datei enthält nur Punkte, keine Oberfläche, daher können Löcher und aufgefüllte Bereiche nicht geprüft werden. Für eine vollständige Prüfung exportieren Sie den Scan als STL oder als PLY mit Oberfläche.',
    'sq.point_cloud.t': 'Eingeschränkte Prüfung',
    'sq.bite_overlap.d': 'In Bissstellung überschneiden sich Ober- und Unterkieferscan (rot markiert), was bei echten Zähnen nicht möglich ist. Entweder ist der Bissscan falsch oder ein Kieferscan ist leicht verzogen. Wiederholen Sie den Bissscan; überschneiden sie sich weiterhin, scannen Sie den betroffenen Kiefer neu.',
    'sq.bite_overlap.t': 'Ober- und Unterkiefer passen nicht zusammen',
    'sq.double_layer.d': 'An einigen Stellen (rot markiert) erscheint die Oberfläche doppelt und leicht versetzt – zwei Scandurchgänge wurden verschoben zusammengefügt, oft weil sich der Patient bewegt hat. Löschen Sie den Bereich in der Scanner-Software und scannen Sie ihn neu.',
    'sq.double_layer.t': 'Doppelte Oberfläche',
    'sq.noisy_surface.d': 'Die gesamte Oberfläche wirkt körnig statt glatt. Häufige Ursachen sind eine verschmutzte oder beschlagene Scannerspitze oder zu viel Abstand zu den Zähnen. Reinigen Sie die Spitze und scannen Sie neu.',
    'sq.noisy_surface.t': 'Körniger Scan',
    'sq.rough_surface.d': 'Einige Stellen (rot markiert) wirken holprig, gestuft oder doppelt. Das entsteht meist durch Bewegung beim Scannen oder durch Speichel oder Blut auf den Zähnen. Trocknen Sie den Bereich und scannen Sie ihn langsam neu.',
    'sq.rough_surface.t': 'Raue oder unebene Stellen',
    'sq.patched_holes.d': 'Der Scanner hat einige Bereiche (rot markiert) nicht erfasst, und die Software hat sie mit einer geschätzten, glatten Fläche gefüllt. Die echte Form ist dort unbekannt, eine Versorgung passt deshalb eventuell nicht. Scannen Sie diese Bereiche erneut.',
    'sq.patched_holes.t': 'Lücken von der Software aufgefüllt',
    'sq.holes.d': 'Einige Bereiche (rot markiert) wurden nicht erfasst, das Labor kann die echte Form dort nicht sehen. Scannen Sie sie erneut – besonders wichtig, wenn ein Loch an einem präparierten Zahn oder dessen Rand liegt.',
    'sq.holes.t': 'Löcher im Scan',
    'sq.broken_mesh.d': 'Einige Dreiecke im Modell sind fehlerhaft. Labor-Software repariert das normalerweise automatisch – nur handeln, wenn das Labor ein Problem meldet.',
    'sq.broken_mesh.t': 'Kleine Dateifehler',
    'sq.loose_fragments.d': 'Neben den Zähnen schweben kleine Stücke (rot markiert) – meist versehentlich mitgescannte Zunge, Wange, ein Finger oder Speichel. Löschen Sie sie in der Scanner-Software oder scannen Sie neu, falls sie Zähne verdecken.',
    'sq.loose_fragments.t': 'Lose Stücke im Scan',
    'sq.split.d': 'Die Scanner-Software konnte Teile des Scans nicht zusammenfügen, dazwischen fehlt die Oberfläche. Scannen Sie den Bereich zwischen den Teilen (rot markiert) erneut, damit sie verbunden werden.',
    'sq.split.t': 'Scan besteht aus getrennten Teilen',
    'sq.low_resolution.d': 'Der Scan wurde mit reduzierter Auflösung exportiert, dadurch gehen feine Details wie Präparationsgrenzen verloren. Exportieren Sie ihn erneut in voller Auflösung.',
    'sq.low_resolution.t': 'Geringe Detailtiefe',
    'sq.flat_export.d': 'Das Modell hat keine Tiefe – beim Export ist etwas schiefgegangen. Exportieren Sie den Scan erneut aus der Scanner-Software.',
    'sq.flat_export.t': 'Scan ist flach',
    'sq.wrong_size.d': 'Das Modell ist viel zu klein oder zu groß für Zähne. Entweder wurde in der falschen Einheit exportiert (es muss Millimeter sein) oder es ist kein Zahnscan. Prüfen Sie die Exporteinstellungen und die Datei.',
    'sq.wrong_size.t': 'Falsche Größe',
    'sq.sparse.d': 'Die Datei enthält viel zu wenige Punkte, um Zähne abzubilden. Der Export ist vermutlich fehlgeschlagen – exportieren Sie den Scan erneut in voller Qualität.',
    'sq.sparse.t': 'Kaum Scandaten',
    'sq.truncated.d': 'Upload oder Export wurden vorzeitig abgebrochen, daher fehlt ein Teil des Scans. Laden Sie die Datei erneut hoch; passiert das wieder, exportieren Sie sie erneut aus der Scanner-Software.',
    'sq.truncated.t': 'Datei ist unvollständig',
    'sq.parse_fail.d': 'Die Datei ist beschädigt oder kein 3D-Scan. Exportieren Sie den Scan erneut aus der Scanner-Software als STL, PLY oder OBJ und laden Sie ihn noch einmal hoch.',
    'sq.parse_fail.t': 'Datei lässt sich nicht öffnen',
    'sq.r.bad': 'Neu scannen',
    'sq.r.review': 'Prüfen',
    'sq.r.good': 'Gut',
    'sq.sev.low': 'Hinweis',
    'sq.sev.medium': 'Bitte prüfen',
    'sq.sev.high': 'Neu scannen',
    's.qBad': 'Dieser Scan hat Probleme – bitte neu scannen, bevor der Patient geht.',
    's.qReview': 'Bitte prüfen Sie die folgenden Punkte, bevor Sie den Scan senden.',
    'dp.year': 'Geburtsjahr wählen',
    'dp.month': 'Geburtsmonat wählen · {y}',
    'dp.y': 'Jahr',
    'p.dentist': 'Zahnarzt',
    'au.reset': 'Falls ein Konto mit dieser E-Mail existiert, wurde ein Link zum Zurücksetzen des Passworts gesendet.',
    'dp.m': 'Monat',
    'dp.d': 'Tag',
    'lc.align': 'Zahn / Zahnbogen ausrichten, dann aufnehmen',
    'c.savingPhoto': 'Foto wird gespeichert…',
    'ch.opening': 'Unterhaltung wird geöffnet…',
    'c.unknown': 'Unbekannt',
    'c.user': 'Benutzer',
    's.scan': 'Scan',
    'z.cervical': 'Zervikal',
    'z.middle': 'Mitte',
    'z.incisal': 'Inzisal',
    'sh.oneTooth': '1 Zahn',
    'sh.nTeeth': '{n} Zähne',
    'sh.match': 'Übereinstimmung',
    'sh.selGum': '{s} ausgewählt — zum Anwenden bei Zahnfleischfarbe auf „Überschreiben“ tippen',
    'sh.chooseFor': '{t} — Farbe wählen, dann auf „Überschreiben“ tippen',
    'sh.selSave': '{s} ausgewählt — zum Anwenden auf „Überschreibung speichern“ tippen',
    'sh.selOn': '{s} ausgewählt — zum Anwenden bei {t} auf „Überschreiben“ tippen',
    'lc.holdChange': 'zum Ändern halten',
    'p.reqOne': '1 Anfrage wartet auf Ihre Entscheidung.',
    'p.reqN': '{n} Anfragen warten auf Ihre Entscheidung.',
    'ap.min': '{m} Min.',
    's.uploaded': '{f}-Scan hochgeladen',
    's.saveToCase': 'Zur Akte speichern',
    's.savedToCase': '{n} Scan(s) zur Akte gespeichert',
    's.alreadyOnCase': 'Alle Scans sind bereits in der Akte',
    's.onCase': 'In Akte',
    's.libraryOnly': 'Bibliothek',
    'sb.pxEnter': 'Ø {p} px (mm eingeben)',
    'sb.pxEnter2': '⌀ {p} px · mm eingeben',
    'ms.hudTris': 'Web · {n} Dreiecke · ziehen/zoomen',
    'ms.hudPts': 'Web · {n} Punkte · keine Flächen · ziehen/zoomen',
    'ms.gpuTris': 'iPad-GPU · {n} Eckpunkte · {t} Dreiecke',
    'ms.gpuNoFaces': 'iPad-GPU · {n} Punkte · keine Flächen',
    'ms.gpuPts': 'iPad-GPU · {n} Punkte',
    'img.read': 'Dieses Foto konnte nicht gelesen werden. Versuchen Sie ein anderes Bild.',
    'img.heic': 'Dieses Foto konnte nicht gelesen werden. Exportieren Sie es in „Fotos“ als JPEG und versuchen Sie es erneut.',
    'err.unexpected': 'Ein unerwarteter Fehler ist aufgetreten.',
    'err.network': 'Verbindungsproblem. Bitte prüfen Sie Ihre Internetverbindung und versuchen Sie es erneut.',
    'sh.dragBottomLip': 'Ziehen Sie die waagerechte Linie an der Unterlippe nach oben oder unten, um sie anzupassen.',
  };
}
