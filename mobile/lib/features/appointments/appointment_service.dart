import '../../core/api/api_client.dart';
import 'models/appointment.dart';

/// Backend integration for `/api/appointments`.
class AppointmentService {
  AppointmentService(this.api);

  final ApiClient api;

  Future<List<Appointment>> list({
    String? status,
    String? patientId,
    bool upcomingOnly = true,
  }) {
    return api.listAppointments(
      status: status,
      patientId: patientId,
      upcomingOnly: upcomingOnly,
    );
  }

  Future<Appointment> create({
    required String patientId,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
  }) {
    return api.createAppointment(
      patientId: patientId,
      startTime: startTime,
      endTime: endTime,
      description: description,
    );
  }

  Future<Appointment> update({
    required String appointmentId,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    String? status,
  }) {
    return api.updateAppointment(
      appointmentId: appointmentId,
      description: description,
      startTime: startTime,
      endTime: endTime,
      status: status,
    );
  }

  Future<void> delete(String appointmentId) {
    return api.deleteAppointment(appointmentId);
  }
}
