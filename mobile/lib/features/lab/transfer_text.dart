import '../../core/l10n/app_localizations.dart';

/// One plain sentence describing a lab transfer from our lab's side,
/// instead of "Lab A → Lab B". [ourLabId] is the signed-in lab.
String transferSentence(AppLocalizations loc, Map<String, dynamic> t, String ourLabId) {
  String name(Object? l) => l is Map ? '${l['name'] ?? '—'}' : '—';
  final from = t['from_lab'], to = t['to_lab'];
  final outgoing = from is Map && '${from['id']}' == ourLabId;
  final handover = t['kind'] == 'handover';
  final p = {
    'p': '${t['patient_name'] ?? '—'}',
    'dentist': '${t['requested_by_name'] ?? t['dentist_name'] ?? '—'}',
    'from': name(from),
    'to': name(to),
    'for': '${t['dentist_name'] ?? ''}',
  };
  final key = switch ('${t['status']}') {
    // Our dentist asked; we forward (or not).
    'awaiting_sender' => outgoing ? 'lab.tx.ourDentistAsks' : 'lab.tx.theirDentistAsks',
    'awaiting_recipient' => outgoing
        ? 'lab.tx.waitingForThem'
        : (handover ? 'lab.tx.handoverToUs' : 'lab.tx.shareWithUs'),
    'accepted' => outgoing
        ? (p['for']!.isEmpty ? 'lab.tx.theyAccepted' : 'lab.tx.theyAcceptedFor')
        : (p['for']!.isEmpty ? 'lab.tx.weAccepted' : 'lab.tx.weAcceptedFor'),
    'rejected' => 'lab.tx.declined',
    _ => 'lab.tx.cancelled',
  };
  return loc.trp(key, p);
}
