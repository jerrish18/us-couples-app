import 'package:flutter_test/flutter_test.dart';
import 'package:us/features/cycle/cycle_prediction.dart';
import 'package:us/features/expenses/expense_groups.dart';
import 'package:us/features/calls/call_service.dart';
import 'package:us/core/theme.dart';
import 'package:flutter/material.dart';

void main() {
  test('legacy expenses group by recorded date; outings and categories stay independent', () {
    final rows = <Map<String, dynamic>>[
      {
        'title': 'Lunch',
        'amount': 450.50,
        'spent_on': '2026-10-19',
        'category': 'Food',
        'outing': 'Beach date',
      },
      {
        'title': 'Taxi',
        'amount': 200.25,
        'spent_on': '2026-10-19',
        'category': 'Travel',
        'outing': 'Beach date',
      },
      {'title': 'Gift', 'amount': 100, 'created_at': '2026-10-18T12:00:00Z'},
    ];
    expect(groupExpenses(rows, ExpenseGrouping.date)['2026-10-19']!.length, 2);
    expect(
      groupExpenses(
        rows,
        ExpenseGrouping.outing,
      )['Beach date']!.fold<int>(0, (n, r) => n + expensePaise(r)),
      65075,
    );
    expect(
      groupExpenses(rows, ExpenseGrouping.category)['Other']!.single['title'],
      'Gift',
    );
    expect(groupExpenses(rows, ExpenseGrouping.date, query: 'beach').length, 1);
    expect(expenseDate(rows.last), '2026-10-18');
  });
  test('cycle estimates use deduplicated calendar dates and recent observed intervals', () {
    final estimate = estimateCycle([
      DateTime(2026, 8, 1),
      DateTime(2026, 8, 29),
      DateTime(2026, 9, 28),
      DateTime(2026, 9, 28, 18),
    ]);
    expect(estimate!.length, 29);
    expect(estimate.samples, 2);
    expect(estimate.nextStart, DateTime.utc(2026, 10, 27));
    expect(estimateCycle([]), isNull);
    expect(
      estimateCycle([DateTime(2026, 10, 1)], fallback: 31)!.nextStart,
      DateTime.utc(2026, 11, 1),
    );
    expect(
      cycleContains(
        DateTime(2026, 10, 4, 23),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 4),
      ),
      isTrue,
    );
    expect(
      cycleContains(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 4),
      ),
      isFalse,
    );
  });
  test('ended and expired calls cannot reopen incoming call UI', () {
    final now = DateTime.utc(2026, 10, 20);
    expect(
      liveCall({
        'state': 'ringing',
        'expires_at': now.add(const Duration(seconds: 60)).toIso8601String(),
      }, now),
      isTrue,
    );
    for (final state in terminalCallStates) {
      expect(
        liveCall({
          'state': state,
          'expires_at': now.add(const Duration(seconds: 60)).toIso8601String(),
        }, now),
        isFalse,
      );
    }
    expect(
      liveCall({
        'state': 'ringing',
        'expires_at': now
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      }, now),
      isFalse,
    );
  });
  test('dark surface text and accent pairs retain readable contrast', () {
    final colors = usTheme(Brightness.dark).colorScheme;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    expect(contrast(colors.onSurface, colors.surface), greaterThan(7));
    expect(
      contrast(colors.onSurfaceVariant, colors.surfaceContainerLow),
      greaterThan(4.5),
    );
    for (final accent in Accent.values) {
      expect(
        contrast(
          UsColors.foreground(accent, true),
          UsColors.tint(accent, true),
        ),
        greaterThan(4.5),
      );
    }
  });
}
