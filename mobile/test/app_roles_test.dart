import 'package:dental_lab_ai/core/auth/app_roles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRoles', () {
    test('isAdmin is true only for the admin role', () {
      expect(AppRoles.isAdmin('admin'), isTrue);
      expect(AppRoles.isAdmin('Admin'), isTrue);
      expect(AppRoles.isAdmin('dentist'), isFalse);
      expect(AppRoles.isAdmin('laboratory'), isFalse);
      expect(AppRoles.isAdmin(null), isFalse);
    });

    test('isDentist does not treat admin as a dentist', () {
      expect(AppRoles.isDentist('dentist'), isTrue);
      expect(AppRoles.isDentist('admin'), isFalse);
      expect(AppRoles.isDentist('laboratory'), isFalse);
    });

    test('isLaboratory matches laboratory and legacy aliases only', () {
      expect(AppRoles.isLaboratory('laboratory'), isTrue);
      expect(AppRoles.isLaboratory('lab'), isTrue);
      expect(AppRoles.isLaboratory('clinic'), isTrue);
      expect(AppRoles.isLaboratory('admin'), isFalse);
      expect(AppRoles.isLaboratory('dentist'), isFalse);
    });

    test('label uses Admin for the admin role', () {
      expect(AppRoles.label('admin'), 'Admin');
      expect(AppRoles.label('dentist'), 'Dentist');
      expect(AppRoles.label('laboratory'), 'Laboratory');
    });
  });
}
