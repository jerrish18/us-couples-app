import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:us/core/theme.dart';
import 'package:us/features/memories/memory_composer.dart';

void main() {
  testWidgets(
    'Upload explicitly chooses existing or new collection and keeps the caption',
    (tester) async {
      MemoryDraft? saved;
      final created = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: usTheme(Brightness.light),
          home: MemoryComposer(
            file: '/missing-preview-test.jpg',
            collections: const [
              {'id': 'date', 'title': 'Date nights'},
            ],
            onCreateCollection: (title) async {
              created.add(title);
              return 'new-id';
            },
            onSave: (draft) async {
              saved = draft;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('memory-caption')),
        'Our evening',
      );
      await tester.scrollUntilVisible(find.text('Date nights'), 180);
      await tester.tap(find.text('Date nights'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-memory-collection')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Our travels');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(created, ['Our travels']);
      await tester.scrollUntilVisible(
        find.byKey(const Key('save-memory')),
        180,
      );
      await tester.tap(find.byKey(const Key('save-memory')));
      await tester.pumpAndSettle();
      expect(saved?.caption, 'Our evening');
      expect(saved?.collectionId, 'new-id');
      expect(saved?.date.year, DateTime.now().year);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Saving failure preserves the draft so it can be retried', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: usTheme(Brightness.dark),
        home: MemoryComposer(
          file: '/missing-preview-test.jpg',
          collections: const [],
          onCreateCollection: (_) async => 'unused',
          onSave: (_) async {
            calls++;
            throw StateError('offline');
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('memory-caption')), 'Keep me');
    await tester.scrollUntilVisible(find.byKey(const Key('save-memory')), 180);
    await tester.tap(find.byKey(const Key('save-memory')));
    await tester.pumpAndSettle();
    expect(
      find.text('Your photo is still here. Try saving again.'),
      findsOneWidget,
    );
    expect(calls, 1);
    expect(find.byKey(const Key('save-memory')), findsOneWidget);
  });
}
