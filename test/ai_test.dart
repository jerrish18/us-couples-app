import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/design.dart';
import 'package:us/features/ai/ai_screen.dart';
import 'package:us/features/ai/ai_service.dart';

import 'ui_review_test.dart' as fixtures;

class FakeAi extends UsAi {
  FakeAi(super.space, {this.partner = true});
  bool partner;
  int requests = 0;
  String? requestedLanguage;
  @override
  Future<List<Map<String, dynamic>>> preferences() async => [
    {'user_id': 'one', 'enabled': true, 'share_history': true},
    {'user_id': 'two', 'enabled': partner, 'share_history': partner},
  ];
  @override
  Future<void> consent({required bool enabled, required bool history}) async {}
  @override
  Future<Map<String, dynamic>> ask({
    required String task,
    required String prompt,
    required String language,
    List<String> ids = const [],
    DateTime? from,
    DateTime? until,
    double? budget,
    int? minutes,
  }) async {
    requests++;
    requestedLanguage = language;
    return {
      'answer': 'A private suggestion',
      'suggestions': ['நான் உன்னை நேசிக்கிறேன்', 'Un kooda pesanum'],
      'draft': {'kind': 'none'},
      'sources': [],
      'coverage': 'No chat context',
    };
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'AI fits narrow ${brightness.name} theme and language selection is passed to service',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final space = fixtures.PreviewSpace(fixtures.PreviewSession()),
            ai = FakeAi(fixtures.PreviewSpace(fixtures.PreviewSession()));
        await tester.pumpWidget(
          MaterialApp(
            theme: usTheme(brightness),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 700),
                textScaler: TextScaler.linear(1.5),
              ),
              child: AiScreen(
                space: space,
                service: ai,
                initialTask: 'rewrite',
                initialText: 'I miss you',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Tanglish'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tanglish'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Generate privately'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate privately'));
        await tester.pumpAndSettle();
        expect(ai.requests, 1);
        expect(ai.requestedLanguage, 'Tanglish');
        await tester.scrollUntilVisible(
          find.text('A private suggestion'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('A private suggestion'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('shared assistance is disabled until partner opts in', (
    tester,
  ) async {
    final space = fixtures.PreviewSpace(fixtures.PreviewSession()),
        ai = FakeAi(
          fixtures.PreviewSpace(fixtures.PreviewSession()),
          partner: false,
        );
    await tester.pumpWidget(
      MaterialApp(
        home: AiScreen(
          space: space,
          service: ai,
          initialTask: 'together',
          initialText: 'Ideas?',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-generate')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('ai-generate')),
    );
    expect(button.onPressed, isNull);
    expect(ai.requests, 0);
  });
  testWidgets('date draft cannot save without an explicit date and title', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AiPlanEditor(
            draft: {
              'kind': 'date',
              'title': 'Dinner',
              'place': 'Chennai',
              'notes': '',
              'starts_at': '',
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save to Us'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('invalid date budget never calls the provider', (tester) async {
    final space = fixtures.PreviewSpace(fixtures.PreviewSession()),
        ai = FakeAi(fixtures.PreviewSpace(fixtures.PreviewSession()));
    await tester.pumpWidget(
      MaterialApp(
        home: AiScreen(
          space: space,
          service: ai,
          initialTask: 'date',
          initialText: 'A quiet date',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-budget')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ai-budget')), '0');
    tester.testTextInput.hide();
    await tester.scrollUntilVisible(
      find.byKey(const Key('ai-generate')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai-generate')));
    await tester.pumpAndSettle();
    expect(ai.requests, 0);
    expect(find.textContaining('Enter a budget'), findsOneWidget);
  });
}
