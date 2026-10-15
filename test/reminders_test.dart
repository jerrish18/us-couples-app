import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/reminder_dates.dart';

void main() {
  test('February 29 anniversary falls on February 28 in a non-leap year', () {
    expect(
      nextAnnualDate(DateTime(2024, 2, 29), DateTime(2025, 2, 1)),
      DateTime(2025, 2, 28, 9),
    );
  });
  test('Passed anniversary advances to the next year', () {
    expect(
      nextAnnualDate(DateTime(2024, 5, 27), DateTime(2026, 6, 1)),
      DateTime(2027, 5, 27, 9),
    );
  });
  test(
    'Days-together count ignores time-of-day and daylight-saving hour length',
    () {
      expect(
        daysTogether(DateTime(2026, 3, 8, 23), DateTime(2026, 3, 9, 1)),
        1,
      );
    },
  );
  test(
    'Notification identifiers distinguish the one-day and one-hour reminder',
    () {
      expect(
        stableNotificationId('date:a:24'),
        isNot(stableNotificationId('date:a:1')),
      );
      expect(
        stableNotificationId('date:a:24'),
        stableNotificationId('date:a:24'),
      );
    },
  );
}
