import 'locale_controller.dart';

// The backend stores/returns English sentences (notifications, HTTP `detail`).
// ponytail: client-side pattern map; move to message codes + params if the
// backend ever gets a second language.
final _patterns = <(RegExp, String)>[
  (RegExp(r'^(.+) uploaded a 3D scan for (.+)\.$'), r'$1 hat einen 3D-Scan für $2 hochgeladen.'),
  (RegExp(r'^(.+) saved a shade photo for (.+)\.$'), r'$1 hat ein Farbfoto für $2 gespeichert.'),
  (RegExp(r'^(.+) saved a smile preview for (.+)\.$'), r'$1 hat eine Smile-Vorschau für $2 gespeichert.'),
  (RegExp(r'^(.+) added a file for (.+)\.$'), r'$1 hat eine Datei für $2 hinzugefügt.'),
  (RegExp(r'^(.+) asked to join your lab\.$'), r'$1 möchte Ihrem Labor beitreten.'),
  (RegExp(r'^(.+) asked to transfer to (.+)\.$'), r'$1 möchte zu $2 wechseln.'),
  (RegExp(r'^(.+) joined your lab \(transferred\)\.$'), r'$1 ist Ihrem Labor beigetreten (Wechsel).'),
  (RegExp(r'^Your transfer to (.+) was approved\.$'), r'Ihr Wechsel zu $1 wurde genehmigt.'),
  (RegExp(r'^(.+) accepted you\.$'), r'$1 hat Sie aufgenommen.'),
  (RegExp(r'^(.+) declined your request\. You can ask again\.$'), r'$1 hat Ihre Anfrage abgelehnt. Sie können erneut anfragen.'),
  (RegExp(r'^Your lab transfer request was declined\.$'), r'Ihre Anfrage zum Laborwechsel wurde abgelehnt.'),
  (RegExp(r'^A lab asked to remove (.+)\.$'), r'Ein Labor möchte $1 entfernen.'),
  (RegExp(r'^Access approved for (.+)\. You can open this patient record\.$'), r'Zugriff für $1 genehmigt. Sie können diese Patientenakte öffnen.'),
  (RegExp(r"^You approved (.+)'s access to (.+)\.$"), r'Sie haben den Zugriff von $1 auf $2 genehmigt.'),
  (RegExp(r'^Access to (.+) was declined\.$'), r'Der Zugriff auf $1 wurde abgelehnt.'),
  (RegExp(r"^You declined (.+)'s request to access (.+)\.$"), r'Sie haben die Zugriffsanfrage von $1 auf $2 abgelehnt.'),
  (RegExp(r'^(.+) was created and assigned to you\.$'), r'$1 wurde angelegt und Ihnen zugewiesen.'),
  (RegExp(r'^(.+) granted you access to (.+)\.$'), r'$1 hat Ihnen Zugriff auf $2 gewährt.'),
  (RegExp(r'^You granted (.+) access to (.+)\.$'), r'Sie haben $1 Zugriff auf $2 gewährt.'),
  (RegExp(r'^(.+) asked to share (.+) with (.+)\.$'), r'$1 möchte $2 mit $3 teilen.'),
  (RegExp(r'^Your lab will review sharing (.+) with (.+)\.$'), r'Ihr Labor prüft das Teilen von $1 mit $2.'),
  (RegExp(r'^Your access to (.+) was revoked\.$'), r'Ihr Zugriff auf $1 wurde entzogen.'),
  (RegExp(r"^You revoked (.+)'s access to (.+)\.$"), r'Sie haben den Zugriff von $1 auf $2 entzogen.'),
  (RegExp(r'^(.+) was assigned to you\.$'), r'$1 wurde Ihnen zugewiesen.'),
  (RegExp(r'^(.+) was moved to another dentist\.$'), r'$1 wurde einem anderen Zahnarzt zugewiesen.'),
  (RegExp(r'^Transfer request for (.+)\.$'), r'Übertragungsanfrage für $1.'),
  (RegExp(r'^(.+) was shared with you\.$'), r'$1 wurde mit Ihnen geteilt.'),
  (RegExp(r'^Transfer of (.+) was approved\.$'), r'Übertragung von $1 wurde genehmigt.'),
  (RegExp(r'^Transfer of (.+) was (rejected|declined)\.$'), r'Übertragung von $1 wurde abgelehnt.'),
  (RegExp(r'^Transfer of (.+) was cancelled\.$'), r'Übertragung von $1 wurde abgebrochen.'),
  (RegExp(r'^Transfer of (.+) was pending\.$'), r'Übertragung von $1 ist noch offen.'),
  (RegExp(r'^Access request is not pending \(current status: approved\)\.$'),
      r'Diese Freigabeanfrage ist nicht mehr offen (bereits genehmigt).'),
  (RegExp(r'^Access request is not pending \(current status: rejected\)\.$'),
      r'Diese Freigabeanfrage ist nicht mehr offen (bereits abgelehnt).'),
  (RegExp(r'^Access request is not pending \(current status: (.+)\)\.$'),
      r'Diese Freigabeanfrage ist nicht mehr offen (Status: $1).'),
  (RegExp(r'^(.+) added a note for (.+)\.$'), r'$1 hat eine Notiz für $2 hinzugefügt.'),
  (RegExp(r'^You added a note for (.+)\.$'), r'Sie haben eine Notiz für $1 hinzugefügt.'),
  (RegExp(r'^(.+) set the appointment for (.+) to (.+)\.$'),
      r'$1 hat den Termin für $2 auf „$3“ gesetzt.'),
  (RegExp(r'^You set the appointment for (.+) to (.+)\.$'),
      r'Sie haben den Termin für $1 auf „$2“ gesetzt.'),
  (RegExp(r'^(.+) was submitted for review\.$'), r'$1 wurde zur Prüfung eingereicht.'),
  (RegExp(r'^(.+) was updated by the dentist\.$'), r'$1 wurde vom Zahnarzt aktualisiert.'),
  (RegExp(r'^(.+) was reopened by the dentist\.$'), r'$1 wurde vom Zahnarzt wieder geöffnet.'),
  (RegExp(r'^The lab approved (.+)\.$'), r'Das Labor hat $1 freigegeben.'),
  (RegExp(r'^The lab rejected (.+?): (.*)$', dotAll: true), r'Das Labor hat $1 abgelehnt: $2'),
  (RegExp(r'^An administrator set (.+?) to (awaiting scan|in progress|under review|completed|rejected): (.*)$', dotAll: true),
      r'Ein Administrator hat $1 auf „$2“ gesetzt: $3'),
  (RegExp(r'^(.+) booked an appointment for (.+)\.$'), r'$1 hat einen Termin für $2 gebucht.'),
  (RegExp(r'^You booked an appointment for (.+)\.$'), r'Sie haben einen Termin für $1 gebucht.'),
  (RegExp(r'^(.+) cancelled an appointment for (.+)\.$'), r'$1 hat einen Termin für $2 abgesagt.'),
  (RegExp(r'^You cancelled an appointment for (.+)\.$'), r'Sie haben einen Termin für $1 abgesagt.'),
  (RegExp(r'^(.+) updated an appointment for (.+)\.$'), r'$1 hat einen Termin für $2 geändert.'),
  (RegExp(r'^You updated an appointment for (.+)\.$'), r'Sie haben einen Termin für $1 geändert.'),
  (RegExp(r'^Max (\d+) photos per patient$'), r'Maximal $1 Fotos pro Patient'),
];

const _exact = <String, String>{
  'Unknown Practitioner': 'Unbekannter Behandler',
  'A colleague': 'Ein Kollege',
  'Signed out': 'Abgemeldet',
  'Password updated': 'Passwort aktualisiert',
  'Account deleted': 'Konto gelöscht',
  'Your account has been permanently deleted.': 'Ihr Konto wurde endgültig gelöscht.',
  'Account created successfully. An administrator must verify your account before you can sign in.':
      'Konto erfolgreich erstellt. Ein Administrator muss Ihr Konto freigeben, bevor Sie sich anmelden können.',
  'If an account exists for that email, a password reset link has been sent.':
      'Falls ein Konto mit dieser E-Mail existiert, wurde ein Link zum Zurücksetzen des Passworts gesendet.',
  'Password is incorrect': 'Das Passwort ist falsch.',
  'Current password is incorrect': 'Das aktuelle Passwort ist falsch.',
  'New password must be different from the current password':
      'Das neue Passwort muss sich vom aktuellen unterscheiden.',
  'Invalid or expired refresh token': 'Ihre Sitzung ist abgelaufen. Bitte melden Sie sich erneut an.',
  'Your session expired. Please sign in again.': 'Ihre Sitzung ist abgelaufen. Bitte melden Sie sich erneut an.',
  'An account with this email address already exists.': 'Ein Konto mit dieser E-Mail-Adresse existiert bereits.',
  'Signup failed': 'Registrierung fehlgeschlagen.',
  'Name is required': 'Name ist erforderlich.',
  'Patient not found': 'Patient nicht gefunden.',
  'Appointment not found': 'Termin nicht gefunden.',
  'Overlapping active appointment exists for this time window':
      'In diesem Zeitfenster existiert bereits ein aktiver Termin.',
  'end_time must be after start_time': 'Das Ende muss nach dem Beginn liegen.',
  'Invalid start_time or end_time': 'Ungültige Start- oder Endzeit.',
  'assign_to must be an active dentist': 'Bitte wählen Sie einen aktiven Zahnarzt.',
  'You do not have access to this patient': 'Sie haben keinen Zugriff auf diesen Patienten.',
  'Patient email is required': 'Die E-Mail-Adresse des Patienten ist erforderlich.',
  'Patient email is required before scheduling an appointment':
      'Vor der Terminplanung ist die E-Mail-Adresse des Patienten erforderlich.',
  'Patient email is required for appointment responses':
      'Für Terminantworten ist die E-Mail-Adresse des Patienten erforderlich.',
  'Labs must assign a dentist (assign_to) when booking': 'Labore müssen beim Buchen einen Zahnarzt zuweisen.',
  'Can only assign a dentist in your lab': 'Sie können nur Zahnärzte Ihres Labors zuweisen.',
  'No fields to update': 'Keine Änderungen vorhanden.',
  'Conversation not found': 'Unterhaltung nicht gefunden.',
  'Target user not found': 'Benutzer nicht gefunden.',
  'Cannot start a conversation with yourself': 'Sie können keine Unterhaltung mit sich selbst beginnen.',
  'Failed to create conversation': 'Unterhaltung konnte nicht erstellt werden.',
  'Failed to save message': 'Nachricht konnte nicht gespeichert werden.',
  'Photo not found': 'Foto nicht gefunden.',
  'Photo file not found': 'Fotodatei nicht gefunden.',
  'File not found': 'Datei nicht gefunden.',
  'Record not found': 'Eintrag nicht gefunden.',
  'Shade detection not found': 'Farbbestimmung nicht gefunden.',
  'Notification not found': 'Benachrichtigung nicht gefunden.',
  'Empty file': 'Die Datei ist leer.',
  'Empty photo file': 'Die Fotodatei ist leer.',
  'File is not a video': 'Die Datei ist kein Video.',
  'Filename is required': 'Ein Dateiname ist erforderlich.',
  'Image must be .jpg, .jpeg, .png, .webp, .heic, .tif, or .tiff':
      'Das Bild muss .jpg, .jpeg, .png, .webp, .heic, .tif oder .tiff sein.',
  'Scan file must be .ply, .stl, or .obj': 'Die Scan-Datei muss .ply, .stl oder .obj sein.',
  'Video must be mp4, mov, m4v, webm, avi, mkv, 3gp, or mpeg':
      'Das Video muss mp4, mov, m4v, webm, avi, mkv, 3gp oder mpeg sein.',
  'You need a dentist or laboratory account to continue.':
      'Für diese Funktion benötigen Sie ein Zahnarzt- oder Laborkonto.',
  'This action is only available to dentists.': 'Diese Aktion steht nur Zahnärzten zur Verfügung.',
  'Only an administrator can do this.': 'Das darf nur ein Administrator.',
  'Access request not found': 'Zugriffsanfrage nicht gefunden.',
  'Cannot grant access to yourself': 'Sie können sich selbst keinen Zugriff gewähren.',
  'Target user is already the patient owner': 'Dieser Benutzer ist bereits Besitzer der Patientenakte.',
  'Target user already has access or a pending request':
      'Dieser Benutzer hat bereits Zugriff oder eine offene Anfrage.',
  "Permission Denied: only the dentist's lab can approve or reject this request.":
      'Nur das Labor des Zahnarztes kann diese Anfrage genehmigen oder ablehnen.',
};

/// English tokens the API embeds inside otherwise-translated sentences.
const _embeddedEn = <String, String>{
  'awaiting scan': 'Wartet auf Scan',
  'in progress': 'In Bearbeitung',
  'under review': 'In Prüfung',
  'needs work': 'Nacharbeit nötig',
  'no_show': 'Nicht erschienen',
  'scheduled': 'Geplant',
  'completed': 'Abgeschlossen',
  'cancelled': 'Abgesagt',
  'canceled': 'Abgesagt',
  'rejected': 'Abgelehnt',
  'approved': 'Genehmigt',
  'pending': 'Ausstehend',
};

/// Swap known English status tokens inside an otherwise-localized sentence.
String localizeEmbeddedServerTokens(String text) {
  if (LocaleController.current != 'de') return text;
  var out = text;
  // Longer phrases first so "awaiting scan" wins over bare words.
  final keys = _embeddedEn.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final en in keys) {
    out = out.replaceAllMapped(
      RegExp('\\b${RegExp.escape(en)}\\b', caseSensitive: false),
      (_) => _embeddedEn[en]!,
    );
  }
  return out;
}

/// German text for known backend sentences; unknown text and EN pass through.
///
/// Used by error dialogs / HTTP `detail`. Notification inbox prefers
/// [AppLocalizations.localizeNotificationMessage] (match English first).
String localizeServerText(String text) {
  if (LocaleController.current != 'de') return text;
  final t = text.trim();
  final hit = _exact[t];
  if (hit != null) return localizeEmbeddedServerTokens(hit);
  for (final (re, de) in _patterns) {
    final m = re.firstMatch(t);
    if (m == null) continue;
    final out = de.replaceAllMapped(
      RegExp(r'\$(\d)'),
      (g) => m.group(int.parse(g.group(1)!)) ?? '',
    );
    return localizeEmbeddedServerTokens(out);
  }
  return text;
}
