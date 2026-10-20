import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/design.dart';
import 'package:us/core/space.dart';
import 'package:us/core/session.dart';
import 'package:us/features/expenses/expenses_screen.dart';
import 'package:us/features/cycle/cycle_screen.dart';

import 'ui_review_test.dart' as fixtures;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'expense and cycle forms fit narrow ${brightness.name} screens with keyboard and large text',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final editor in <Widget>[
          const ExpenseEditor(),
          const CycleEditor(),
        ]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: usTheme(brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(320, 700),
                  textScaler: TextScaler.linear(1.5),
                  viewInsets: EdgeInsets.only(bottom: 250),
                ),
                child: Scaffold(body: editor),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -900),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );
    testWidgets(
      'expense groups and dock fit narrow ${brightness.name} screens',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = fixtures.PreviewSession(),
            space = fixtures.PreviewSpace(fixtures.PreviewSession());
        space.rows['expenses'] = [
          {
            'id': 'expense',
            'author_id': 'one',
            'title': 'Dinner with my favourite person',
            'amount': 450.50,
            'currency': 'INR',
            'spent_on': '2026-10-20',
            'category': 'Food',
            'outing': 'Weekend trip',
          },
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sessionProvider.overrideWithValue(session),
              spaceProvider.overrideWithValue(space),
            ],
            child: MaterialApp(
              theme: usTheme(brightness),
              home: const ExpensesScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('By outing'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('By outing'));
        await tester.pumpAndSettle();
        expect(find.text('Weekend trip'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            theme: usTheme(brightness),
            home: Scaffold(
              bottomNavigationBar: UsDock(selected: 2, onSelect: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        space.dispose();
        session.dispose();
      },
    );
  }
  testWidgets('expense validation rejects nondecimal amounts before saving', (
    tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExpenseEditor())));
    await tester.enterText(find.byType(TextFormField).at(0), 'Dinner');
    await tester.enterText(find.byType(TextFormField).at(1), '12.345');
    await tester.ensureVisible(find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a positive amount, up to 2 decimal places'),
      findsOneWidget,
    );
  });
}
