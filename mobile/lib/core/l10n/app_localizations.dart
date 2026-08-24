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
  String patientsShownTotal(int shown, int total) => _t('patients.shownTotal')
      .replaceAll('{shown}', '$shown')
      .replaceAll('{total}', '$total');


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
  String get patientsLoadingAccessRequests => _t('patients.loadingAccessRequests');
  String get patientsEditNote => _t('patients.editNote');
  String get patientsDeleteNoteTitle => _t('patients.deleteNoteTitle');
  String get patientsDeleteNoteBody => _t('patients.deleteNoteBody');
  String get patientsNoteHint => _t('patients.noteHint');
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
  String get shadeUploadDetect => _t('shade.uploadDetect');
  String get shadeRemoveSave => _t('shade.removeSave');
  String shadeDeleteFromSession(String shade) => _t('shade.deleteFromSession').replaceAll('{shade}', shade);
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
  String cameraDeletePhotoBody(String angle, String name) =>
      _t('camera.deletePhotoBody').replaceAll('{angle}', angle).replaceAll('{name}', name);
  String get cameraRenamePhoto => _t('camera.renamePhoto');
  String get cameraChoosePatient => _t('camera.choosePatient');
  String get cameraChoosePatientBody => _t('camera.choosePatientBody');
  String get cameraNoPhotosYet => _t('camera.noPhotosYet');
  String cameraNoAnglePhotos(String angle) => _t('camera.noAnglePhotos').replaceAll('{angle}', angle);
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
  String get messagesLoadingConversations => _t('messages.loadingConversations');
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
  String dashPatientsAndCasesOnFile(int patients, int cases) =>
      _t('dash.patientsAndCasesOnFile')
          .replaceAll('{patients}', '$patients')
          .replaceAll('{cases}', '$cases');
  String dashAcrossCompleted(int n) =>
      _t('dash.acrossCompleted').replaceAll('{n}', '$n');
  String dashInProgressInReview(int inProgress, int inReview) =>
      _t('dash.inProgressInReview')
          .replaceAll('{inProgress}', '$inProgress')
          .replaceAll('{inReview}', '$inReview');
  String dashActivityCompleted(String label, String patient) =>
      _t('dash.activityCompleted')
          .replaceAll('{label}', label)
          .replaceAll('{patient}', patient);
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
  String commonDaysAgo(int n) =>
      _t('common.daysAgo').replaceAll('{n}', '$n');

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
  String get shadeOverride => _t('shade.override');
  String shadeOverrideSelected(String shade) =>
      _t('shade.overrideSelected').replaceAll('{shade}', shade);
  String get shadeSelected => _t('shade.selected');
  String get shadeUploadToothFirst => _t('shade.uploadToothFirst');

  // ── Smile leftovers ──────────────────────────────────────────────────────
  String get smilePageSubtitle => _t('smile.pageSubtitle');
  String get smileLoadSmilePhoto => _t('smile.loadSmilePhoto');
  String get smileLoadSmileHint => _t('smile.loadSmileHint');
  String get smileLoadSmileHintPortrait => _t('smile.loadSmileHintPortrait');
  String get smilePlacement => _t('smile.placement');
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

    m = RegExp(r"^Access approved for (.+)\. You can open this patient record\.$")
        .firstMatch(msg);
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
    m = RegExp(r"^You declined (.+)'s request to access (.+)\.$")
        .firstMatch(msg);
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
      return fill('notifications.msgBookedAppt', {
        'who': m[1]!,
        'name': m[2]!,
      });
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
      return fill('notifications.msgSavedShade', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^(.+) saved a smile preview for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgSavedSmile', {
        'who': m[1]!,
        'name': m[2]!,
      });
    }
    m = RegExp(r"^(.+) added a file for (.+)\.$").firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgAddedFile', {
        'who': m[1]!,
        'name': m[2]!,
      });
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
    m = RegExp(r"^New patient on file: (.+) \(awaiting scan\)\.$")
        .firstMatch(msg);
    if (m != null) {
      return fill('notifications.msgNewPatient', {'name': m[1]!});
    }

    // Non-EN: type + patient fallback when body is still English/unknown.
    final name = (patientName ?? '').trim();
    if (code != 'en' &&
        name.isNotEmpty &&
        type != null &&
        type.isNotEmpty) {
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
  String get scansUploadPreviewHint => _t('scans.uploadPreviewHint');
  String get scansEmptyHintUpload => _t('scans.emptyHintUpload');

  static const _en = <String, String>{
    'nav.dashboard': 'Dashboard',
    'nav.patients': 'Patients',
    'nav.newPatient': 'New Patient',
    'nav.appointments': 'Appointments',
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
        'Chairside scan validation, shade AI, and lab collaboration — designed for iPad.',    'auth.registerSubtitle':
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
        'This permanently removes your account and associated data. '
        'Type DELETE to continue.',
    'settings.deleteConfirmToken': 'DELETE',
    'settings.continue': 'Continue',
    'settings.confirmWithPassword': 'Confirm with password',
    'settings.enterPasswordToFinish':
        'Enter your account password to finish.',
    'settings.passwordRequired': 'Password is required.',
    'settings.deletingAccount': 'Deleting account…',
    'settings.loading': 'Loading settings…',
    'settings.accountFallback': 'Account',
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
    'scans.subtitle':
        'Upload PLY / STL / OBJ · preview Dots / Solid on device',
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
    'patients.deleteNoteBody': 'This clinical note will be permanently removed.',
    'patients.noteHint': 'Add a clinical note…',
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
    'camera.deletePhotoBody': 'Remove this {angle} photo from {name}\'s record.',
    'camera.renamePhoto': 'Rename photo',
    'camera.choosePatient': 'Choose a patient',
    'camera.choosePatientBody': 'Select a patient in the header to capture chairside photos.',
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
    'media.deleteBody': 'Are you sure you want to delete this item? This action cannot be undone.',
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
    'dash.inProgressInReview': '{inProgress} in progress · {inReview} in review',
    'dash.activityCompleted': 'Case {label} marked complete — {patient}',
    'dash.activityRejected':
        'Scan rejected for {patient} — rescan required',
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
    'camera.subtitle':
        'Frontal, left, and right photos · up to 12 per patient',
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
    'shade.override': 'Override',
    'shade.overrideSelected': 'Override selected: {shade}',
    'shade.selected': 'Selected',
    'shade.uploadToothFirst':
        'Upload a tooth photo first so AI can detect a shade.',
    'smile.pageSubtitle':
        'Pick a tooth shape · place it on the patient photo · save to case',
    'smile.loadSmilePhoto': 'Load a patient smile photo',
    'smile.loadSmileHint':
        'Then tap a shape in the library on the right and place it over the teeth.',
    'smile.loadSmileHintPortrait':
        'Then tap a shape in the library below and place it over the teeth.',
    'smile.placement': 'Placement',
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
    'notifications.msgYouUpdatedAppt':
        'You updated an appointment for {name}.',
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
    'scans.uploadPreviewHint': 'Upload a PLY / STL / OBJ to preview',
    'scans.emptyHintUpload': 'No patients yet — add one to upload scans.',
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
    'settings.deleteAccount': 'Konto löschen',
    'settings.deleteAccountBody':
        'Dadurch werden Ihr Konto und zugehörige Daten dauerhaft entfernt. '
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
    'appointments.statusScheduled': 'Geplant',
    'appointments.statusCompleted': 'Abgeschlossen',
    'appointments.statusCancelled': 'Abgesagt',
    'appointments.statusNoShow': 'Nicht erschienen',
    'messages.subtitle': 'Posteingang und Gespräche mit dem Labor',
    'messages.placeholder': 'Nachricht',
    'messages.newChat': 'Neuer Chat',
    'messages.startChat': 'Chat starten',
    'messages.empty': 'Noch keine Nachrichten — schreiben Sie hallo.',
    'messages.selectConversation':
        'Wählen Sie eine Unterhaltung zum Schreiben',
    'messages.attach': 'Anhängen',
    'messages.active': 'Aktiv',
    'messages.reconnecting': 'Verbinde erneut…',
    'messages.noConversations': 'Noch keine Unterhaltungen.',
    'messages.noMatch': 'Keine Unterhaltungen passen zur Suche.',
    'messages.newTitle': 'Neue Nachricht',
    'scans.subtitle':
        'PLY / STL / OBJ hochladen · Vorschau Punkte / Solid auf dem Gerät',
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
    'camera.deletePhotoBody': 'Dieses {angle}-Foto aus dem Datensatz von {name} entfernen.',
    'camera.renamePhoto': 'Foto umbenennen',
    'camera.choosePatient': 'Patient auswählen',
    'camera.choosePatientBody': 'Wählen Sie oben einen Patienten, um Stuhlseitenfotos aufzunehmen.',
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
    'media.uploadBody': 'Dieses Element hochladen und im Patientendatensatz speichern?',
    'media.uploadConfirm': 'Hochladen',
    'media.deleteBody': 'Möchten Sie dieses Element wirklich löschen? Dies kann nicht rückgängig gemacht werden.',
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
    'auth.passwordUpdatedRelogin': 'Passwort aktualisiert. Bitte erneut anmelden.',
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
    'dash.activityPending':
        'Fall für {patient} eröffnet — warte auf Scan',
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
    'shade.override': 'Korrigieren',
    'shade.overrideSelected': 'Korrektur gewählt: {shade}',
    'shade.selected': 'Ausgewählt',
    'shade.uploadToothFirst':
        'Laden Sie zuerst ein Zahnfoto hoch, damit die KI eine Farbe erkennen kann.',
    'smile.pageSubtitle':
        'Zahnform wählen · auf dem Patientenfoto platzieren · im Fall speichern',
    'smile.loadSmilePhoto': 'Patienten-Lächelnfoto laden',
    'smile.loadSmileHint':
        'Tippen Sie dann rechts in der Bibliothek auf eine Form und platzieren Sie sie über den Zähnen.',
    'smile.loadSmileHintPortrait':
        'Tippen Sie dann unten in der Bibliothek auf eine Form und platzieren Sie sie über den Zähnen.',
    'smile.placement': 'Platzierung',
    'smile.nudge': 'Verschieben',
    'smile.resetPlacement': 'Platzierung zurücksetzen',
    'smile.centerShape': 'Form zentrieren',
    'smile.selectShapeHint':
        'Form aus der Bibliothek wählen → ziehen / zoomen / drehen',
    'smile.originalPhoto': 'Originalfoto',
    'notifications.markedAllRead': 'Alle Benachrichtigungen als gelesen markiert',
    'notifications.now': 'jetzt',
    'notifications.minsShort': '{n}m',
    'notifications.hoursShort': '{n}h',
    'notifications.daysShort': '{n}d',
    'notifications.moreCount': '+{n} weitere',
    'notifications.msgAccessApproved':
        'Zugriff für {name} genehmigt. Sie können diesen Patienten öffnen.',
    'notifications.msgYouApprovedAccess':
        'Sie haben den Zugriff von {who} auf {name} genehmigt.',
    'notifications.msgAccessDeclined':
        'Zugriff auf {name} wurde abgelehnt.',
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
    'notifications.msgAccessRevoked':
        'Ihr Zugriff auf {name} wurde entzogen.',
    'notifications.msgYouRevokedAccess':
        'Sie haben den Zugriff von {who} auf {name} entzogen.',
    'notifications.msgYouBookedAppt':
        'Sie haben einen Termin für {name} gebucht.',
    'notifications.msgBookedAppt':
        '{who} hat einen Termin für {name} gebucht.',
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
    'scans.uploadPreviewHint':
        'PLY / STL / OBJ hochladen für die Vorschau',
    'scans.emptyHintUpload':
        'Noch keine Patienten — fügen Sie einen hinzu, um Scans hochzuladen.',
  };
}
